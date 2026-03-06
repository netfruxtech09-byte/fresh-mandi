import express from 'express';
import { z } from 'zod';

import { env } from '../../config/env.js';
import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok, fail } from '../../utils/response.js';
import { createNotification } from '../../utils/notifications.js';

export const paymentRouter = express.Router();
paymentRouter.use(authMiddleware);

async function finalizeOrderPaymentSuccess(client, { orderId, userId }) {
  const orderRes = await client.query(
    'SELECT id, total, status FROM orders WHERE id = $1 AND user_id = $2 FOR UPDATE',
    [orderId, userId],
  );
  if (!orderRes.rowCount) {
    return { ok: false, error: 'Order not found' };
  }

  const order = orderRes.rows[0];
  const firstConfirmation = order.status !== 'CONFIRMED';

  if (firstConfirmation) {
    await client.query(
      `UPDATE orders SET status = 'CONFIRMED' WHERE id = $1 AND user_id = $2`,
      [orderId, userId],
    );

    const reward = Number((Number(order.total) * 0.02).toFixed(2));
    if (reward > 0) {
      await client.query(
        `INSERT INTO wallet_transactions (user_id, amount, type, reason)
         VALUES ($1,$2,'CREDIT',$3)`,
        [userId, reward, `Cashback for order #${orderId}`],
      );
    }

    await createNotification({
      userId,
      title: 'Payment Success',
      body: `Payment received for order #${orderId}.`,
      kind: 'PAYMENT_SUCCESS',
      db: client,
    });
  }

  // Clear cart only when payment is successful.
  await client.query('DELETE FROM cart_items WHERE user_id = $1', [userId]);
  return { ok: true };
}

paymentRouter.post('/create-intent', async (req, res) => {
  const parsed = z
    .object({
      order_id: z.number(),
      amount: z.number().positive(),
      provider: z.enum(['RAZORPAY', 'STRIPE']),
    })
    .safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const order = await pool.query('SELECT * FROM orders WHERE id = $1 AND user_id = $2', [parsed.data.order_id, req.user.sub]);
  if (!order.rowCount) return fail(res, 404, 'Order not found');

  const reference = `PMT-${Date.now()}`;
  await pool.query(
    `INSERT INTO payments (order_id, user_id, provider, reference, amount, status)
     VALUES ($1,$2,$3,$4,$5,'INITIATED')`,
    [parsed.data.order_id, req.user.sub, parsed.data.provider, reference, parsed.data.amount],
  );

  return ok(
    res,
    {
      provider: parsed.data.provider,
      client_secret: 'mock_client_secret_for_sdk_integration',
      reference,
    },
    'Payment intent created',
  );
});

paymentRouter.post('/confirm', async (req, res) => {
  const parsed = z
    .object({
      reference: z.string().min(4),
      order_id: z.number(),
      status: z.enum(['SUCCESS', 'FAILED']),
    })
    .safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const payment = await client.query(
      'SELECT * FROM payments WHERE reference = $1 AND order_id = $2 AND user_id = $3',
      [parsed.data.reference, parsed.data.order_id, req.user.sub],
    );
    if (!payment.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Payment not found');
    }

    await client.query(
      'UPDATE payments SET status = $1, updated_at = NOW() WHERE id = $2',
      [parsed.data.status, payment.rows[0].id],
    );

    if (parsed.data.status === 'SUCCESS') {
      const finalized = await finalizeOrderPaymentSuccess(client, {
        orderId: parsed.data.order_id,
        userId: req.user.sub,
      });
      if (!finalized.ok) {
        await client.query('ROLLBACK');
        return fail(res, 404, finalized.error ?? 'Order not found');
      }
    }

    await client.query('COMMIT');
    return ok(res, true, 'Payment updated');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Payment update failed: ${error.message}`);
  } finally {
    client.release();
  }
});

paymentRouter.post('/mock-success', async (req, res) => {
  if (!env.paymentBypass) return fail(res, 403, 'Payment bypass is disabled');

  const parsed = z
    .object({
      order_id: z.number(),
      provider: z.enum(['RAZORPAY', 'STRIPE', 'MOCK']).optional(),
      reference: z.string().optional(),
    })
    .safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const reference = parsed.data.reference ?? `MOCK-${Date.now()}`;
  const provider = parsed.data.provider ?? 'MOCK';
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `INSERT INTO payments (order_id, user_id, provider, reference, amount, status)
       SELECT o.id, o.user_id, $2, $3, o.total, 'SUCCESS'
       FROM orders o
       WHERE o.id = $1 AND o.user_id = $4`,
      [parsed.data.order_id, provider, reference, req.user.sub],
    );

    const finalized = await finalizeOrderPaymentSuccess(client, {
      orderId: parsed.data.order_id,
      userId: req.user.sub,
    });
    if (!finalized.ok) {
      await client.query('ROLLBACK');
      return fail(res, 404, finalized.error ?? 'Order not found');
    }

    await client.query('COMMIT');
    return ok(
      res,
      { order_id: parsed.data.order_id, reference, status: 'SUCCESS' },
      'Payment mocked successfully',
    );
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Mock payment failed: ${error.message}`);
  } finally {
    client.release();
  }
});

import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { env } from '../../config/env.js';
import { ok, fail } from '../../utils/response.js';
import { getNumericSetting } from '../../utils/settings.js';
import { createNotification } from '../../utils/notifications.js';

export const orderRouter = express.Router();
orderRouter.use(authMiddleware);

const createOrderSchema = z.object({
  address_id: z.number(),
  slot_id: z.number(),
  payment_mode: z.enum(['COD', 'UPI']),
  coupon_code: z.string().optional(),
  wallet_redeem: z.number().min(0).optional(),
});

async function isCutoffPassed() {
  const cutOffHour = await getNumericSetting('cutoff_hour', env.cutOffHour);
  const now = new Date();
  return now.getHours() >= cutOffHour;
}

orderRouter.post('/', async (req, res) => {
  const parsed = createOrderSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');
  if (await isCutoffPassed()) return fail(res, 400, 'Cutoff passed. Next-day slots closed after 9 PM.');

  const { address_id, slot_id, payment_mode, coupon_code, wallet_redeem = 0 } = parsed.data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const cart = await client.query(
      `SELECT ci.product_id, ci.quantity, p.price
       FROM cart_items ci JOIN products p ON p.id = ci.product_id
       WHERE ci.user_id = $1`,
      [req.user.sub],
    );
    if (!cart.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 400, 'Cart is empty');
    }

    const address = await client.query(
      `SELECT id, sector_id, building_id
       FROM addresses
       WHERE id = $1 AND user_id = $2`,
      [address_id, req.user.sub],
    );
    if (!address.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Address not found');
    }

    const addressRow = address.rows[0];
    if (!addressRow.sector_id) {
      await client.query('ROLLBACK');
      return fail(res, 400, 'Address sector is not set. Please edit address and select sector.');
    }

    let routeId = null;
    if (addressRow.building_id) {
      const mappedRoute = await client.query(
        `SELECT r.id
         FROM route_buildings rb
         JOIN routes r ON r.id = rb.route_id
         WHERE rb.building_id = $1
           AND r.sector_id = $2
           AND r.active = true
         ORDER BY rb.stop_sequence ASC, r.id ASC
         LIMIT 1`,
        [addressRow.building_id, addressRow.sector_id],
      );
      routeId = mappedRoute.rows[0]?.id ?? null;
    }

    if (!routeId) {
      const fallbackRoute = await client.query(
        `SELECT id
         FROM routes
         WHERE sector_id = $1
           AND active = true
         ORDER BY id ASC
         LIMIT 1`,
        [addressRow.sector_id],
      );
      routeId = fallbackRoute.rows[0]?.id ?? null;
    }

    if (!routeId) {
      await client.query('ROLLBACK');
      return fail(res, 400, 'No active route found for selected sector. Ask admin to create route.');
    }

    const sequenceRow = await client.query(
      `SELECT COALESCE(MAX(route_sequence), 0)::int + 1 AS next_sequence
       FROM orders
       WHERE route_id = $1
         AND DATE(created_at) = CURRENT_DATE`,
      [routeId],
    );
    const routeSequence = sequenceRow.rows[0]?.next_sequence ?? 1;

    const subtotal = cart.rows.reduce((sum, i) => sum + Number(i.price) * Number(i.quantity), 0);
    let discount = 0;
    if (coupon_code) {
      const coupon = await client.query(
        'SELECT * FROM coupons WHERE code = $1 AND active = true AND expires_at > NOW()',
        [coupon_code],
      );
      if (coupon.rowCount) {
        discount = Math.min(subtotal, Number(coupon.rows[0].flat_discount || 0));
      }
    }

    const balanceRow = await client.query(
      'SELECT COALESCE(SUM(amount),0) AS balance FROM wallet_transactions WHERE user_id = $1',
      [req.user.sub],
    );
    const availableWallet = Number(balanceRow.rows[0].balance);
    if (wallet_redeem > availableWallet) {
      await client.query('ROLLBACK');
      return fail(res, 400, 'Insufficient wallet balance');
    }

    const gstPercent = await getNumericSetting('gst_percent', env.gstPercent);
    const gst = ((subtotal - discount) * gstPercent) / 100;
    const total = Math.max(0, subtotal - discount + gst - wallet_redeem);
    const status = payment_mode === 'UPI' ? 'PENDING_PAYMENT' : 'CONFIRMED';

    const order = await client.query(
      `INSERT INTO orders (
          user_id, address_id, slot_id, payment_mode, status,
          subtotal, discount, gst, wallet_redeem, total,
          sector_id, building_id, route_id, route_sequence
        )
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)
       RETURNING *`,
      [
        req.user.sub,
        address_id,
        slot_id,
        payment_mode,
        status,
        subtotal,
        discount,
        gst,
        wallet_redeem,
        total,
        addressRow.sector_id,
        addressRow.building_id ?? null,
        routeId,
        routeSequence,
      ],
    );
    const orderId = order.rows[0].id;

    for (const item of cart.rows) {
      await client.query(
        `INSERT INTO order_items (order_id, product_id, quantity, unit_price)
         VALUES ($1,$2,$3,$4)`,
        [orderId, item.product_id, item.quantity, item.price],
      );
    }

    if (wallet_redeem > 0) {
      await client.query(
        `INSERT INTO wallet_transactions (user_id, amount, type, reason)
         VALUES ($1,$2,'DEBIT',$3)`,
        [req.user.sub, -Math.abs(wallet_redeem), `Redeemed against order #${orderId}`],
      );
    }

    if (payment_mode === 'COD') {
      // For COD, order is confirmed immediately, so clear cart now.
      await client.query('DELETE FROM cart_items WHERE user_id = $1', [req.user.sub]);

      const reward = Number((total * 0.02).toFixed(2));
      if (reward > 0) {
        await client.query(
          `INSERT INTO wallet_transactions (user_id, amount, type, reason)
           VALUES ($1,$2,'CREDIT',$3)`,
          [req.user.sub, reward, `Cashback for order #${orderId}`],
        );
      }
      await createNotification({
        userId: req.user.sub,
        title: 'Order Confirmed',
        body: `Your order #${orderId} is confirmed.`,
        kind: 'ORDER_CONFIRMED',
        db: client,
      });
    }

    await client.query('COMMIT');
    return ok(res, order.rows[0], payment_mode === 'UPI' ? 'Order pending payment' : 'Order created');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Order creation failed: ${error.message}`);
  } finally {
    client.release();
  }
});

orderRouter.get('/', async (req, res) => {
  const rows = await pool.query(
    'SELECT * FROM orders WHERE user_id = $1 ORDER BY id DESC',
    [req.user.sub],
  );
  return ok(res, rows.rows);
});

orderRouter.get('/:id', async (req, res) => {
  const order = await pool.query(
    'SELECT * FROM orders WHERE id = $1 AND user_id = $2',
    [Number(req.params.id), req.user.sub],
  );
  const items = await pool.query(
    `SELECT oi.*, p.name FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id = $1`,
    [Number(req.params.id)],
  );
  return ok(res, { ...order.rows[0], items: items.rows });
});

orderRouter.post('/:id/reorder', async (req, res) => {
  const orderId = Number(req.params.id);
  if (!Number.isFinite(orderId) || orderId <= 0) {
    return fail(res, 400, 'Invalid order id');
  }

  const ownsOrder = await pool.query(
    'SELECT id FROM orders WHERE id = $1 AND user_id = $2',
    [orderId, req.user.sub],
  );
  if (!ownsOrder.rowCount) {
    return fail(res, 404, 'Order not found');
  }

  const items = await pool.query(
    `SELECT oi.product_id, oi.quantity
     FROM order_items oi
     JOIN products p ON p.id = oi.product_id
     WHERE oi.order_id = $1`,
    [orderId],
  );
  if (!items.rowCount) {
    return fail(res, 400, 'No reorderable items found for this order');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const i of items.rows) {
      await client.query(
        `INSERT INTO cart_items (user_id, product_id, quantity)
         VALUES ($1,$2,$3)
         ON CONFLICT (user_id, product_id)
         DO UPDATE SET quantity = cart_items.quantity + EXCLUDED.quantity`,
        [req.user.sub, i.product_id, i.quantity],
      );
    }
    await client.query('COMMIT');
    return ok(res, { items_added: items.rowCount }, 'Reordered to cart');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Reorder failed: ${error.message}`);
  } finally {
    client.release();
  }
});

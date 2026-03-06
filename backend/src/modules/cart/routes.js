import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok, fail } from '../../utils/response.js';

export const cartRouter = express.Router();
cartRouter.use(authMiddleware);

cartRouter.get('/', async (req, res) => {
  try {
    const row = await pool.query(
      `SELECT ci.id, ci.quantity, p.id AS product_id, p.name, p.price, p.unit, p.image_url
       FROM cart_items ci
       JOIN products p ON p.id = ci.product_id
       WHERE ci.user_id = $1`,
      [req.user.sub],
    );
    return ok(res, row.rows);
  } catch (error) {
    return fail(res, 500, `Failed to fetch cart: ${error.message}`);
  }
});

cartRouter.post('/items', async (req, res) => {
  try {
    const schema = z.object({ product_id: z.number(), quantity: z.number().min(1) });
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) return fail(res, 400, 'Invalid payload');
    const { product_id, quantity } = parsed.data;

    await pool.query(
      `INSERT INTO cart_items (user_id, product_id, quantity)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, product_id)
       DO UPDATE SET quantity = EXCLUDED.quantity, updated_at = NOW()`,
      [req.user.sub, product_id, quantity],
    );

    return ok(res, true, 'Item upserted');
  } catch (error) {
    return fail(res, 500, `Failed to update cart: ${error.message}`);
  }
});

cartRouter.delete('/items/:productId', async (req, res) => {
  try {
    await pool.query('DELETE FROM cart_items WHERE user_id = $1 AND product_id = $2', [req.user.sub, Number(req.params.productId)]);
    return ok(res, true, 'Item removed');
  } catch (error) {
    return fail(res, 500, `Failed to remove item: ${error.message}`);
  }
});

cartRouter.get('/suggestions', async (req, res) => {
  try {
    const rows = await pool.query(
      `SELECT id, name, price, unit, image_url FROM products
       WHERE id NOT IN (SELECT product_id FROM cart_items WHERE user_id = $1)
       ORDER BY RANDOM() LIMIT 5`,
      [req.user.sub],
    );
    return ok(res, rows.rows);
  } catch (error) {
    return fail(res, 500, `Failed to fetch suggestions: ${error.message}`);
  }
});

import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok, fail } from '../../utils/response.js';

export const userRouter = express.Router();
userRouter.use(authMiddleware);

userRouter.get('/me', async (req, res) => {
  const row = await pool.query('SELECT id, phone, name FROM users WHERE id = $1', [req.user.sub]);
  return ok(res, row.rows[0]);
});

userRouter.patch('/me', async (req, res) => {
  const schema = z.object({ name: z.string().min(2).optional(), phone: z.string().min(10).max(15).optional() });
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const updates = parsed.data;
  const row = await pool.query(
    `UPDATE users SET
      name = COALESCE($1, name),
      phone = COALESCE($2, phone),
      updated_at = NOW()
     WHERE id = $3
     RETURNING id, phone, name`,
    [updates.name ?? null, updates.phone ?? null, req.user.sub],
  );

  return ok(res, row.rows[0], 'Profile updated');
});

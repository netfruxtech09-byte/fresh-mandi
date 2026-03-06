import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok, fail } from '../../utils/response.js';

export const notificationRouter = express.Router();
notificationRouter.use(authMiddleware);

notificationRouter.post('/fcm-token', async (req, res) => {
  const parsed = z.object({ token: z.string().min(20) }).safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid token');

  await pool.query(
    `INSERT INTO user_devices (user_id, fcm_token)
     VALUES ($1,$2)
     ON CONFLICT (user_id, fcm_token) DO NOTHING`,
    [req.user.sub, parsed.data.token],
  );

  return ok(res, true, 'Token stored');
});

notificationRouter.get('/', async (req, res) => {
  const rows = await pool.query('SELECT * FROM notifications WHERE user_id = $1 ORDER BY id DESC', [req.user.sub]);
  return ok(res, rows.rows);
});

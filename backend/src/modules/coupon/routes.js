import express from 'express';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok } from '../../utils/response.js';

export const couponRouter = express.Router();
couponRouter.use(authMiddleware);

couponRouter.get('/validate/:code', async (req, res) => {
  const row = await pool.query(
    'SELECT * FROM coupons WHERE code = $1 AND active = true AND expires_at > NOW()',
    [req.params.code],
  );
  return ok(res, { valid: row.rowCount > 0, coupon: row.rows[0] ?? null });
});

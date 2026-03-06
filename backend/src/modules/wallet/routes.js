import express from 'express';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok } from '../../utils/response.js';

export const walletRouter = express.Router();
walletRouter.use(authMiddleware);

walletRouter.get('/', async (req, res) => {
  const summary = await pool.query('SELECT COALESCE(SUM(amount),0) AS balance FROM wallet_transactions WHERE user_id = $1', [req.user.sub]);
  const txns = await pool.query('SELECT * FROM wallet_transactions WHERE user_id = $1 ORDER BY id DESC', [req.user.sub]);
  return ok(res, { balance: Number(summary.rows[0].balance), transactions: txns.rows });
});

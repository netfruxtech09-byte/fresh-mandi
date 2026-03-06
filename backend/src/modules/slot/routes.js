import express from 'express';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok } from '../../utils/response.js';

export const slotRouter = express.Router();
slotRouter.use(authMiddleware);

slotRouter.get('/', async (_req, res) => {
  const rows = await pool.query('SELECT * FROM delivery_slots WHERE active = true ORDER BY id ASC');
  return ok(res, rows.rows);
});

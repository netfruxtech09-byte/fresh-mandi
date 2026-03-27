import jwt from 'jsonwebtoken';

import { env } from '../config/env.js';
import { pool } from '../db/pool.js';

export async function authMiddleware(req, res, next) {
  const auth = req.headers.authorization;
  if (!auth?.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'Unauthorized' });
  }

  try {
    const token = auth.replace('Bearer ', '');
    const payload = jwt.verify(token, env.jwtSecret);

    if (payload.role === 'admin') {
      req.user = payload;
      return next();
    }

    if (payload.role === 'delivery') {
      const executive = await pool.query(
        'SELECT id, active FROM delivery_executives WHERE id = $1',
        [payload.sub],
      );
      if (!executive.rowCount || !executive.rows[0].active) {
        return res.status(401).json({ message: 'Session expired. Please login again.' });
      }
      req.user = payload;
      return next();
    }

    if (payload.role === 'processing') {
      const staff = await pool.query(
        'SELECT id, active FROM processing_staff WHERE id = $1',
        [payload.sub],
      );
      if (!staff.rowCount || !staff.rows[0].active) {
        return res.status(401).json({ message: 'Session expired. Please login again.' });
      }
      req.user = payload;
      return next();
    }

    {
      const user = await pool.query('SELECT id FROM users WHERE id = $1', [payload.sub]);
      if (!user.rowCount) {
        return res.status(401).json({ message: 'Session expired. Please login again.' });
      }
    }

    req.user = payload;
    return next();
  } catch {
    return res.status(401).json({ message: 'Invalid token' });
  }
}

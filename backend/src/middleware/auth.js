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

    if (payload.role !== 'admin') {
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

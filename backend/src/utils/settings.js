import { pool } from '../db/pool.js';

export async function getNumericSetting(key, fallback) {
  const row = await pool.query('SELECT value FROM app_settings WHERE key = $1', [key]);
  if (!row.rowCount) return fallback;
  const parsed = Number(row.rows[0].value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

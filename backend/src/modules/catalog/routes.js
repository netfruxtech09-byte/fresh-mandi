import express from 'express';

import { pool } from '../../db/pool.js';
import { ok } from '../../utils/response.js';

export const catalogRouter = express.Router();

catalogRouter.get('/categories', async (_req, res) => {
  const rows = await pool.query(
    `SELECT DISTINCT ON (name, type) *
     FROM categories
     ORDER BY name, type, id ASC`,
  );
  return ok(res, rows.rows);
});

catalogRouter.get('/products', async (req, res) => {
  const { categoryId, subcategory, q } = req.query;
  const rows = await pool.query(
    `SELECT * FROM products
     WHERE ($1::int IS NULL OR category_id = $1)
       AND ($2::text IS NULL OR subcategory = $2)
       AND ($3::text IS NULL OR LOWER(name) LIKE LOWER('%' || $3 || '%'))
     ORDER BY id DESC`,
    [categoryId ? Number(categoryId) : null, subcategory ?? null, q ?? null],
  );
  return ok(res, rows.rows);
});

catalogRouter.get('/sectors', async (_req, res) => {
  const rows = await pool.query(
    `SELECT id, code, name
     FROM sectors
     WHERE active = true
     ORDER BY code ASC`,
  );
  return ok(res, rows.rows);
});

catalogRouter.get('/buildings', async (req, res) => {
  const sectorId = Number(req.query.sector_id);
  const rows = await pool.query(
    `SELECT id, sector_id, code, name
     FROM buildings
     WHERE active = true
       AND ($1::int IS NULL OR sector_id = $1::int)
     ORDER BY name ASC`,
    [Number.isFinite(sectorId) && sectorId > 0 ? sectorId : null],
  );
  return ok(res, rows.rows);
});

catalogRouter.get('/serviceability', async (_req, res) => {
  const rows = await pool.query(
    `SELECT key, value
     FROM app_settings
     WHERE key IN ('service_city', 'service_pincodes', 'gst_percent', 'cutoff_hour')`,
  );
  const map = Object.fromEntries(rows.rows.map((r) => [r.key, `${r.value ?? ''}`.trim()]));
  const city = map.service_city || 'Mohali';
  const pincodes = (map.service_pincodes || '')
    .split(',')
    .map((v) => v.trim())
    .filter(Boolean);
  const gstPercent = Number.parseFloat(map.gst_percent || '5');
  const cutoffHour = Number.parseInt(map.cutoff_hour || '21', 10);

  return ok(res, {
    city,
    state: 'Punjab',
    cities: [city],
    pincodes,
    gst_percent: Number.isFinite(gstPercent) ? gstPercent : 5,
    cutoff_hour: Number.isFinite(cutoffHour) ? cutoffHour : 21,
  });
});

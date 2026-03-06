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

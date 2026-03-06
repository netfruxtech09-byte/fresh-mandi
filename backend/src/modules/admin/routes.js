import bcrypt from 'bcryptjs';
import express from 'express';
import fs from 'fs/promises';
import jwt from 'jsonwebtoken';
import path from 'path';
import { fileURLToPath } from 'url';
import { z } from 'zod';

import { env } from '../../config/env.js';
import { authMiddleware } from '../../middleware/auth.js';
import { pool } from '../../db/pool.js';
import { queueNightReminderForAllUsers } from '../../utils/notifications.js';
import { ok, fail } from '../../utils/response.js';
import { getUploadsDir } from '../../utils/uploads.js';
import { isCloudinaryConfigured, uploadImageToCloudinary } from '../../utils/cloudinary.js';

export const adminRouter = express.Router();
const __dirname = path.dirname(fileURLToPath(import.meta.url));

const adminLoginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6),
});

const productSchema = z.object({
  category_id: z.coerce.number().int().positive(),
  name: z.string().min(2).max(150),
  subcategory: z.string().max(50).optional().nullable(),
  unit: z.string().min(1).max(50),
  price: z.coerce.number().positive(),
  image_url: z
    .union([
      z.string().url(),
      z.string().regex(/^\/uploads\/[a-zA-Z0-9._-]+$/),
    ])
    .optional()
    .nullable(),
  in_stock: z.boolean().optional(),
});

const updateOrderStatusSchema = z.object({
  status: z.enum(['PENDING_PAYMENT', 'CONFIRMED', 'PACKED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED']),
});

const settingSchema = z.object({
  key: z.string().min(2),
  value: z.string().min(1),
});

const uploadImageSchema = z.object({
  filename: z.string().min(1).max(200),
  mime_type: z.enum(['image/jpeg', 'image/png', 'image/webp']),
  data_base64: z.string().min(20),
});

function adminOnly(req, res, next) {
  if (req.user?.role !== 'admin') {
    return fail(res, 403, 'Admin access required');
  }
  return next();
}

adminRouter.post('/auth/login', async (req, res) => {
  try {
    const parsed = adminLoginSchema.safeParse(req.body);
    if (!parsed.success) return fail(res, 400, 'Invalid login payload');

    const { email, password } = parsed.data;
    const admin = await pool.query(
      'SELECT id, name, email, password_hash, active FROM admin_users WHERE LOWER(email) = LOWER($1)',
      [email],
    );

    if (!admin.rowCount) return fail(res, 401, 'Invalid email or password');

    const user = admin.rows[0];
    if (!user.active) return fail(res, 403, 'Admin account is disabled');

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) return fail(res, 401, 'Invalid email or password');

    const token = jwt.sign(
      {
        sub: user.id,
        role: 'admin',
        email: user.email,
        name: user.name,
      },
      env.jwtSecret,
      { expiresIn: '7d' },
    );

    return ok(
      res,
      {
        token,
        admin: { id: user.id, name: user.name, email: user.email },
      },
      'Admin authenticated',
    );
  } catch (error) {
    return fail(res, 500, `Admin login failed: ${error.message}`);
  }
});

adminRouter.use(authMiddleware);
adminRouter.use(adminOnly);

adminRouter.post('/uploads', async (req, res) => {
  const parsed = uploadImageSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid upload payload');

  try {
    const { filename, mime_type, data_base64 } = parsed.data;
    const ext = mime_type === 'image/png' ? 'png' : mime_type === 'image/webp' ? 'webp' : 'jpg';
    const safeName = filename.replace(/[^a-zA-Z0-9_.-]/g, '_').replace(/\.[^.]+$/, '');
    const finalName = `${Date.now()}_${safeName}.${ext}`;
    const buffer = Buffer.from(data_base64, 'base64');

    if (buffer.length > 5 * 1024 * 1024) {
      return fail(res, 400, 'Image too large. Max 5MB');
    }

    const cloudinaryReady = isCloudinaryConfigured();
    if (cloudinaryReady) {
      const uploaded = await uploadImageToCloudinary({
        buffer,
        mimeType: mime_type,
        filename: finalName,
      });
      return ok(res, { url: uploaded.url }, 'Image uploaded');
    }

    const isProductionRuntime = `${process.env.NODE_ENV}` === 'production' || Boolean(process.env.VERCEL);
    if (isProductionRuntime) {
      return fail(
        res,
        500,
        'Image storage is not configured. Set CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET.',
      );
    }

    const uploadsDir = getUploadsDir(path.resolve(__dirname, '../../..'));
    await fs.mkdir(uploadsDir, { recursive: true });
    await fs.writeFile(path.join(uploadsDir, finalName), buffer);

    return ok(res, { url: `/uploads/${finalName}` }, 'Image uploaded');
  } catch (error) {
    return fail(res, 500, `Image upload failed: ${error.message}`);
  }
});

adminRouter.get('/me', async (req, res) => {
  return ok(res, {
    id: req.user.sub,
    name: req.user.name,
    email: req.user.email,
    role: req.user.role,
  });
});

adminRouter.get('/dashboard', async (_req, res) => {
  const [users, orders, products, categories, revenue, recentOrders] = await Promise.all([
    pool.query('SELECT COUNT(*)::int AS count FROM users'),
    pool.query('SELECT COUNT(*)::int AS count FROM orders'),
    pool.query('SELECT COUNT(*)::int AS count FROM products'),
    pool.query('SELECT COUNT(*)::int AS count FROM categories'),
    pool.query("SELECT COALESCE(SUM(total),0)::numeric(12,2) AS amount FROM orders WHERE status <> 'CANCELLED'"),
    pool.query(
      `SELECT DATE(created_at) AS day, COUNT(*)::int AS order_count, COALESCE(SUM(total),0)::numeric(12,2) AS amount
       FROM orders
       WHERE created_at >= NOW() - INTERVAL '7 days'
       GROUP BY DATE(created_at)
       ORDER BY day ASC`,
    ),
  ]);

  return ok(res, {
    totals: {
      users: users.rows[0].count,
      orders: orders.rows[0].count,
      products: products.rows[0].count,
      categories: categories.rows[0].count,
      revenue: Number(revenue.rows[0].amount || 0),
    },
    orders_by_day: recentOrders.rows.map((r) => ({
      day: r.day,
      order_count: r.order_count,
      amount: Number(r.amount || 0),
    })),
  });
});

adminRouter.get('/products', async (req, res) => {
  const { q, category_id, in_stock } = req.query;
  const rows = await pool.query(
    `SELECT p.*, c.name AS category_name, c.type AS category_type
     FROM products p
     JOIN categories c ON c.id = p.category_id
     WHERE ($1::text IS NULL OR LOWER(p.name) LIKE LOWER('%' || $1 || '%'))
       AND ($2::int IS NULL OR p.category_id = $2)
       AND ($3::boolean IS NULL OR p.in_stock = $3)
     ORDER BY p.id DESC`,
    [q ?? null, category_id ? Number(category_id) : null, in_stock == null ? null : `${in_stock}` === 'true'],
  );

  return ok(res, rows.rows);
});

adminRouter.post('/products', async (req, res) => {
  const parsed = productSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid product payload');

  const payload = parsed.data;
  const row = await pool.query(
    `INSERT INTO products (category_id, name, subcategory, unit, price, image_url, in_stock)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     RETURNING *`,
    [
      payload.category_id,
      payload.name,
      payload.subcategory ?? null,
      payload.unit,
      payload.price,
      payload.image_url ?? null,
      payload.in_stock ?? true,
    ],
  );

  return ok(res, row.rows[0], 'Product created');
});

adminRouter.put('/products/:id', async (req, res) => {
  const parsed = productSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid product payload');

  const payload = parsed.data;
  const row = await pool.query(
    `UPDATE products
     SET category_id = $1,
         name = $2,
         subcategory = $3,
         unit = $4,
         price = $5,
         image_url = $6,
         in_stock = $7,
         updated_at = NOW()
     WHERE id = $8
     RETURNING *`,
    [
      payload.category_id,
      payload.name,
      payload.subcategory ?? null,
      payload.unit,
      payload.price,
      payload.image_url ?? null,
      payload.in_stock ?? true,
      Number(req.params.id),
    ],
  );

  if (!row.rowCount) return fail(res, 404, 'Product not found');
  return ok(res, row.rows[0], 'Product updated');
});

adminRouter.delete('/products/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return fail(res, 400, 'Invalid product id');

  const orderRef = await pool.query('SELECT 1 FROM order_items WHERE product_id = $1 LIMIT 1', [id]);
  if (orderRef.rowCount) {
    return fail(res, 400, 'Cannot delete product with existing order history. Mark out of stock instead.');
  }

  await pool.query('DELETE FROM cart_items WHERE product_id = $1', [id]);
  const deleted = await pool.query('DELETE FROM products WHERE id = $1 RETURNING id', [id]);
  if (!deleted.rowCount) return fail(res, 404, 'Product not found');
  return ok(res, true, 'Product deleted');
});

adminRouter.get('/orders', async (req, res) => {
  const { status } = req.query;
  const rows = await pool.query(
    `SELECT o.*, u.phone AS user_phone, u.name AS user_name, a.line1, a.city, a.state, a.pincode, s.label AS slot_label
     FROM orders o
     JOIN users u ON u.id = o.user_id
     JOIN addresses a ON a.id = o.address_id
     JOIN delivery_slots s ON s.id = o.slot_id
     WHERE ($1::text IS NULL OR o.status = $1)
     ORDER BY o.id DESC`,
    [status ?? null],
  );
  return ok(res, rows.rows);
});

adminRouter.get('/orders/:id', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return fail(res, 400, 'Invalid order id');

  const order = await pool.query(
    `SELECT o.*, u.phone AS user_phone, u.name AS user_name, a.line1, a.city, a.state, a.pincode, s.label AS slot_label
     FROM orders o
     JOIN users u ON u.id = o.user_id
     JOIN addresses a ON a.id = o.address_id
     JOIN delivery_slots s ON s.id = o.slot_id
     WHERE o.id = $1`,
    [id],
  );
  if (!order.rowCount) return fail(res, 404, 'Order not found');

  const items = await pool.query(
    `SELECT oi.*, p.name, p.unit, p.image_url
     FROM order_items oi
     JOIN products p ON p.id = oi.product_id
     WHERE oi.order_id = $1`,
    [id],
  );

  return ok(res, { ...order.rows[0], items: items.rows });
});

adminRouter.patch('/orders/:id/status', async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return fail(res, 400, 'Invalid order id');

  const parsed = updateOrderStatusSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid status payload');

  const row = await pool.query(
    'UPDATE orders SET status = $1 WHERE id = $2 RETURNING *',
    [parsed.data.status, id],
  );

  if (!row.rowCount) return fail(res, 404, 'Order not found');
  return ok(res, row.rows[0], 'Order status updated');
});

adminRouter.get('/settings', async (_req, res) => {
  const rows = await pool.query('SELECT key, value FROM app_settings ORDER BY key ASC');
  return ok(res, rows.rows);
});

adminRouter.put('/settings', async (req, res) => {
  const parsed = settingSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  await pool.query(
    `INSERT INTO app_settings (key, value)
     VALUES ($1,$2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [parsed.data.key, parsed.data.value],
  );
  return ok(res, true, 'Updated');
});

adminRouter.post('/jobs/night-reminder', async (_req, res) => {
  await queueNightReminderForAllUsers();
  return ok(res, true, 'Night reminder queued');
});

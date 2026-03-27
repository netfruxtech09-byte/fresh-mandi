import bcrypt from 'bcryptjs';
import express from 'express';
import fs from 'fs/promises';
import jwt from 'jsonwebtoken';
import path from 'path';
import { fileURLToPath } from 'url';
import { z } from 'zod';

import { env } from '../../config/env.js';
import { authMiddleware } from '../../middleware/auth.js';
import { requirePermission, resolveAdminPermissions } from '../../middleware/admin-permissions.js';
import { pool } from '../../db/pool.js';
import { queueNightReminderForAllUsers } from '../../utils/notifications.js';
import { ok, fail } from '../../utils/response.js';
import { getUploadsDir } from '../../utils/uploads.js';
import { isCloudinaryConfigured, uploadImageToCloudinary } from '../../utils/cloudinary.js';
import { normalizeIndianPhone } from '../../utils/sms.js';

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

const deliveryExecutiveSchema = z.object({
  name: z.string().min(2).max(120),
  phone: z.string().min(10).max(20),
  employee_code: z.string().min(2).max(40).optional().nullable(),
  active: z.boolean().optional(),
});

const processingStaffSchema = z.object({
  name: z.string().min(2).max(120),
  phone: z.string().min(10).max(20),
  employee_code: z.string().min(2).max(40).optional().nullable(),
  active: z.boolean().optional(),
});

const assignmentSchema = z.object({
  business_date: z.string().min(1),
  route_id: z.coerce.number().int().positive(),
  delivery_executive_id: z.coerce.number().int().positive(),
});

const createRouteSchema = z.object({
  route_code: z.string().min(2).max(40),
  sector_id: z.coerce.number().int().positive(),
  max_orders: z.coerce.number().int().positive().default(120),
  sequence_logic: z.string().min(2).max(80).default('tower_then_flat'),
});

function adminOnly(req, res, next) {
  if (req.user?.role !== 'admin') {
    return fail(res, 403, 'Admin access required');
  }
  return next();
}

async function resolveAdminRoles(adminId) {
  const roles = await pool.query(
    `SELECT r.code
     FROM admin_user_roles aur
     JOIN roles r ON r.id = aur.role_id
     WHERE aur.admin_user_id = $1`,
    [adminId],
  );

  if (!roles.rowCount) {
    return ['SUPER_ADMIN'];
  }

  return roles.rows.map((r) => r.code);
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

    const roles = await resolveAdminRoles(user.id);
    const permissions = roles.includes('SUPER_ADMIN') ? ['*'] : await resolveAdminPermissions(user.id);

    const token = jwt.sign(
      {
        sub: user.id,
        role: 'admin',
        role_code: roles[0] ?? 'SUPER_ADMIN',
        roles,
        permissions,
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
        admin: { id: user.id, name: user.name, email: user.email, roles, permissions },
      },
      'Admin authenticated',
    );
  } catch (error) {
    return fail(res, 500, `Admin login failed: ${error.message}`);
  }
});

adminRouter.use(authMiddleware);
adminRouter.use(adminOnly);

adminRouter.post('/uploads', requirePermission('products:write'), async (req, res) => {
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
  const roles = Array.isArray(req.user.roles) ? req.user.roles : await resolveAdminRoles(req.user.sub);
  const permissions = roles.includes('SUPER_ADMIN')
    ? ['*']
    : (Array.isArray(req.user.permissions) ? req.user.permissions : await resolveAdminPermissions(req.user.sub));

  return ok(res, {
    id: req.user.sub,
    name: req.user.name,
    email: req.user.email,
    role: req.user.role,
    role_code: req.user.role_code ?? roles[0] ?? 'SUPER_ADMIN',
    roles,
    permissions,
  });
});

adminRouter.get('/rbac/roles', requirePermission('users:manage_roles'), async (_req, res) => {
  const roles = await pool.query(
    `SELECT r.id, r.code, r.name, r.description,
            COALESCE(
              JSON_AGG(
                JSON_BUILD_OBJECT(
                  'id', p.id,
                  'code', p.code,
                  'module', p.module,
                  'action', p.action
                )
              ) FILTER (WHERE p.id IS NOT NULL),
              '[]'::json
            ) AS permissions
     FROM roles r
     LEFT JOIN role_permissions rp ON rp.role_id = r.id
     LEFT JOIN permissions p ON p.id = rp.permission_id
     GROUP BY r.id
     ORDER BY r.id`,
  );

  return ok(res, roles.rows);
});

adminRouter.get('/rbac/admin-users', requirePermission('users:manage_roles'), async (_req, res) => {
  const admins = await pool.query(
    `SELECT a.id, a.name, a.email, a.active,
            COALESCE(
              JSON_AGG(
                JSON_BUILD_OBJECT('id', r.id, 'code', r.code, 'name', r.name)
              ) FILTER (WHERE r.id IS NOT NULL),
              '[]'::json
            ) AS roles
     FROM admin_users a
     LEFT JOIN admin_user_roles aur ON aur.admin_user_id = a.id
     LEFT JOIN roles r ON r.id = aur.role_id
     GROUP BY a.id
     ORDER BY a.id DESC`,
  );
  return ok(res, admins.rows);
});

adminRouter.get('/dashboard', requirePermission('dashboard:read'), async (_req, res) => {
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

adminRouter.get('/products', requirePermission('products:read'), async (req, res) => {
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

adminRouter.post('/products', requirePermission('products:write'), async (req, res) => {
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

adminRouter.put('/products/:id', requirePermission('products:write'), async (req, res) => {
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

adminRouter.delete('/products/:id', requirePermission('products:write'), async (req, res) => {
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

adminRouter.get('/orders', requirePermission('orders:read'), async (req, res) => {
  const { status, business_date, sector_id, route_id } = req.query;
  const rows = await pool.query(
    `SELECT o.*,
            u.phone AS user_phone,
            u.name AS user_name,
            a.line1,
            a.city,
            a.state,
            a.pincode,
            s.label AS slot_label,
            sec.code AS sector_code,
            sec.name AS sector_name,
            b.code AS building_code,
            b.name AS building_name,
            r.route_code,
            COUNT(oi.id)::int AS item_count,
            COALESCE(
              STRING_AGG(
                p.name || ' x' || oi.quantity::text,
                ', ' ORDER BY oi.id
              ),
              ''
            ) AS items_summary
     FROM orders o
     JOIN users u ON u.id = o.user_id
     JOIN addresses a ON a.id = o.address_id
     JOIN delivery_slots s ON s.id = o.slot_id
     LEFT JOIN sectors sec ON sec.id = o.sector_id
     LEFT JOIN buildings b ON b.id = o.building_id
     LEFT JOIN routes r ON r.id = o.route_id
     LEFT JOIN order_items oi ON oi.order_id = o.id
     LEFT JOIN products p ON p.id = oi.product_id
     WHERE ($1::text IS NULL OR o.status = $1)
       AND ($2::date IS NULL OR DATE(o.created_at) = $2::date)
       AND ($3::int IS NULL OR o.sector_id = $3::int)
       AND ($4::int IS NULL OR o.route_id = $4::int)
     GROUP BY o.id, u.phone, u.name, a.line1, a.city, a.state, a.pincode, s.label, sec.code, sec.name, b.code, b.name, r.route_code
     ORDER BY o.id DESC`,
    [status ?? null, business_date ?? null, sector_id ? Number(sector_id) : null, route_id ? Number(route_id) : null],
  );
  return ok(res, rows.rows);
});

adminRouter.get('/orders/:id', requirePermission('orders:read'), async (req, res) => {
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

adminRouter.patch('/orders/:id/status', requirePermission('orders:update_status'), async (req, res) => {
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

adminRouter.get('/modules/procurement/summary', requirePermission('purchase:read'), async (_req, res) => {
  const todaySummary = await pool.query(
    `SELECT COUNT(*)::int AS rows,
            COALESCE(SUM(final_purchase_qty),0)::numeric(12,3) AS total_qty,
            COUNT(*) FILTER (WHERE purchased = true)::int AS purchased_rows
     FROM purchase_summary
     WHERE business_date = CURRENT_DATE`,
  );

  const top = await pool.query(
    `SELECT p.name,
            ps.required_qty,
            ps.wastage_pct,
            ps.final_purchase_qty,
            COALESCE(ps.supplier_name, '-') AS supplier_name,
            ps.purchased
     FROM purchase_summary ps
     JOIN products p ON p.id = ps.product_id
     WHERE ps.business_date = CURRENT_DATE
     ORDER BY ps.final_purchase_qty DESC
     LIMIT 10`,
  );

  return ok(res, { overview: todaySummary.rows[0], items: top.rows });
});

adminRouter.get('/modules/inventory/summary', requirePermission('inventory:read'), async (_req, res) => {
  const overview = await pool.query(
    `SELECT COUNT(*)::int AS rows,
            COALESCE(SUM(remaining_qty),0)::numeric(12,3) AS total_remaining,
            COUNT(*) FILTER (WHERE remaining_qty <= low_stock_threshold)::int AS low_stock_items,
            COALESCE(SUM(wastage_qty),0)::numeric(12,3) AS total_wastage
     FROM inventory
     WHERE stock_date = CURRENT_DATE`,
  );

  const lowStock = await pool.query(
    `SELECT p.name, i.remaining_qty, i.low_stock_threshold, i.warehouse_code
     FROM inventory i
     JOIN products p ON p.id = i.product_id
     WHERE i.stock_date = CURRENT_DATE
       AND i.remaining_qty <= i.low_stock_threshold
     ORDER BY (i.remaining_qty - i.low_stock_threshold) ASC
     LIMIT 10`,
  );

  return ok(res, { overview: overview.rows[0], low_stock: lowStock.rows });
});

adminRouter.get('/modules/packing/summary', requirePermission('packing:read'), async (_req, res) => {
  const overview = await pool.query(
    `SELECT COUNT(*)::int AS packed_logs_today,
            COUNT(DISTINCT route_id)::int AS active_routes,
            COUNT(DISTINCT crate_number)::int AS crates_used
     FROM packing_log
     WHERE DATE(packed_at) = CURRENT_DATE`,
  );

  const routes = await pool.query(
    `SELECT r.route_code,
            COUNT(pl.id)::int AS packed_orders,
            COUNT(DISTINCT pl.crate_number)::int AS crate_count
     FROM packing_log pl
     LEFT JOIN routes r ON r.id = pl.route_id
     WHERE DATE(pl.packed_at) = CURRENT_DATE
     GROUP BY r.route_code
     ORDER BY packed_orders DESC
     LIMIT 10`,
  );

  return ok(res, { overview: overview.rows[0], routes: routes.rows });
});

adminRouter.get('/modules/delivery/summary', requirePermission('delivery:read'), async (_req, res) => {
  const overview = await pool.query(
    `SELECT COUNT(*)::int AS logs_today,
            COUNT(*) FILTER (WHERE status = 'DELIVERED')::int AS delivered,
            COUNT(*) FILTER (WHERE status = 'NOT_AVAILABLE')::int AS not_available,
            COUNT(*) FILTER (WHERE status = 'RESCHEDULED')::int AS rescheduled,
            COUNT(*) FILTER (WHERE status = 'CANCELLED')::int AS cancelled
     FROM delivery_log
     WHERE DATE(created_at) = CURRENT_DATE`,
  );

  const byRoute = await pool.query(
    `SELECT COALESCE(r.route_code, '-') AS route_code,
            COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE dl.status = 'DELIVERED')::int AS delivered
     FROM delivery_log dl
     LEFT JOIN routes r ON r.id = dl.route_id
     WHERE DATE(dl.created_at) = CURRENT_DATE
     GROUP BY r.route_code
     ORDER BY total DESC
     LIMIT 10`,
  );

  return ok(res, { overview: overview.rows[0], routes: byRoute.rows });
});

adminRouter.get('/modules/accounting/summary', requirePermission('payments:read'), async (_req, res) => {
  const overview = await pool.query(
    `SELECT COUNT(*)::int AS total_payments,
            COUNT(*) FILTER (WHERE status = 'PENDING')::int AS pending,
            COUNT(*) FILTER (WHERE status = 'PAID')::int AS paid,
            COALESCE(SUM(amount),0)::numeric(12,2) AS amount_total,
            COALESCE(SUM(amount) FILTER (WHERE status = 'PAID'),0)::numeric(12,2) AS amount_paid
     FROM payments
     WHERE DATE(created_at) = CURRENT_DATE`,
  );

  const byProvider = await pool.query(
    `SELECT provider, COUNT(*)::int AS count, COALESCE(SUM(amount),0)::numeric(12,2) AS amount
     FROM payments
     GROUP BY provider
     ORDER BY amount DESC`,
  );

  return ok(res, { overview: overview.rows[0], providers: byProvider.rows });
});

adminRouter.get('/modules/customers/summary', requirePermission('customers:read'), async (_req, res) => {
  const overview = await pool.query(
    `SELECT COUNT(*)::int AS total_customers
     FROM users`,
  );

  const topCustomers = await pool.query(
    `SELECT u.id, COALESCE(u.name, '-') AS name, u.phone,
            COUNT(o.id)::int AS total_orders,
            COALESCE(SUM(o.total),0)::numeric(12,2) AS revenue
     FROM users u
     LEFT JOIN orders o ON o.user_id = u.id
     GROUP BY u.id
     ORDER BY total_orders DESC, revenue DESC
     LIMIT 10`,
  );

  return ok(res, { overview: overview.rows[0], top_customers: topCustomers.rows });
});

adminRouter.get('/modules/routes', requirePermission('routes:read'), async (_req, res) => {
  const sectors = await pool.query('SELECT id, code, name FROM sectors ORDER BY code ASC');
  const routes = await pool.query(
    `SELECT r.id, r.route_code, r.max_orders, r.sequence_logic, r.active,
            s.code AS sector_code, s.name AS sector_name,
            COUNT(rb.building_id)::int AS buildings_mapped
     FROM routes r
     JOIN sectors s ON s.id = r.sector_id
     LEFT JOIN route_buildings rb ON rb.route_id = r.id
     GROUP BY r.id, s.code, s.name
     ORDER BY r.route_code ASC`,
  );
  return ok(res, { sectors: sectors.rows, routes: routes.rows });
});

adminRouter.post('/modules/routes', requirePermission('routes:write'), async (req, res) => {
  const parsed = createRouteSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid route payload');

  const payload = parsed.data;
  const created = await pool.query(
    `INSERT INTO routes (route_code, sector_id, max_orders, sequence_logic, active)
     VALUES ($1, $2, $3, $4, true)
     RETURNING *`,
    [payload.route_code, payload.sector_id, payload.max_orders, payload.sequence_logic],
  );
  return ok(res, created.rows[0], 'Route created');
});

adminRouter.get('/modules/reports', requirePermission('reports:read'), async (_req, res) => {
  const rows = await pool.query(
    `SELECT report_type, business_date, storage_url, created_at
     FROM reports
     ORDER BY business_date DESC, created_at DESC
     LIMIT 30`,
  );
  return ok(res, rows.rows);
});

adminRouter.get('/modules/notifications', requirePermission('dashboard:read'), async (_req, res) => {
  const rows = await pool.query(
    `SELECT id, title, body, kind, created_at
     FROM notifications
     ORDER BY created_at DESC
     LIMIT 30`,
  );
  return ok(res, rows.rows);
});

adminRouter.get('/settings', requirePermission('settings:read'), async (_req, res) => {
  const rows = await pool.query('SELECT key, value FROM app_settings ORDER BY key ASC');
  return ok(res, rows.rows);
});

adminRouter.put('/settings', requirePermission('settings:write'), async (req, res) => {
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

adminRouter.post('/jobs/night-reminder', requirePermission('orders:freeze'), async (_req, res) => {
  await queueNightReminderForAllUsers();
  return ok(res, true, 'Night reminder queued');
});

adminRouter.get('/delivery/executives', requirePermission('delivery:read'), async (_req, res) => {
  const rows = await pool.query(
    `SELECT id, name, phone, employee_code, device_id, active, last_login_at, created_at, updated_at
     FROM delivery_executives
     ORDER BY id DESC`,
  );
  return ok(res, rows.rows);
});

adminRouter.post('/delivery/executives', requirePermission('delivery:write'), async (req, res) => {
  const parsed = deliveryExecutiveSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid delivery executive payload');

  const p = parsed.data;
  const normalizedPhone = normalizeIndianPhone(p.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const customer = await pool.query('SELECT id FROM users WHERE phone = $1', [normalizedPhone]);
  if (customer.rowCount) {
    return fail(
      res,
      409,
      'This phone is already registered as a customer. Use a separate number for delivery executive.',
    );
  }

  try {
    const row = await pool.query(
      `INSERT INTO delivery_executives (name, phone, employee_code, active)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, phone, employee_code, active, created_at`,
      [p.name, normalizedPhone, p.employee_code ?? null, p.active ?? true],
    );
    return ok(res, row.rows[0], 'Delivery executive created');
  } catch (error) {
    if (error?.code === '23505') {
      return fail(res, 409, 'Delivery executive already exists with this phone or employee code');
    }
    throw error;
  }
});

adminRouter.get('/processing/staff', requirePermission('delivery:read'), async (_req, res) => {
  const rows = await pool.query(
    `SELECT id, name, phone, employee_code, device_id, active, last_login_at, created_at, updated_at
     FROM processing_staff
     ORDER BY id DESC`,
  );
  return ok(res, rows.rows);
});

adminRouter.post('/processing/staff', requirePermission('delivery:write'), async (req, res) => {
  const parsed = processingStaffSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid processing staff payload');

  const p = parsed.data;
  const normalizedPhone = normalizeIndianPhone(p.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const customer = await pool.query('SELECT id FROM users WHERE phone = $1', [normalizedPhone]);
  if (customer.rowCount) {
    return fail(
      res,
      409,
      'This phone is already registered as a customer. Use a separate number for processing staff.',
    );
  }

  const deliveryExecutive = await pool.query(
    'SELECT id FROM delivery_executives WHERE phone = $1',
    [normalizedPhone],
  );
  if (deliveryExecutive.rowCount) {
    return fail(
      res,
      409,
      'This phone is already registered as a delivery executive. Use a separate number for processing staff.',
    );
  }

  try {
    const row = await pool.query(
      `INSERT INTO processing_staff (name, phone, employee_code, active)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, phone, employee_code, active, created_at`,
      [p.name, normalizedPhone, p.employee_code ?? null, p.active ?? true],
    );
    return ok(res, row.rows[0], 'Processing staff created');
  } catch (error) {
    if (error?.code === '23505') {
      return fail(res, 409, 'Processing staff already exists with this phone or employee code');
    }
    throw error;
  }
});

adminRouter.get('/delivery/assignments', requirePermission('delivery:read'), async (req, res) => {
  const date = `${req.query.business_date ?? ''}` || null;
  const rows = await pool.query(
    `SELECT a.id, a.business_date, a.status, a.route_start_time, a.route_end_time,
            r.id AS route_id, r.route_code,
            s.name AS sector_name, s.code AS sector_code,
            d.id AS delivery_executive_id, d.name AS delivery_executive_name, d.phone AS delivery_executive_phone
     FROM delivery_route_assignments a
     JOIN routes r ON r.id = a.route_id
     JOIN sectors s ON s.id = r.sector_id
     JOIN delivery_executives d ON d.id = a.delivery_executive_id
     WHERE ($1::date IS NULL OR a.business_date = $1::date)
     ORDER BY a.business_date DESC, a.id DESC`,
    [date],
  );
  return ok(res, rows.rows);
});

adminRouter.get('/delivery/route-monitor', requirePermission('delivery:read'), async (req, res) => {
  const dateRaw = `${req.query.business_date ?? ''}`.trim();
  const businessDate = dateRaw || new Date().toISOString().slice(0, 10);
  const sectorId = Number(req.query.sector_id);
  const routeId = Number(req.query.route_id);

  const rows = await pool.query(
    `SELECT
        a.id AS assignment_id,
        r.id AS route_id,
        r.route_code,
        s.id AS sector_id,
        s.code AS sector_code,
        s.name AS sector_name,
        a.status AS assignment_status,
        a.route_start_time,
        a.route_end_time,
        d.name AS delivery_executive_name,
        d.phone AS delivery_executive_phone,
        COUNT(o.id)::int AS total_orders,
        COUNT(*) FILTER (WHERE COALESCE(o.packing_status::text, 'PLACED') = 'PACKED')::int AS packed_orders,
        COUNT(*) FILTER (WHERE COALESCE(o.delivery_status::text, 'PENDING') = 'OUT_FOR_DELIVERY')::int AS out_for_delivery,
        COUNT(*) FILTER (WHERE COALESCE(o.delivery_status::text, 'PENDING') = 'DELIVERED')::int AS delivered_orders,
        COUNT(*) FILTER (
          WHERE COALESCE(o.delivery_status::text, 'PENDING') NOT IN ('DELIVERED','CANCELLED')
            AND o.failure_reason IS NULL
        )::int AS pending_orders
     FROM routes r
     JOIN sectors s ON s.id = r.sector_id
     LEFT JOIN delivery_route_assignments a
       ON a.route_id = r.id
      AND a.business_date = $1::date
     LEFT JOIN delivery_executives d ON d.id = a.delivery_executive_id
     LEFT JOIN orders o
       ON o.route_id = r.id
      AND o.created_at >= $1::date
      AND o.created_at < ($1::date + INTERVAL '1 day')
     WHERE r.active = TRUE
       AND ($2::int IS NULL OR s.id = $2::int)
       AND ($3::int IS NULL OR r.id = $3::int)
     GROUP BY r.id, r.route_code, s.id, s.code, s.name, a.status, a.route_start_time, a.route_end_time, d.name, d.phone
     ORDER BY s.code ASC, r.route_code ASC`,
    [
      businessDate,
      Number.isFinite(sectorId) && sectorId > 0 ? sectorId : null,
      Number.isFinite(routeId) && routeId > 0 ? routeId : null,
    ],
  );

  return ok(res, rows.rows);
});

adminRouter.post('/delivery/assignments/:id/reopen', requirePermission('delivery:write'), async (req, res) => {
  const assignmentId = Number(req.params.id);
  if (!Number.isFinite(assignmentId) || assignmentId <= 0) {
    return fail(res, 400, 'Invalid assignment id');
  }

  const current = await pool.query(
    `SELECT id, status
     FROM delivery_route_assignments
     WHERE id = $1
     LIMIT 1`,
    [assignmentId],
  );
  if (!current.rowCount) return fail(res, 404, 'Assignment not found');

  const status = `${current.rows[0].status ?? ''}`.toUpperCase();
  if (status === 'SETTLEMENT_DONE') {
    return fail(res, 409, 'Cannot reopen route after settlement is completed');
  }

  const updated = await pool.query(
    `UPDATE delivery_route_assignments
     SET status = 'IN_PROGRESS',
         route_end_time = NULL,
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [assignmentId],
  );

  return ok(res, updated.rows[0], 'Route reopened');
});

adminRouter.post('/delivery/assignments', requirePermission('delivery:write'), async (req, res) => {
  const parsed = assignmentSchema.safeParse(req.body);
  if (!parsed.success) {
    const issue = parsed.error.issues?.[0];
    const reason = issue ? `${issue.path.join('.') || 'field'}: ${issue.message}` : 'Invalid payload';
    return fail(res, 400, `Invalid assignment payload (${reason})`);
  }

  const p = parsed.data;
  const parsedDate = new Date(p.business_date);
  if (Number.isNaN(parsedDate.getTime())) {
    return fail(res, 400, 'Invalid business date');
  }
  const businessDate = parsedDate.toISOString().slice(0, 10);

  const row = await pool.query(
    `INSERT INTO delivery_route_assignments (business_date, route_id, delivery_executive_id, status)
     VALUES ($1::date, $2, $3, 'ASSIGNED')
     ON CONFLICT (business_date, route_id)
     DO UPDATE SET delivery_executive_id = EXCLUDED.delivery_executive_id, status = 'ASSIGNED', updated_at = NOW()
     RETURNING *`,
    [businessDate, p.route_id, p.delivery_executive_id],
  );
  return ok(res, row.rows[0], 'Delivery assignment saved');
});

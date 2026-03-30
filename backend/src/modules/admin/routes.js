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
import { getNumericSetting } from '../../utils/settings.js';

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

const procurementActionSchema = z.object({
  business_date: z.string().optional(),
});

const inventoryAdjustSchema = z.object({
  product_id: z.coerce.number().int().positive(),
  warehouse_code: z.string().min(2).max(40).default('WH-01'),
  operation: z.enum(['OPENING', 'PURCHASE', 'ALLOCATE', 'DAMAGED', 'WASTAGE']),
  quantity: z.coerce.number().positive(),
  low_stock_threshold: z.coerce.number().nonnegative().optional(),
});

const goodsReceiptSchema = z.object({
  supplier_name: z.string().min(2).max(160),
  invoice_number: z.string().min(2).max(80),
  product_id: z.coerce.number().int().positive(),
  quantity_received: z.coerce.number().positive(),
  rate_per_kg: z.coerce.number().nonnegative(),
});

const qualityApprovalSchema = z.object({
  goods_received_item_id: z.coerce.number().int().positive(),
  good_quantity: z.coerce.number().nonnegative(),
  damaged_quantity: z.coerce.number().nonnegative(),
  waste_quantity: z.coerce.number().nonnegative(),
  damage_reason: z.string().max(300).optional().nullable(),
});

const packingScanSchema = z.object({
  route_id: z.coerce.number().int().positive(),
  barcode: z.string().min(1),
});

const printRouteLabelsSchema = z.object({
  route_id: z.coerce.number().int().positive(),
});

const customerCreditSchema = z.object({
  points: z.coerce.number().int(),
});

const customerBlockSchema = z.object({
  blocked: z.boolean(),
});

const routeBuildingSchema = z.object({
  route_id: z.coerce.number().int().positive(),
  building_id: z.coerce.number().int().positive(),
  stop_sequence: z.coerce.number().int().positive().default(1),
});

const reportGenerateSchema = z.object({
  report_type: z.string().min(3).max(80),
  business_date: z.string().optional(),
  format: z.enum(['CSV', 'PDF']).default('CSV'),
});

function normalizeBusinessDate(value) {
  const raw = `${value ?? ''}`.trim();
  if (!raw) return new Date().toISOString().slice(0, 10);
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;
  const parsed = new Date(raw);
  if (Number.isNaN(parsed.getTime())) return new Date().toISOString().slice(0, 10);
  return parsed.toISOString().slice(0, 10);
}

function barcodeToOrderId(raw) {
  const text = `${raw ?? ''}`.trim();
  if (!text) return null;
  const direct = Number(text);
  if (Number.isFinite(direct) && direct > 0) return direct;
  const match = text.match(/(\d+)/);
  if (!match) return null;
  const id = Number(match[1]);
  return Number.isFinite(id) && id > 0 ? id : null;
}

function escapeCsv(value) {
  const text = `${value ?? ''}`;
  if (!/[",\n]/.test(text)) return text;
  return `"${text.replace(/"/g, '""')}"`;
}

function csvExportPayload({ filename, headers, rows }) {
  const csv = [headers.map(escapeCsv).join(','), ...rows.map((row) => row.map(escapeCsv).join(','))].join('\n');
  return {
    filename,
    mime_type: 'text/csv',
    content_base64: Buffer.from(csv, 'utf8').toString('base64'),
  };
}

function buildSimplePdfBuffer(title, lines) {
  const escapePdf = (input) => `${input ?? ''}`.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
  const streamLines = [
    'BT',
    '/F1 16 Tf',
    '50 780 Td',
    `(${escapePdf(title)}) Tj`,
    '/F1 10 Tf',
  ];
  let cursorY = 760;
  for (const line of lines.slice(0, 55)) {
    streamLines.push(`1 0 0 1 50 ${cursorY} Tm`);
    streamLines.push(`(${escapePdf(line)}) Tj`);
    cursorY -= 12;
  }
  streamLines.push('ET');
  const stream = streamLines.join('\n');
  const objects = [];
  const pushObject = (body) => {
    objects.push(body);
    return objects.length;
  };
  pushObject('<< /Type /Catalog /Pages 2 0 R >>');
  pushObject('<< /Type /Pages /Kids [3 0 R] /Count 1 >>');
  pushObject('<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>');
  pushObject(`<< /Length ${Buffer.byteLength(stream, 'utf8')} >>\nstream\n${stream}\nendstream`);
  pushObject('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');

  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (let i = 0; i < objects.length; i += 1) {
    offsets.push(Buffer.byteLength(pdf, 'utf8'));
    pdf += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`;
  }
  const xrefOffset = Buffer.byteLength(pdf, 'utf8');
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (let i = 1; i < offsets.length; i += 1) {
    pdf += `${String(offsets[i]).padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF`;
  return Buffer.from(pdf, 'utf8');
}

function pdfExportPayload({ filename, title, lines }) {
  return {
    filename,
    mime_type: 'application/pdf',
    content_base64: buildSimplePdfBuffer(title, lines).toString('base64'),
  };
}

async function generatePurchaseSummaryForDate(client, businessDate, adminUserId) {
  const wastagePct = await getNumericSetting('procurement_wastage_pct', 5);
  const rows = await client.query(
    `SELECT oi.product_id,
            COALESCE(SUM(oi.quantity), 0)::numeric(12,3) AS required_qty
     FROM orders o
     JOIN order_items oi ON oi.order_id = o.id
     WHERE DATE(o.created_at) = $1::date
       AND COALESCE(o.status, '') <> 'CANCELLED'
     GROUP BY oi.product_id`,
    [businessDate],
  );

  await client.query('DELETE FROM purchase_summary WHERE business_date = $1::date', [businessDate]);

  for (const row of rows.rows) {
    const requiredQty = Number(row.required_qty ?? 0);
    const finalPurchaseQty = Number((requiredQty * (1 + Number(wastagePct) / 100)).toFixed(3));
    await client.query(
      `INSERT INTO purchase_summary (
         business_date, product_id, required_qty, wastage_pct, final_purchase_qty, updated_by
       )
       VALUES ($1::date, $2, $3, $4, $5, $6)`,
      [businessDate, row.product_id, requiredQty, wastagePct, finalPurchaseQty, adminUserId],
    );
  }

  return rows.rows.length;
}

async function runCutoffWorkflow(adminUserId, businessDateInput) {
  const businessDate = normalizeBusinessDate(businessDateInput);
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `WITH ranked AS (
         SELECT o.id,
                ROW_NUMBER() OVER (
                  PARTITION BY o.route_id
                  ORDER BY COALESCE(o.building_id, 0), COALESCE(o.floor_number, 0), COALESCE(o.flat_number, ''), o.id
                )::int AS next_sequence
         FROM orders o
         WHERE DATE(o.created_at) = $1::date
           AND o.route_id IS NOT NULL
       )
       UPDATE orders o
       SET route_sequence = r.next_sequence,
           stop_number = r.next_sequence,
           updated_at = NOW(),
           updated_by = $2
       FROM ranked r
       WHERE o.id = r.id`,
      [businessDate, adminUserId],
    );

    const purchaseRows = await generatePurchaseSummaryForDate(client, businessDate, adminUserId);

    await client.query(
      `INSERT INTO reports (report_type, business_date, storage_url, generated_by, updated_by)
       VALUES ('PACKING_SHEET_DATA', $1::date, $2, $3, $3)
       ON CONFLICT (report_type, business_date)
       DO UPDATE SET storage_url = EXCLUDED.storage_url, generated_by = EXCLUDED.generated_by, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
      [businessDate, `inline:packing-sheet:${businessDate}`, adminUserId],
    );

    await client.query('COMMIT');
    return { businessDate, purchaseRows };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function maybeAutoRunCutoff(adminUserId) {
  const cutoffHour = await getNumericSetting('cutoff_hour', env.cutOffHour);
  const now = new Date();
  if (now.getHours() < cutoffHour) return null;
  const businessDate = now.toISOString().slice(0, 10);
  const existing = await pool.query(
    `SELECT 1
     FROM purchase_summary
     WHERE business_date = $1::date
     LIMIT 1`,
    [businessDate],
  );
  if (existing.rowCount) return null;
  return runCutoffWorkflow(adminUserId, businessDate);
}

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
  await maybeAutoRunCutoff(_req.user.sub);
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
  await maybeAutoRunCutoff(req.user.sub);
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
  await maybeAutoRunCutoff(_req.user.sub);
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

adminRouter.post('/modules/procurement/generate', requirePermission('purchase:write'), async (req, res) => {
  const parsed = procurementActionSchema.safeParse(req.body ?? {});
  if (!parsed.success) return fail(res, 400, 'Invalid procurement payload');

  const client = await pool.connect();
  try {
    const businessDate = normalizeBusinessDate(parsed.data.business_date);
    await client.query('BEGIN');
    const count = await generatePurchaseSummaryForDate(client, businessDate, req.user.sub);
    await client.query('COMMIT');
    return ok(res, { business_date: businessDate, rows_generated: count }, 'Purchase summary generated');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Failed to generate purchase summary: ${error.message}`);
  } finally {
    client.release();
  }
});

adminRouter.get('/modules/procurement/detail', requirePermission('purchase:read'), async (req, res) => {
  const businessDate = normalizeBusinessDate(req.query.business_date);
  const rows = await pool.query(
    `SELECT ps.id, ps.business_date, ps.product_id, p.name AS product_name,
            ps.required_qty, ps.wastage_pct, ps.final_purchase_qty,
            COALESCE(ps.supplier_name, '-') AS supplier_name,
            ps.purchase_cost, ps.purchase_date, ps.invoice_url, ps.purchased
     FROM purchase_summary ps
     JOIN products p ON p.id = ps.product_id
     WHERE ps.business_date = $1::date
     ORDER BY p.name ASC`,
    [businessDate],
  );
  return ok(res, { business_date: businessDate, rows: rows.rows });
});

adminRouter.post('/modules/procurement/mark-purchased/:id', requirePermission('purchase:write'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return fail(res, 400, 'Invalid purchase summary id');

  const payload = z.object({
    supplier_name: z.string().min(2).max(120).optional().nullable(),
    purchase_cost: z.coerce.number().nonnegative().optional().nullable(),
    invoice_url: z.string().max(400).optional().nullable(),
    purchase_date: z.string().optional().nullable(),
  }).safeParse(req.body ?? {});
  if (!payload.success) return fail(res, 400, 'Invalid purchase update payload');

  const data = payload.data;
  const updated = await pool.query(
    `UPDATE purchase_summary
     SET purchased = TRUE,
         supplier_name = COALESCE($2, supplier_name),
         purchase_cost = COALESCE($3, purchase_cost),
         invoice_url = COALESCE($4, invoice_url),
         purchase_date = COALESCE($5::date, purchase_date, CURRENT_DATE),
         updated_at = NOW(),
         updated_by = $6
     WHERE id = $1
     RETURNING *`,
    [
      id,
      data.supplier_name ?? null,
      data.purchase_cost ?? null,
      data.invoice_url ?? null,
      data.purchase_date ? normalizeBusinessDate(data.purchase_date) : null,
      req.user.sub,
    ],
  );
  if (!updated.rowCount) return fail(res, 404, 'Purchase summary row not found');
  return ok(res, updated.rows[0], 'Purchase row marked purchased');
});

adminRouter.get('/modules/procurement/export', requirePermission('purchase:read'), async (req, res) => {
  const businessDate = normalizeBusinessDate(req.query.business_date);
  const format = `${req.query.format ?? 'CSV'}`.toUpperCase();
  const rows = await pool.query(
    `SELECT p.name AS product_name, ps.required_qty, ps.wastage_pct, ps.final_purchase_qty,
            COALESCE(ps.supplier_name, '-') AS supplier_name, ps.purchased
     FROM purchase_summary ps
     JOIN products p ON p.id = ps.product_id
     WHERE ps.business_date = $1::date
     ORDER BY p.name ASC`,
    [businessDate],
  );
  const headers = ['Product', 'Required Qty', 'Wastage %', 'Final Purchase Qty', 'Supplier', 'Purchased'];
  const dataRows = rows.rows.map((row) => [
    row.product_name,
    row.required_qty,
    row.wastage_pct,
    row.final_purchase_qty,
    row.supplier_name,
    row.purchased ? 'Yes' : 'No',
  ]);

  const payload = format === 'PDF'
    ? pdfExportPayload({
        filename: `purchase-summary-${businessDate}.pdf`,
        title: `Purchase Summary ${businessDate}`,
        lines: [headers.join(' | '), ...dataRows.map((row) => row.join(' | '))],
      })
    : csvExportPayload({
        filename: `purchase-summary-${businessDate}.csv`,
        headers,
        rows: dataRows,
      });

  return ok(res, payload);
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

adminRouter.get('/modules/inventory/items', requirePermission('inventory:read'), async (req, res) => {
  const businessDate = normalizeBusinessDate(req.query.business_date);
  const rows = await pool.query(
    `SELECT i.*, p.name AS product_name
     FROM inventory i
     JOIN products p ON p.id = i.product_id
     WHERE i.stock_date = $1::date
     ORDER BY p.name ASC`,
    [businessDate],
  );
  return ok(res, { business_date: businessDate, rows: rows.rows });
});

adminRouter.get('/modules/inventory/receipts', requirePermission('inventory:read'), async (_req, res) => {
  const receipts = await pool.query(
    `SELECT gr.id, gr.supplier_name, gr.invoice_number, gr.total_cost, gr.status, gr.received_at,
            gri.id AS goods_received_item_id, p.name AS product_name, gri.quantity_received, gri.rate_per_kg, gri.quality_status
     FROM goods_received gr
     JOIN goods_received_items gri ON gri.goods_received_id = gr.id
     JOIN products p ON p.id = gri.product_id
     ORDER BY gr.received_at DESC, gr.id DESC
     LIMIT 30`,
  );
  const quality = await pool.query(
    `SELECT qc.id, qc.goods_received_item_id, p.name AS product_name, qc.good_quantity, qc.damaged_quantity, qc.waste_quantity,
            qc.damage_reason, qc.approved_at
     FROM quality_checks qc
     JOIN products p ON p.id = qc.product_id
     ORDER BY qc.approved_at DESC
     LIMIT 30`,
  );
  return ok(res, { receipts: receipts.rows, quality_checks: quality.rows });
});

adminRouter.post('/modules/inventory/goods-received', requirePermission('inventory:write'), async (req, res) => {
  const parsed = goodsReceiptSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid goods received payload');
  const p = parsed.data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const totalCost = Number((Number(p.quantity_received) * Number(p.rate_per_kg)).toFixed(2));
    const receipt = await client.query(
      `INSERT INTO goods_received (supplier_name, invoice_number, total_cost, status)
       VALUES ($1, $2, $3, 'AWAITING_QUALITY_CHECK')
       ON CONFLICT (invoice_number)
       DO UPDATE SET supplier_name = EXCLUDED.supplier_name, total_cost = goods_received.total_cost + EXCLUDED.total_cost, updated_at = NOW()
       RETURNING id`,
      [p.supplier_name, p.invoice_number, totalCost],
    );

    await client.query(
      `INSERT INTO goods_received_items (goods_received_id, product_id, quantity_received, rate_per_kg, total_cost)
       VALUES ($1, $2, $3, $4, $5)`,
      [receipt.rows[0].id, p.product_id, p.quantity_received, p.rate_per_kg, totalCost],
    );
    await client.query('COMMIT');
    return ok(res, true, 'Goods receipt saved');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Goods receipt failed: ${error.message}`);
  } finally {
    client.release();
  }
});

adminRouter.post('/modules/inventory/quality-approve', requirePermission('inventory:write'), async (req, res) => {
  const parsed = qualityApprovalSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid quality approval payload');
  const p = parsed.data;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const item = await client.query(
      `SELECT gri.id, gri.goods_received_id, gri.product_id, gri.quantity_received, gr.invoice_number
       FROM goods_received_items gri
       JOIN goods_received gr ON gr.id = gri.goods_received_id
       WHERE gri.id = $1`,
      [p.goods_received_item_id],
    );
    if (!item.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Goods received item not found');
    }

    await client.query(
      `INSERT INTO quality_checks (goods_received_item_id, product_id, good_quantity, damaged_quantity, waste_quantity, damage_reason)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [p.goods_received_item_id, item.rows[0].product_id, p.good_quantity, p.damaged_quantity, p.waste_quantity, p.damage_reason ?? null],
    );

    await client.query(
      `UPDATE goods_received_items
       SET quality_status = 'APPROVED',
           updated_at = NOW()
       WHERE id = $1`,
      [p.goods_received_item_id],
    );

    await client.query(
      `INSERT INTO inventory (product_id, warehouse_code, stock_date, purchased_qty, damaged_qty, wastage_qty, remaining_qty, quality_check_approved, updated_by)
       VALUES ($1, 'WH-01', CURRENT_DATE, $2, $3, $4, $2, TRUE, $5)
       ON CONFLICT (product_id, warehouse_code, stock_date)
       DO UPDATE SET
         purchased_qty = inventory.purchased_qty + EXCLUDED.purchased_qty,
         damaged_qty = inventory.damaged_qty + EXCLUDED.damaged_qty,
         wastage_qty = inventory.wastage_qty + EXCLUDED.wastage_qty,
         remaining_qty = GREATEST(0, inventory.remaining_qty + EXCLUDED.purchased_qty - EXCLUDED.damaged_qty - EXCLUDED.wastage_qty),
         quality_check_approved = TRUE,
         updated_at = NOW(),
         updated_by = EXCLUDED.updated_by`,
      [item.rows[0].product_id, p.good_quantity, p.damaged_quantity, p.waste_quantity, req.user.sub],
    );

    await client.query(
      `UPDATE goods_received
       SET status = 'APPROVED_FOR_PACKING',
           updated_at = NOW()
       WHERE id = $1`,
      [item.rows[0].goods_received_id],
    );
    await client.query('COMMIT');
    return ok(res, true, 'Quality approved and inventory updated');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Quality approval failed: ${error.message}`);
  } finally {
    client.release();
  }
});

adminRouter.post('/modules/inventory/adjust', requirePermission('inventory:write'), async (req, res) => {
  const parsed = inventoryAdjustSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid inventory adjustment payload');

  const p = parsed.data;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(
      `INSERT INTO inventory (product_id, warehouse_code, stock_date, low_stock_threshold, updated_by)
       VALUES ($1, $2, CURRENT_DATE, COALESCE($3, 0), $4)
       ON CONFLICT (product_id, warehouse_code, stock_date)
       DO NOTHING`,
      [p.product_id, p.warehouse_code, p.low_stock_threshold ?? 0, req.user.sub],
    );

    const columnByOperation = {
      OPENING: 'opening_stock',
      PURCHASE: 'purchased_qty',
      ALLOCATE: 'allocated_qty',
      DAMAGED: 'damaged_qty',
      WASTAGE: 'wastage_qty',
    };
    const column = columnByOperation[p.operation];
    await client.query(
      `UPDATE inventory
       SET ${column} = ${column} + $4,
           low_stock_threshold = COALESCE($5, low_stock_threshold),
           remaining_qty = GREATEST(
             0,
             opening_stock + purchased_qty + CASE WHEN $3 = 'OPENING' THEN $4 ELSE 0 END + CASE WHEN $3 = 'PURCHASE' THEN $4 ELSE 0 END
             - allocated_qty - CASE WHEN $3 = 'ALLOCATE' THEN $4 ELSE 0 END
             - damaged_qty - CASE WHEN $3 = 'DAMAGED' THEN $4 ELSE 0 END
             - wastage_qty - CASE WHEN $3 = 'WASTAGE' THEN $4 ELSE 0 END
           ),
           updated_at = NOW(),
           updated_by = $6
       WHERE product_id = $1
         AND warehouse_code = $2
         AND stock_date = CURRENT_DATE
       RETURNING *`,
      [p.product_id, p.warehouse_code, p.operation, Number(p.quantity), p.low_stock_threshold ?? null, req.user.sub],
    );

    const latest = await client.query(
      `SELECT i.*, p.name AS product_name
       FROM inventory i
       JOIN products p ON p.id = i.product_id
       WHERE i.product_id = $1
         AND i.warehouse_code = $2
         AND i.stock_date = CURRENT_DATE`,
      [p.product_id, p.warehouse_code],
    );

    await client.query('COMMIT');
    return ok(res, latest.rows[0], 'Inventory updated');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Inventory adjustment failed: ${error.message}`);
  } finally {
    client.release();
  }
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

adminRouter.get('/modules/packing/routes', requirePermission('packing:read'), async (req, res) => {
  const businessDate = normalizeBusinessDate(req.query.business_date);
  const routes = await pool.query(
    `SELECT r.id, r.route_code, s.name AS sector_name,
            COUNT(o.id)::int AS total_orders,
            COUNT(*) FILTER (WHERE COALESCE(o.packing_status::text, 'PLACED') = 'PACKED')::int AS packed_orders
     FROM routes r
     JOIN sectors s ON s.id = r.sector_id
     LEFT JOIN orders o
       ON o.route_id = r.id
      AND DATE(o.created_at) = $1::date
     WHERE r.active = TRUE
     GROUP BY r.id, r.route_code, s.name
     ORDER BY s.name ASC, r.route_code ASC`,
    [businessDate],
  );
  return ok(res, { business_date: businessDate, routes: routes.rows });
});

adminRouter.get('/modules/packing/route/:id', requirePermission('packing:read'), async (req, res) => {
  const routeId = Number(req.params.id);
  if (!Number.isFinite(routeId) || routeId <= 0) return fail(res, 400, 'Invalid route id');
  const businessDate = normalizeBusinessDate(req.query.business_date);

  const orders = await pool.query(
    `SELECT o.id, o.route_sequence, o.customer_ref, o.total, o.print_status, o.packing_status,
            u.name AS customer_name, b.name AS building_name, a.line1 AS flat,
            COALESCE(o.crate_number, '-') AS crate_number
     FROM orders o
     JOIN users u ON u.id = o.user_id
     JOIN addresses a ON a.id = o.address_id
     LEFT JOIN buildings b ON b.id = o.building_id
     WHERE o.route_id = $1
       AND DATE(o.created_at) = $2::date
     ORDER BY COALESCE(o.route_sequence, o.id) ASC, o.id ASC`,
    [routeId, businessDate],
  );

  const itemSummary = await pool.query(
    `SELECT p.name, COALESCE(SUM(oi.quantity),0)::numeric(12,3) AS total_qty
     FROM orders o
     JOIN order_items oi ON oi.order_id = o.id
     JOIN products p ON p.id = oi.product_id
     WHERE o.route_id = $1
       AND DATE(o.created_at) = $2::date
     GROUP BY p.name
     ORDER BY p.name ASC`,
    [routeId, businessDate],
  );

  const crates = await pool.query(
    `SELECT crate_code, stop_from, stop_to, max_capacity, current_orders
     FROM route_crates
     WHERE route_id = $1
     ORDER BY crate_code ASC`,
    [routeId],
  );

  return ok(res, {
    business_date: businessDate,
    orders: orders.rows,
    item_summary: itemSummary.rows,
    crates: crates.rows,
  });
});

adminRouter.get('/modules/packing/export', requirePermission('packing:read'), async (req, res) => {
  const routeId = Number(req.query.route_id);
  if (!Number.isFinite(routeId) || routeId <= 0) return fail(res, 400, 'Invalid route id');
  const businessDate = normalizeBusinessDate(req.query.business_date);
  const format = `${req.query.format ?? 'PDF'}`.toUpperCase();

  const routeMeta = await pool.query('SELECT route_code FROM routes WHERE id = $1', [routeId]);
  const routeCode = routeMeta.rows[0]?.route_code ?? `route-${routeId}`;
  const detail = await pool.query(
    `SELECT COALESCE(o.route_sequence, o.id)::int AS sequence,
            COALESCE(u.name, '-') AS customer_name,
            COALESCE(b.name, '-') AS building_name,
            COALESCE(a.line1, '-') AS flat,
            COALESCE(o.crate_number, '-') AS crate_number
     FROM orders o
     JOIN users u ON u.id = o.user_id
     JOIN addresses a ON a.id = o.address_id
     LEFT JOIN buildings b ON b.id = o.building_id
     WHERE o.route_id = $1
       AND DATE(o.created_at) = $2::date
     ORDER BY sequence ASC`,
    [routeId, businessDate],
  );

  const headers = ['Sequence', 'Customer', 'Building', 'Flat', 'Crate'];
  const rows = detail.rows.map((row) => [
    row.sequence,
    row.customer_name,
    row.building_name,
    row.flat,
    row.crate_number,
  ]);

  const payload = format === 'CSV'
    ? csvExportPayload({
        filename: `packing-sheet-${routeCode}-${businessDate}.csv`,
        headers,
        rows,
      })
    : pdfExportPayload({
        filename: `packing-sheet-${routeCode}-${businessDate}.pdf`,
        title: `Packing Sheet ${routeCode} ${businessDate}`,
        lines: [headers.join(' | '), ...rows.map((row) => row.join(' | '))],
      });

  return ok(res, payload);
});

adminRouter.post('/modules/packing/print-labels', requirePermission('packing:write'), async (req, res) => {
  const parsed = printRouteLabelsSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const updated = await pool.query(
    `UPDATE orders
     SET print_status = 'PRINTED',
         printed_at = NOW(),
         updated_at = NOW(),
         updated_by = $2
     WHERE route_id = $1
       AND DATE(created_at) = CURRENT_DATE
     RETURNING id`,
    [parsed.data.route_id, req.user.sub],
  );
  return ok(res, { printed_orders: updated.rowCount }, 'Route labels printed');
});

adminRouter.post('/modules/packing/bulk-scan', requirePermission('packing:write'), async (req, res) => {
  const parsed = packingScanSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');
  const orderId = barcodeToOrderId(parsed.data.barcode);
  if (!orderId) return fail(res, 400, 'Invalid barcode');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const order = await client.query(
      `SELECT id, route_id, crate_number
       FROM orders
       WHERE id = $1
         AND route_id = $2
         AND DATE(created_at) = CURRENT_DATE`,
      [orderId, parsed.data.route_id],
    );
    if (!order.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Order not found on this route');
    }

    await client.query(
      `UPDATE orders
       SET packing_status = 'PACKED',
           packed_at = NOW(),
           packed_by = $2,
           status = 'PACKED',
           updated_at = NOW(),
           updated_by = $2
       WHERE id = $1`,
      [orderId, req.user.sub],
    );
    await client.query(
      `INSERT INTO packing_log (order_id, route_id, crate_number, barcode_value, packed_by, processing_staff_id, status, updated_by)
       VALUES ($1, $2, $3, $4, $5, NULL, 'PACKED', $5)`,
      [orderId, parsed.data.route_id, order.rows[0].crate_number ?? null, parsed.data.barcode, req.user.sub],
    );
    await client.query('COMMIT');
    return ok(res, { order_id: orderId }, 'Packing scan recorded');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Bulk scan failed: ${error.message}`);
  } finally {
    client.release();
  }
});

adminRouter.get('/modules/delivery/summary', requirePermission('delivery:read'), async (_req, res) => {
  const overview = await pool.query(
    `SELECT COUNT(*)::int AS logs_today,
            COUNT(*) FILTER (WHERE status = 'DELIVERED')::int AS delivered,
            COUNT(*) FILTER (WHERE status = 'NOT_AVAILABLE')::int AS not_available,
            COUNT(*) FILTER (WHERE status = 'RESCHEDULED')::int AS rescheduled,
            COUNT(*) FILTER (WHERE status = 'CANCELLED')::int AS cancelled,
            COALESCE(
              SUM(o.total) FILTER (
                WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
                  AND COALESCE(o.payment_mode, 'CASH') IN ('CASH', 'COD')
              ),
              0
            )::numeric(12,2) AS cash_collected,
            COALESCE(
              SUM(o.total) FILTER (
                WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
                  AND COALESCE(o.payment_mode, 'UPI') = 'UPI'
              ),
              0
            )::numeric(12,2) AS upi_collected,
            COUNT(*) FILTER (
              WHERE a.status = 'SETTLEMENT_DONE'
            )::int AS settled_routes
     FROM delivery_log
     LEFT JOIN orders o ON o.id = delivery_log.order_id
     LEFT JOIN delivery_route_assignments a
       ON a.route_id = delivery_log.route_id
      AND a.business_date = delivery_log.business_date
     WHERE DATE(delivery_log.created_at) = CURRENT_DATE`,
  );

  const byRoute = await pool.query(
    `SELECT COALESCE(r.route_code, '-') AS route_code,
            COUNT(*)::int AS total,
            COUNT(*) FILTER (WHERE dl.status = 'DELIVERED')::int AS delivered,
            COALESCE(
              SUM(o.total) FILTER (
                WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
              ),
              0
            )::numeric(12,2) AS collected_amount,
            COALESCE(MAX(a.status::text), 'UNASSIGNED') AS assignment_status
     FROM delivery_log dl
     LEFT JOIN routes r ON r.id = dl.route_id
     LEFT JOIN orders o ON o.id = dl.order_id
     LEFT JOIN delivery_route_assignments a
       ON a.route_id = dl.route_id
      AND a.business_date = dl.business_date
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

adminRouter.get('/modules/customers', requirePermission('customers:read'), async (req, res) => {
  const queryText = `${req.query.q ?? ''}`.trim();
  const rows = await pool.query(
    `SELECT c.id, c.full_name, c.phone, c.credit_points, c.blocked,
            sec.name AS sector_name, b.name AS building_name,
            COUNT(o.id)::int AS total_orders,
            COALESCE(SUM(o.total),0)::numeric(12,2) AS revenue
     FROM customers c
     LEFT JOIN sectors sec ON sec.id = c.sector_id
     LEFT JOIN buildings b ON b.id = c.building_id
     LEFT JOIN orders o ON o.user_id = c.user_id
     WHERE ($1::text IS NULL OR LOWER(c.full_name) LIKE LOWER('%' || $1 || '%') OR c.phone LIKE '%' || $1 || '%')
     GROUP BY c.id, sec.name, b.name
     ORDER BY c.full_name ASC`,
    [queryText || null],
  );
  return ok(res, rows.rows);
});

adminRouter.post('/modules/customers/:id/block', requirePermission('customers:write'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return fail(res, 400, 'Invalid customer id');
  const parsed = customerBlockSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid customer block payload');

  const updated = await pool.query(
    `UPDATE customers
     SET blocked = $2,
         updated_at = NOW(),
         updated_by = $3
     WHERE id = $1
     RETURNING *`,
    [id, parsed.data.blocked, req.user.sub],
  );
  if (!updated.rowCount) return fail(res, 404, 'Customer not found');
  return ok(res, updated.rows[0], parsed.data.blocked ? 'Customer blocked' : 'Customer unblocked');
});

adminRouter.post('/modules/customers/:id/credit', requirePermission('customers:write'), async (req, res) => {
  const id = Number(req.params.id);
  if (!Number.isFinite(id) || id <= 0) return fail(res, 400, 'Invalid customer id');
  const parsed = customerCreditSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid customer credit payload');

  const updated = await pool.query(
    `UPDATE customers
     SET credit_points = credit_points + $2,
         updated_at = NOW(),
         updated_by = $3
     WHERE id = $1
     RETURNING *`,
    [id, parsed.data.points, req.user.sub],
  );
  if (!updated.rowCount) return fail(res, 404, 'Customer not found');
  return ok(res, updated.rows[0], 'Customer credit updated');
});

adminRouter.get('/modules/routes', requirePermission('routes:read'), async (_req, res) => {
  await maybeAutoRunCutoff(_req.user.sub);
  const sectors = await pool.query('SELECT id, code, name FROM sectors ORDER BY code ASC');
  const routes = await pool.query(
    `SELECT r.id, r.route_code, r.max_orders, r.sequence_logic, r.active,
            r.optimized, r.total_orders, r.total_distance_km, r.estimated_time_minutes, r.generated_at,
            s.code AS sector_code, s.name AS sector_name,
            COUNT(DISTINCT rb.building_id)::int AS buildings_mapped,
            COUNT(DISTINCT rc.id)::int AS crate_count
     FROM routes r
     JOIN sectors s ON s.id = r.sector_id
     LEFT JOIN route_buildings rb ON rb.route_id = r.id
     LEFT JOIN route_crates rc ON rc.route_id = r.id
     GROUP BY r.id, s.code, s.name
     ORDER BY r.route_code ASC`,
  );
  return ok(res, { sectors: sectors.rows, routes: routes.rows });
});

adminRouter.get('/modules/routes/buildings', requirePermission('routes:read'), async (req, res) => {
  const sectorId = Number(req.query.sector_id);
  const rows = await pool.query(
    `SELECT b.id, b.name, b.code, s.name AS sector_name, s.code AS sector_code,
            rb.route_id, r.route_code, rb.stop_sequence
     FROM buildings b
     JOIN sectors s ON s.id = b.sector_id
     LEFT JOIN route_buildings rb ON rb.building_id = b.id
     LEFT JOIN routes r ON r.id = rb.route_id
     WHERE ($1::int IS NULL OR b.sector_id = $1::int)
     ORDER BY s.code ASC, b.name ASC`,
    [Number.isFinite(sectorId) && sectorId > 0 ? sectorId : null],
  );
  return ok(res, rows.rows);
});

adminRouter.post('/modules/routes/map-building', requirePermission('routes:write'), async (req, res) => {
  const parsed = routeBuildingSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid route building payload');
  const p = parsed.data;
  await pool.query(
    `INSERT INTO route_buildings (route_id, building_id, stop_sequence, created_by)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (route_id, building_id)
     DO UPDATE SET stop_sequence = EXCLUDED.stop_sequence`,
    [p.route_id, p.building_id, p.stop_sequence, req.user.sub],
  );
  return ok(res, true, 'Building mapped to route');
});

adminRouter.post('/modules/routes/auto-assign-buildings', requirePermission('routes:write'), async (req, res) => {
  const sectorId = Number(req.body?.sector_id);
  if (!Number.isFinite(sectorId) || sectorId <= 0) return fail(res, 400, 'Invalid sector id');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const routes = await client.query(
      `SELECT r.id, COUNT(rb.building_id)::int AS mapped_count
       FROM routes r
       LEFT JOIN route_buildings rb ON rb.route_id = r.id
       WHERE r.sector_id = $1
       GROUP BY r.id
       ORDER BY mapped_count ASC, r.id ASC`,
      [sectorId],
    );
    if (!routes.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'No routes found for this sector');
    }
    const buildings = await client.query(
      `SELECT b.id
       FROM buildings b
       LEFT JOIN route_buildings rb ON rb.building_id = b.id
       WHERE b.sector_id = $1
         AND rb.building_id IS NULL
       ORDER BY b.id ASC`,
      [sectorId],
    );
    let pointer = 0;
    for (const building of buildings.rows) {
      const route = routes.rows[pointer % routes.rows.length];
      await client.query(
        `INSERT INTO route_buildings (route_id, building_id, stop_sequence, created_by)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT DO NOTHING`,
        [route.id, building.id, route.mapped_count + 1, req.user.sub],
      );
      route.mapped_count += 1;
      pointer += 1;
    }
    await client.query('COMMIT');
    return ok(res, { mapped_buildings: buildings.rowCount }, 'Buildings auto-assigned');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Auto-assign failed: ${error.message}`);
  } finally {
    client.release();
  }
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

adminRouter.post('/modules/reports/generate', requirePermission('reports:read'), async (req, res) => {
  const parsed = reportGenerateSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid report payload');
  const businessDate = normalizeBusinessDate(parsed.data.business_date);
  const type = parsed.data.report_type.toUpperCase();
  let headers = [];
  let rows = [];

  if (type === 'DAILY_SALES_REPORT') {
    const result = await pool.query(
      `SELECT o.id, COALESCE(u.name, '-') AS customer_name, o.total, o.status
       FROM orders o
       LEFT JOIN users u ON u.id = o.user_id
       WHERE DATE(o.created_at) = $1::date
       ORDER BY o.id ASC`,
      [businessDate],
    );
    headers = ['Order ID', 'Customer', 'Total', 'Status'];
    rows = result.rows.map((row) => [row.id, row.customer_name, row.total, row.status]);
  } else if (type === 'PRODUCT_DEMAND_REPORT') {
    const result = await pool.query(
      `SELECT p.name, COALESCE(SUM(oi.quantity),0)::numeric(12,3) AS demand_qty
       FROM orders o
       JOIN order_items oi ON oi.order_id = o.id
       JOIN products p ON p.id = oi.product_id
       WHERE DATE(o.created_at) = $1::date
       GROUP BY p.name
       ORDER BY demand_qty DESC, p.name ASC`,
      [businessDate],
    );
    headers = ['Product', 'Demand Qty'];
    rows = result.rows.map((row) => [row.name, row.demand_qty]);
  } else if (type === 'DELIVERY_TIME_REPORT') {
    const result = await pool.query(
      `SELECT COALESCE(r.route_code, '-') AS route_code,
              COUNT(*) FILTER (WHERE COALESCE(o.delivery_status::text, 'PLACED') = 'DELIVERED')::int AS delivered_orders
       FROM routes r
       LEFT JOIN orders o
         ON o.route_id = r.id
        AND DATE(o.created_at) = $1::date
       GROUP BY r.route_code
       ORDER BY r.route_code ASC`,
      [businessDate],
    );
    headers = ['Route', 'Delivered Orders'];
    rows = result.rows.map((row) => [row.route_code, row.delivered_orders]);
  } else {
    return fail(res, 400, 'Unsupported report type');
  }

  const exportPayload = parsed.data.format === 'PDF'
    ? pdfExportPayload({
        filename: `${type.toLowerCase()}-${businessDate}.pdf`,
        title: `${type.replaceAll('_', ' ')} ${businessDate}`,
        lines: [headers.join(' | '), ...rows.map((row) => row.join(' | '))],
      })
    : csvExportPayload({
        filename: `${type.toLowerCase()}-${businessDate}.csv`,
        headers,
        rows,
      });

  await pool.query(
    `INSERT INTO reports (report_type, business_date, storage_url, generated_by, updated_by)
     VALUES ($1, $2::date, $3, $4, $4)
     ON CONFLICT (report_type, business_date)
     DO UPDATE SET storage_url = EXCLUDED.storage_url, generated_by = EXCLUDED.generated_by, updated_by = EXCLUDED.updated_by, updated_at = NOW()`,
    [type, businessDate, `inline:${type}:${businessDate}:${parsed.data.format}`, req.user.sub],
  );

  return ok(res, exportPayload, 'Report generated');
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

adminRouter.post('/jobs/run-cutoff', requirePermission('orders:freeze'), async (req, res) => {
  try {
    const businessDate = normalizeBusinessDate(req.body?.business_date);
    const result = await runCutoffWorkflow(req.user.sub, businessDate);
    return ok(
      res,
      {
        business_date: result.businessDate,
        purchase_rows: result.purchaseRows,
      },
      'Cutoff workflow completed',
    );
  } catch (error) {
    return fail(res, 500, `Cutoff workflow failed: ${error.message}`);
  }
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
    `SELECT id, name, phone, employee_code, role_code, device_id, active, last_login_at, created_at, updated_at
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
            a.cash_handover_confirmed_at, a.cash_handover_amount, a.cash_handover_notes,
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
        a.cash_handover_confirmed_at,
        a.cash_handover_amount,
        d.name AS delivery_executive_name,
        d.phone AS delivery_executive_phone,
        COUNT(o.id)::int AS total_orders,
        COUNT(*) FILTER (WHERE COALESCE(o.packing_status::text, 'PLACED') = 'PACKED')::int AS packed_orders,
        COUNT(*) FILTER (WHERE COALESCE(o.delivery_status::text, 'PENDING') = 'OUT_FOR_DELIVERY')::int AS out_for_delivery,
        COUNT(*) FILTER (WHERE COALESCE(o.delivery_status::text, 'PENDING') = 'DELIVERED')::int AS delivered_orders,
        COALESCE(
          SUM(o.total) FILTER (
            WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
          ),
          0
        )::numeric(12,2) AS collected_amount,
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
     GROUP BY
       a.id,
       r.id,
       r.route_code,
       s.id,
       s.code,
       s.name,
       a.status,
       a.route_start_time,
       a.route_end_time,
       a.cash_handover_confirmed_at,
       a.cash_handover_amount,
       d.name,
       d.phone
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

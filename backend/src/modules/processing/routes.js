import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { env } from '../../config/env.js';
import { signToken } from '../../utils/jwt.js';
import { normalizeIndianPhone, sendOtpSms } from '../../utils/sms.js';
import { ok, fail } from '../../utils/response.js';
import { authMiddleware } from '../../middleware/auth.js';

export const processingRouter = express.Router();

const loginSchema = z.object({
  phone: z.string().min(10).max(20),
  device_id: z.string().min(4).max(160),
});

const verifySchema = z.object({
  phone: z.string().min(10).max(20),
  otp: z.string().length(6),
  device_id: z.string().min(4).max(160),
});

const lockSchema = z.object({
  order_id: z.coerce.number().int().positive(),
});

const unlockSchema = z.object({
  order_id: z.coerce.number().int().positive(),
});

const scanPackSchema = z.object({
  order_id: z.coerce.number().int().positive(),
  barcode: z.string().min(1),
  crate_number: z.string().max(40).optional(),
});

const printSchema = z.object({
  route_id: z.coerce.number().int().positive(),
});

function normalizeFlatToken(raw) {
  const text = `${raw ?? ''}`.trim().toUpperCase();
  if (!text) return '';
  const number = text.match(/\d+/)?.[0] ?? '';
  if (number) {
    const n = Number(number);
    if (Number.isFinite(n)) return `${n}`.padStart(3, '0');
  }
  return text;
}

function inferFloorAndFlat(line1) {
  const text = `${line1 ?? ''}`;
  const floorMatch = text.match(/(?:floor|flr|fl)\s*[-:]?\s*(\d+)/i);
  const flatMatch = text.match(/(?:flat|apt|apartment|unit)\s*[-:]?\s*([a-z0-9-]+)/i);
  const fallbackNumber = text.match(/\b(\d{1,4})\b/)?.[1] ?? '';
  const floor = floorMatch ? Number(floorMatch[1]) : Math.floor((Number(fallbackNumber) || 0) / 100);
  const flat = flatMatch?.[1] ?? fallbackNumber;
  return {
    floorNumber: Number.isFinite(floor) ? floor : 0,
    flatNumber: normalizeFlatToken(flat),
  };
}

function expectedBarcodeForOrder(order) {
  const ref = `${order?.customer_ref ?? ''}`.trim();
  if (ref) return ref.toUpperCase();
  return `ORD-${order.id}`;
}

async function ensureRouteForToday(routeId) {
  const row = await pool.query(
    `SELECT id
     FROM routes
     WHERE id = $1
       AND active = TRUE`,
    [routeId],
  );
  return row.rowCount > 0;
}

processingRouter.post('/login', async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const normalizedPhone = normalizeIndianPhone(parsed.data.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const customer = await pool.query('SELECT id FROM users WHERE phone = $1', [normalizedPhone]);
  if (customer.rowCount) {
    return fail(res, 403, 'This number is registered as customer. Use store app.');
  }
  const delivery = await pool.query('SELECT id FROM delivery_executives WHERE phone = $1', [normalizedPhone]);
  if (delivery.rowCount) {
    return fail(res, 403, 'This number is registered as delivery executive. Use delivery app.');
  }

  const staff = await pool.query('SELECT id, active FROM processing_staff WHERE phone = $1', [normalizedPhone]);
  if (!staff.rowCount) return fail(res, 403, 'No processing staff account found. Contact admin.');
  if (!staff.rows[0].active) return fail(res, 403, 'Processing staff account is inactive.');

  const otp = env.otpBypass ? env.otpBypassCode : `${Math.floor(100000 + Math.random() * 900000)}`;
  await pool.query(
    `INSERT INTO otp_codes (phone, code, expires_at)
     VALUES ($1, $2, NOW() + INTERVAL '10 minutes')
     ON CONFLICT (phone)
     DO UPDATE SET code = $2, expires_at = NOW() + INTERVAL '10 minutes', updated_at = NOW()`,
    [normalizedPhone, otp],
  );

  if (!env.otpBypass) {
    try {
      await sendOtpSms(normalizedPhone, otp);
    } catch (error) {
      if (!env.otpFallbackOnSmsFailure) return fail(res, 502, `OTP send failed: ${error.message}`);
      return ok(res, { phone: normalizedPhone, otp, bypass_mode: true }, 'OTP fallback mode');
    }
  }

  return ok(
    res,
    { phone: normalizedPhone, otp: env.otpBypass ? otp : null },
    env.otpBypass ? 'OTP generated (bypass mode)' : 'OTP sent',
  );
});

processingRouter.post('/verify-otp', async (req, res) => {
  const parsed = verifySchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const normalizedPhone = normalizeIndianPhone(parsed.data.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const otpRow = await pool.query(
    'SELECT 1 FROM otp_codes WHERE phone = $1 AND code = $2 AND expires_at > NOW()',
    [normalizedPhone, parsed.data.otp],
  );
  if (!otpRow.rowCount) return fail(res, 401, 'Invalid OTP');

  const staffRow = await pool.query(
    `SELECT id, name, phone, employee_code, active, device_id
     FROM processing_staff
     WHERE phone = $1`,
    [normalizedPhone],
  );
  if (!staffRow.rowCount) return fail(res, 403, 'No processing staff account found. Contact admin.');
  if (!staffRow.rows[0].active) return fail(res, 403, 'Processing staff account is inactive.');

  const staff = staffRow.rows[0];
  if (staff.device_id && staff.device_id !== parsed.data.device_id) {
    return fail(res, 403, 'This account is active on another device. Contact admin to rebind.');
  }

  await pool.query(
    `UPDATE processing_staff
     SET device_id = COALESCE(device_id, $2),
         last_login_at = NOW(),
         updated_at = NOW()
     WHERE id = $1`,
    [staff.id, parsed.data.device_id],
  );

  const token = signToken({
    sub: staff.id,
    role: 'processing',
    phone: staff.phone,
    name: staff.name,
  });

  return ok(
    res,
    {
      token,
      user: {
        id: staff.id,
        name: staff.name,
        phone: staff.phone,
        employee_code: staff.employee_code,
      },
    },
    'Processing staff authenticated',
  );
});

processingRouter.use(authMiddleware);
processingRouter.use((req, res, next) => {
  if (req.user?.role !== 'processing') return fail(res, 403, 'Processing access required');
  return next();
});

processingRouter.post('/generate-routes', async (_req, res) => {
  const todayOrders = await pool.query(
    `SELECT o.id, o.route_id, a.line1
     FROM orders o
     JOIN addresses a ON a.id = o.address_id
     WHERE o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
       AND o.route_id IS NOT NULL
     ORDER BY o.route_id ASC, o.id ASC`,
  );

  const grouped = new Map();
  for (const row of todayOrders.rows) {
    const list = grouped.get(row.route_id) ?? [];
    list.push(row);
    grouped.set(row.route_id, list);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const [routeId, orders] of grouped.entries()) {
      const activeRoute = await ensureRouteForToday(routeId);
      if (!activeRoute) continue;

      const sorted = [...orders]
        .map((o) => ({ ...o, ...inferFloorAndFlat(o.line1) }))
        .sort((a, b) => {
          if (a.floorNumber !== b.floorNumber) return a.floorNumber - b.floorNumber;
          return `${a.flatNumber}`.localeCompare(`${b.flatNumber}`, undefined, { numeric: true });
        });

      for (let i = 0; i < sorted.length; i++) {
        const item = sorted[i];
        await client.query(
          `UPDATE orders
           SET floor_number = $2,
               flat_number = $3,
               stop_number = $4,
               route_sequence = $4,
               updated_at = NOW()
           WHERE id = $1`,
          [item.id, item.floorNumber, item.flatNumber || null, i + 1],
        );
      }
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Route generation failed: ${error.message}`);
  } finally {
    client.release();
  }

  return ok(res, { routes: grouped.size, orders: todayOrders.rowCount }, 'Routes generated');
});

processingRouter.get('/routes-today', async (_req, res) => {
  const rows = await pool.query(
    `SELECT o.route_id,
            r.route_code,
            s.code AS sector_code,
            s.name AS sector_name,
            COUNT(*)::int AS total_orders,
            COUNT(*) FILTER (WHERE COALESCE(o.packing_status::text, 'PLACED') = 'PACKED')::int AS packed_orders,
            COUNT(*) FILTER (WHERE COALESCE(o.packing_status::text, 'PLACED') <> 'PACKED')::int AS pending_orders,
            COUNT(*) FILTER (WHERE COALESCE(o.print_status::text, 'PLACED') = 'PRINTED')::int AS printed_orders
     FROM orders o
     JOIN routes r ON r.id = o.route_id
     JOIN sectors s ON s.id = o.sector_id
     WHERE o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
       AND o.route_id IS NOT NULL
     GROUP BY o.route_id, r.route_code, s.code, s.name
     ORDER BY s.code ASC, r.route_code ASC`,
  );

  return ok(res, rows.rows);
});

processingRouter.get('/route-orders/:routeId', async (req, res) => {
  const routeId = Number(req.params.routeId);
  if (!Number.isFinite(routeId) || routeId <= 0) return fail(res, 400, 'Invalid route_id');

  const routeActive = await ensureRouteForToday(routeId);
  if (!routeActive) return fail(res, 404, 'Route not found');

  const rows = await pool.query(
    `SELECT o.id AS order_id,
            o.stop_number,
            o.floor_number,
            o.flat_number,
            COALESCE(b.name, 'Building') AS building_name,
            COALESCE(u.name, 'Customer') AS customer_name,
            u.phone,
            o.total AS order_value,
            COALESCE(o.packing_status::text, 'PLACED') AS packing_status,
            COALESCE(o.print_status::text, 'PLACED') AS print_status,
            o.route_id,
            o.customer_ref,
            COALESCE(pl.crate_number, CONCAT('CRATE-', CEIL(COALESCE(o.stop_number, 1)::numeric / 15.0)::text)) AS crate_suggestion,
            CONCAT_WS(', ', a.line1, a.city, a.state, a.pincode) AS address,
            COALESCE(
              JSON_AGG(
                JSON_BUILD_OBJECT('name', p.name, 'quantity', oi.quantity, 'unit_price', oi.unit_price)
              ) FILTER (WHERE oi.id IS NOT NULL),
              '[]'::json
            ) AS items
     FROM orders o
     JOIN users u ON u.id = o.user_id
     JOIN addresses a ON a.id = o.address_id
     LEFT JOIN buildings b ON b.id = o.building_id
     LEFT JOIN order_items oi ON oi.order_id = o.id
     LEFT JOIN products p ON p.id = oi.product_id
     LEFT JOIN LATERAL (
       SELECT crate_number
       FROM packing_log
       WHERE order_id = o.id
       ORDER BY packed_at DESC
       LIMIT 1
     ) pl ON true
     WHERE o.route_id = $1
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
     GROUP BY o.id, b.name, u.name, u.phone, a.line1, a.city, a.state, a.pincode, pl.crate_number
     ORDER BY COALESCE(o.stop_number, 9999) ASC, COALESCE(o.floor_number, 9999) ASC, COALESCE(o.flat_number, 'ZZZ') ASC, o.id ASC`,
    [routeId],
  );

  return ok(res, rows.rows);
});

processingRouter.post('/lock-order', async (req, res) => {
  const parsed = lockSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');
  const orderId = parsed.data.order_id;

  const order = await pool.query(
    `SELECT id
     FROM orders
     WHERE id = $1
       AND created_at >= CURRENT_DATE
       AND created_at < (CURRENT_DATE + INTERVAL '1 day')`,
    [orderId],
  );
  if (!order.rowCount) return fail(res, 404, 'Order not found for today');

  await pool.query(
    `DELETE FROM processing_order_locks
     WHERE order_id = $1
       AND locked_until < NOW()`,
    [orderId],
  );

  const existing = await pool.query(
    `SELECT l.order_id, l.processing_staff_id, l.locked_until, p.name
     FROM processing_order_locks l
     JOIN processing_staff p ON p.id = l.processing_staff_id
     WHERE l.order_id = $1
       AND l.locked_until >= NOW()
     LIMIT 1`,
    [orderId],
  );

  if (existing.rowCount && existing.rows[0].processing_staff_id !== req.user.sub) {
    return fail(
      res,
      409,
      `Order is being packed by ${existing.rows[0].name}. Try again in a moment.`,
    );
  }

  await pool.query(
    `INSERT INTO processing_order_locks (order_id, processing_staff_id, locked_until, updated_at)
     VALUES ($1, $2, NOW() + INTERVAL '2 minutes', NOW())
     ON CONFLICT (order_id)
     DO UPDATE
       SET processing_staff_id = EXCLUDED.processing_staff_id,
           locked_until = EXCLUDED.locked_until,
           updated_at = NOW()`,
    [orderId, req.user.sub],
  );

  return ok(res, { order_id: orderId, locked_until: new Date(Date.now() + 2 * 60 * 1000) }, 'Order locked');
});

processingRouter.post('/unlock-order', async (req, res) => {
  const parsed = unlockSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  await pool.query(
    `DELETE FROM processing_order_locks
     WHERE order_id = $1
       AND processing_staff_id = $2`,
    [parsed.data.order_id, req.user.sub],
  );

  return ok(res, true, 'Order unlocked');
});

processingRouter.post('/scan-pack', async (req, res) => {
  const parsed = scanPackSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const lock = await pool.query(
    `SELECT 1
     FROM processing_order_locks
     WHERE order_id = $1
       AND processing_staff_id = $2
       AND locked_until >= NOW()`,
    [parsed.data.order_id, req.user.sub],
  );
  if (!lock.rowCount) return fail(res, 409, 'Lock this order first before packing.');

  const owned = await pool.query(
    `SELECT o.id, o.route_id, o.customer_ref, o.packing_status
     FROM orders o
     WHERE o.id = $1
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
     LIMIT 1`,
    [parsed.data.order_id],
  );
  if (!owned.rowCount) return fail(res, 404, 'Order not found for today');

  const order = owned.rows[0];
  const status = `${order.packing_status ?? ''}`.toUpperCase();
  if (status === 'PACKED') return ok(res, true, 'Order already packed');

  const expected = expectedBarcodeForOrder({ id: order.id, customer_ref: order.customer_ref });
  const provided = `${parsed.data.barcode}`.trim().toUpperCase();
  if (provided !== expected) {
    return fail(res, 409, `Invalid barcode for this order. Expected code: ${expected}`);
  }

  await pool.query(
    `UPDATE orders
     SET packing_status = 'PACKED',
         packed_at = NOW(),
         packed_by = $2,
         crate_number = COALESCE($3, crate_number),
         updated_at = NOW()
     WHERE id = $1`,
    [order.id, req.user.sub, parsed.data.crate_number ?? null],
  );

  await pool.query(
    `INSERT INTO packing_log (order_id, route_id, crate_number, barcode_value, packed_at, status, processing_staff_id, updated_at)
     VALUES ($1, $2, $3, $4, NOW(), 'PACKED', $5, NOW())`,
    [order.id, order.route_id, parsed.data.crate_number ?? null, provided, req.user.sub],
  );

  await pool.query(
    `DELETE FROM processing_order_locks
     WHERE order_id = $1`,
    [order.id],
  );

  return ok(res, true, 'Order packed');
});

processingRouter.post('/print-route-labels', async (req, res) => {
  const parsed = printSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const updated = await pool.query(
    `UPDATE orders
     SET print_status = 'PRINTED',
         printed_at = NOW(),
         updated_at = NOW()
     WHERE route_id = $1
       AND created_at >= CURRENT_DATE
       AND created_at < (CURRENT_DATE + INTERVAL '1 day')
     RETURNING id`,
    [parsed.data.route_id],
  );

  return ok(
    res,
    { route_id: parsed.data.route_id, labels_printed: updated.rowCount },
    'Route labels marked as printed',
  );
});

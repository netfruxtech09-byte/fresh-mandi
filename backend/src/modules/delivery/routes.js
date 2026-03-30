import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { env } from '../../config/env.js';
import { signToken } from '../../utils/jwt.js';
import { normalizeIndianPhone, sendOtpSms } from '../../utils/sms.js';
import { ok, fail } from '../../utils/response.js';
import { authMiddleware } from '../../middleware/auth.js';
import { getNumericSetting } from '../../utils/settings.js';

export const deliveryRouter = express.Router();

const loginSchema = z.object({
  phone: z.string().min(10).max(20),
  device_id: z.string().min(4).max(160),
});

const verifySchema = z.object({
  phone: z.string().min(10).max(20),
  otp: z.string().length(6),
  device_id: z.string().min(4).max(160),
});

const routeActionSchema = z.object({
  route_id: z.coerce.number().int().positive(),
});

const deliveredSchema = z.object({
  order_id: z.coerce.number().int().positive(),
  route_id: z.coerce.number().int().positive(),
});

const failedSchema = z.object({
  order_id: z.coerce.number().int().positive(),
  failure_reason: z.string().min(3).max(120),
});

const collectPaymentSchema = z.object({
  order_id: z.coerce.number().int().positive(),
  payment_mode: z.enum(['CASH', 'UPI', 'ONLINE', 'COD']),
  collected_amount: z.coerce.number().nonnegative(),
});

const cashHandoverSchema = z.object({
  route_id: z.coerce.number().int().positive(),
  notes: z.string().max(200).optional().nullable(),
});

function barcodeToOrderId(raw) {
  const text = `${raw ?? ''}`.trim();
  if (!text) return null;
  const direct = Number(text);
  if (Number.isFinite(direct) && direct > 0) return direct;
  const m = text.match(/(\d+)/);
  if (!m) return null;
  const id = Number(m[1]);
  return Number.isFinite(id) && id > 0 ? id : null;
}

function expectedBarcodeForOrder(order) {
  const ref = `${order?.customer_ref ?? ''}`.trim();
  if (ref) return ref.toUpperCase();
  return `ORD-${order.id}`;
}

async function getTodayAssignment(executiveId) {
  const assignment = await pool.query(
    `SELECT a.*, r.route_code, s.code AS sector_code, s.name AS sector_name
     FROM delivery_route_assignments a
     JOIN routes r ON r.id = a.route_id
     JOIN sectors s ON s.id = r.sector_id
     WHERE a.delivery_executive_id = $1
       AND a.business_date = CURRENT_DATE
     LIMIT 1`,
    [executiveId],
  );
  return assignment.rows[0] ?? null;
}

async function getDeliveryWindowHours() {
  const [startHour, endHour] = await Promise.all([
    getNumericSetting('delivery_window_start_hour', env.deliveryWindowStartHour),
    getNumericSetting('delivery_window_end_hour', env.deliveryWindowEndHour),
  ]);
  return { startHour, endHour };
}

function formatHourLabel(hour) {
  const normalized = Math.max(0, Math.min(23, Number(hour) || 0));
  const suffix = normalized >= 12 ? 'PM' : 'AM';
  const twelveHour = normalized % 12 === 0 ? 12 : normalized % 12;
  return `${twelveHour}:00 ${suffix}`;
}

async function ensureWithinDeliveryWindow() {
  const { startHour, endHour } = await getDeliveryWindowHours();
  const now = new Date();
  const currentHour = now.getHours();
  if (currentHour < startHour || currentHour >= endHour) {
    return {
      ok: false,
      code: 409,
      message: `Delivery actions are allowed only between ${formatHourLabel(startHour)} and ${formatHourLabel(endHour)}.`,
      startHour,
      endHour,
    };
  }
  return { ok: true, startHour, endHour };
}

async function upsertTodayDeliveryLog({
  orderId,
  routeId,
  staffId,
  status = null,
  notes = null,
  paymentMode = null,
  paymentStatus = null,
}) {
  await pool.query(
    `INSERT INTO delivery_log (
       order_id,
       business_date,
       route_id,
       delivery_staff_id,
       status,
       notes,
       payment_mode,
       payment_status,
       updated_at
     )
     VALUES ($1, CURRENT_DATE, $2, $3, COALESCE($4, 'NOT_AVAILABLE'), $5, $6, COALESCE($7, 'PENDING'), NOW())
     ON CONFLICT (order_id, business_date)
     DO UPDATE
       SET status = COALESCE(EXCLUDED.status, delivery_log.status),
           notes = COALESCE(EXCLUDED.notes, delivery_log.notes),
           payment_mode = COALESCE(EXCLUDED.payment_mode, delivery_log.payment_mode),
           payment_status = COALESCE(EXCLUDED.payment_status, delivery_log.payment_status),
           delivery_staff_id = EXCLUDED.delivery_staff_id,
           route_id = EXCLUDED.route_id,
           updated_at = NOW()`,
    [orderId, routeId, staffId, status, notes, paymentMode, paymentStatus],
  );
}

async function ensureAssignmentForRoute({
  executiveId,
  routeId,
  requireInProgress = false,
  allowCompleted = false,
}) {
  const assignment = await pool.query(
    `SELECT id, status
     FROM delivery_route_assignments
     WHERE delivery_executive_id = $1
       AND route_id = $2
       AND business_date = CURRENT_DATE
     LIMIT 1`,
    [executiveId, routeId],
  );

  if (!assignment.rowCount) {
    return { ok: false, code: 403, message: 'Route does not belong to this delivery executive' };
  }

  const status = assignment.rows[0].status;
  if (!allowCompleted && (status === 'COMPLETED' || status === 'SETTLEMENT_DONE')) {
    return { ok: false, code: 409, message: 'Route already completed for today' };
  }

  if (requireInProgress && status !== 'IN_PROGRESS') {
    return { ok: false, code: 409, message: 'Start route first to perform this action' };
  }

  return { ok: true, assignment: assignment.rows[0] };
}

deliveryRouter.post('/login', async (req, res) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const normalizedPhone = normalizeIndianPhone(parsed.data.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const customer = await pool.query('SELECT id FROM users WHERE phone = $1', [normalizedPhone]);
  if (customer.rowCount) {
    return fail(
      res,
      403,
      'This number is registered as a customer account. Please use customer app login for this number.',
    );
  }

  const executive = await pool.query(
    'SELECT id, active FROM delivery_executives WHERE phone = $1',
    [normalizedPhone],
  );
  if (!executive.rowCount) {
    return fail(res, 403, 'No delivery executive account found for this number. Contact admin.');
  }
  if (!executive.rows[0].active) {
    return fail(res, 403, 'Delivery executive account is inactive. Contact admin.');
  }

  const otp = env.otpBypass ? env.otpBypassCode : `${Math.floor(100000 + Math.random() * 900000)}`;

  await pool.query(
    `INSERT INTO otp_codes (phone, code, expires_at)
     VALUES ($1, $2, NOW() + INTERVAL '10 minutes')
     ON CONFLICT (phone) DO UPDATE
     SET code = $2, expires_at = NOW() + INTERVAL '10 minutes', updated_at = NOW()`,
    [normalizedPhone, otp],
  );

  if (!env.otpBypass) {
    try {
      await sendOtpSms(normalizedPhone, otp);
    } catch (error) {
      if (!env.otpFallbackOnSmsFailure) {
        return fail(res, 502, `OTP send failed: ${error.message}`);
      }
      return ok(
        res,
        { phone: normalizedPhone, otp, bypass_mode: true },
        `OTP fallback mode: SMS failed (${error.message})`,
      );
    }
  }

  return ok(
    res,
    { phone: normalizedPhone, otp: env.otpBypass ? otp : null },
    env.otpBypass ? 'OTP generated (bypass mode)' : 'OTP sent',
  );
});

deliveryRouter.post('/verify-otp', async (req, res) => {
  const parsed = verifySchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const normalizedPhone = normalizeIndianPhone(parsed.data.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const customer = await pool.query('SELECT id FROM users WHERE phone = $1', [normalizedPhone]);
  if (customer.rowCount) {
    return fail(
      res,
      403,
      'This number is registered as a customer account. Please use customer app login for this number.',
    );
  }

  const otpRow = await pool.query(
    'SELECT 1 FROM otp_codes WHERE phone = $1 AND code = $2 AND expires_at > NOW()',
    [normalizedPhone, parsed.data.otp],
  );
  if (!otpRow.rowCount) return fail(res, 401, 'Invalid OTP');

  const executiveRow = await pool.query(
    `SELECT id, name, phone, employee_code, active, device_id
     FROM delivery_executives
     WHERE phone = $1`,
    [normalizedPhone],
  );
  if (!executiveRow.rowCount) {
    return fail(res, 403, 'No delivery executive account found for this number. Contact admin.');
  }
  if (!executiveRow.rows[0].active) {
    return fail(res, 403, 'Delivery executive account is inactive. Contact admin.');
  }

  const executive = executiveRow.rows[0];
  const incomingDeviceId = parsed.data.device_id;

  if (executive.device_id && executive.device_id !== incomingDeviceId) {
    return fail(
      res,
      403,
      'This delivery account is already active on another device. Please contact admin to rebind.',
    );
  }

  await pool.query(
    `UPDATE delivery_executives
     SET device_id = COALESCE(device_id, $2),
         last_login_at = NOW(),
         updated_at = NOW()
     WHERE id = $1`,
    [executive.id, incomingDeviceId],
  );

  const token = signToken({
    sub: executive.id,
    role: 'delivery',
    phone: executive.phone,
    name: executive.name,
  });

  return ok(
    res,
    {
      token,
      user: {
        id: executive.id,
        name: executive.name,
        phone: executive.phone,
        employee_code: executive.employee_code,
      },
    },
    'Delivery executive authenticated',
  );
});

deliveryRouter.use(authMiddleware);

deliveryRouter.use((req, res, next) => {
  if (req.user?.role !== 'delivery') {
    return fail(res, 403, 'Delivery access required');
  }
  return next();
});

deliveryRouter.post('/logout', async (req, res) => {
  await pool.query(
    `UPDATE delivery_executives
     SET device_id = NULL,
         updated_at = NOW()
     WHERE id = $1`,
    [req.user.sub],
  );

  return ok(res, null, 'Delivery executive logged out');
});

deliveryRouter.get('/assigned-route', async (req, res) => {
  const assignment = await getTodayAssignment(req.user.sub);
  const window = await getDeliveryWindowHours();
  if (!assignment) return ok(res, null, 'No route assigned today');

  const counts = await pool.query(
    `SELECT
        COUNT(*)::int AS total_orders,
        COUNT(*) FILTER (WHERE COALESCE(o.delivery_status::text, 'PENDING') = 'DELIVERED')::int AS delivered_count,
        COUNT(*) FILTER (
          WHERE COALESCE(o.delivery_status::text, 'PENDING') <> 'DELIVERED'
            AND o.failure_reason IS NULL
        )::int AS pending_count,
        COALESCE(SUM(o.total),0)::numeric(12,2) AS total_order_amount,
        COALESCE(
          SUM(o.total) FILTER (
            WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
          ),
          0
        )::numeric(12,2) AS total_collection_amount
     FROM orders o
     WHERE o.route_id = $1
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')`,
    [assignment.route_id],
  );

  const c = counts.rows[0] ?? {};
  return ok(res, {
    route_id: assignment.route_id,
    route_code: assignment.route_code,
    sector: assignment.sector_name ?? assignment.sector_code,
    total_orders: c.total_orders ?? 0,
    delivered_count: c.delivered_count ?? 0,
    pending_count: c.pending_count ?? 0,
    total_order_amount: Number(c.total_order_amount ?? 0),
    total_collection_amount: Number(c.total_collection_amount ?? 0),
    route_status: assignment.status,
    route_start_time: assignment.route_start_time,
    route_end_time: assignment.route_end_time,
    cash_handover_confirmed_at: assignment.cash_handover_confirmed_at ?? null,
    cash_handover_amount: Number(assignment.cash_handover_amount ?? 0),
    delivery_window_start_hour: window.startHour,
    delivery_window_end_hour: window.endHour,
  });
});

deliveryRouter.post('/start-route', async (req, res) => {
  const parsed = routeActionSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const windowGuard = await ensureWithinDeliveryWindow();
  if (!windowGuard.ok) return fail(res, windowGuard.code, windowGuard.message);

  const assignment = await pool.query(
    `UPDATE delivery_route_assignments
     SET status = 'IN_PROGRESS',
         route_start_time = COALESCE(route_start_time, NOW()),
         updated_at = NOW()
     WHERE delivery_executive_id = $1
       AND route_id = $2
       AND business_date = CURRENT_DATE
     RETURNING *`,
    [req.user.sub, parsed.data.route_id],
  );

  if (!assignment.rowCount) return fail(res, 404, 'No assigned route found for today');
  return ok(res, assignment.rows[0], 'Route started');
});

deliveryRouter.get('/route-orders', async (req, res) => {
  const routeId = Number(req.query.route_id);
  if (!Number.isFinite(routeId) || routeId <= 0) {
    return fail(res, 400, 'Invalid route_id');
  }

  const guard = await ensureAssignmentForRoute({
    executiveId: req.user.sub,
    routeId,
    allowCompleted: true,
  });
  if (!guard.ok) return fail(res, guard.code, guard.message);

  const rows = await pool.query(
    `SELECT o.id AS order_id,
            COALESCE(o.route_sequence, ROW_NUMBER() OVER (ORDER BY o.id))::int AS stop_number,
            COALESCE(u.name, 'Customer') AS customer_name,
            u.phone,
            COALESCE(b.name, 'Building') AS building,
            COALESCE(a.line1, '-') AS flat,
            o.total AS order_value,
            COALESCE(o.payment_mode, 'CASH') AS payment_type,
            COALESCE(o.payment_status::text, 'PENDING') AS payment_status,
            CASE
              WHEN COALESCE(o.delivery_status::text, 'PENDING') = 'DELIVERED' THEN 'DELIVERED'
              WHEN o.failure_reason = 'Payment Issue' THEN 'RESCHEDULED'
              WHEN o.failure_reason IS NOT NULL THEN 'NOT_AVAILABLE'
              ELSE COALESCE(o.delivery_status::text, 'PENDING')
            END AS delivery_status,
            o.delivery_scan_verified,
            CONCAT_WS(', ', a.line1, a.city, a.state, a.pincode) AS address,
            UPPER(COALESCE(NULLIF(TRIM(o.customer_ref), ''), CONCAT('ORD-', o.id::text))) AS expected_barcode,
            o.route_id,
            COALESCE(
              JSON_AGG(
                JSON_BUILD_OBJECT(
                  'name', p.name,
                  'quantity', oi.quantity,
                  'unit_price', oi.unit_price
                )
              ) FILTER (WHERE oi.id IS NOT NULL),
              '[]'::json
            ) AS items
     FROM orders o
     JOIN users u ON u.id = o.user_id
     JOIN addresses a ON a.id = o.address_id
     LEFT JOIN buildings b ON b.id = o.building_id
     LEFT JOIN order_items oi ON oi.order_id = o.id
     LEFT JOIN products p ON p.id = oi.product_id
     WHERE o.route_id = $1
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
     GROUP BY o.id, u.name, u.phone, b.name, a.line1, a.city, a.state, a.pincode
     ORDER BY stop_number ASC, o.id ASC`,
    [routeId],
  );

  return ok(res, rows.rows);
});

deliveryRouter.post('/scan-order', async (req, res) => {
  const payloadSchema = z.object({
    route_id: z.coerce.number().int().positive(),
    barcode: z.string().min(1),
  });
  const parsed = payloadSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const windowGuard = await ensureWithinDeliveryWindow();
  if (!windowGuard.ok) return fail(res, windowGuard.code, windowGuard.message);

  const orderId = barcodeToOrderId(parsed.data.barcode);
  if (!orderId) return fail(res, 400, 'Invalid barcode');

  const guard = await ensureAssignmentForRoute({
    executiveId: req.user.sub,
    routeId: parsed.data.route_id,
    requireInProgress: true,
  });
  if (!guard.ok) return fail(res, guard.code, guard.message);

  const valid = await pool.query(
    `SELECT o.id, o.customer_ref, o.delivery_status, o.delivery_scan_verified
     FROM orders o
     JOIN delivery_route_assignments a
       ON a.route_id = o.route_id
      AND a.business_date = CURRENT_DATE
     WHERE o.id = $1
       AND o.route_id = $2
       AND a.delivery_executive_id = $3
       AND DATE(o.created_at) = CURRENT_DATE`,
    [orderId, parsed.data.route_id, req.user.sub],
  );

  if (!valid.rowCount) {
    return fail(res, 403, 'This order does not belong to your route.');
  }

  const order = valid.rows[0];
  const currentDeliveryStatus = `${order.delivery_status ?? ''}`.toUpperCase();
  if (currentDeliveryStatus === 'DELIVERED') {
    return fail(res, 409, 'Order already delivered. Additional scan is not allowed.');
  }
  if (order.delivery_scan_verified === true) {
    return fail(res, 409, 'Barcode already verified for this order.');
  }

  const expected = expectedBarcodeForOrder({ id: orderId, customer_ref: order.customer_ref });
  const provided = `${parsed.data.barcode}`.trim().toUpperCase();
  if (provided !== expected) {
    return fail(res, 409, `Invalid barcode for this order. Expected code: ${expected}`);
  }

  await pool.query(
    `UPDATE orders
     SET delivery_scan_verified = true,
         delivery_scan_verified_at = NOW(),
         delivery_scan_verified_by = $2,
         delivery_scan_code = $3,
         updated_at = NOW()
     WHERE id = $1`,
    [orderId, req.user.sub, provided],
  );

  return ok(res, { order_id: orderId, expected_barcode: expected }, 'Scan validated');
});

deliveryRouter.post('/mark-delivered', async (req, res) => {
  const parsed = deliveredSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const windowGuard = await ensureWithinDeliveryWindow();
  if (!windowGuard.ok) return fail(res, windowGuard.code, windowGuard.message);

  const owned = await pool.query(
    `SELECT o.id, o.payment_mode, o.payment_status, o.delivery_scan_verified, o.delivery_status, a.status AS assignment_status
     FROM orders o
     JOIN delivery_route_assignments a
       ON a.route_id = o.route_id
      AND a.business_date = CURRENT_DATE
     WHERE o.id = $1
       AND o.route_id = $2
       AND a.delivery_executive_id = $3
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
     LIMIT 1`,
    [parsed.data.order_id, parsed.data.route_id, req.user.sub],
  );
  if (!owned.rowCount) return fail(res, 403, 'Order does not belong to this delivery executive');

  const order = owned.rows[0];
  const assignmentStatus = `${order.assignment_status ?? ''}`.toUpperCase();
  if (assignmentStatus === 'COMPLETED' || assignmentStatus === 'SETTLEMENT_DONE') {
    return fail(res, 409, 'Route already completed for today');
  }
  if (assignmentStatus !== 'IN_PROGRESS') {
    return fail(res, 409, 'Start route first to perform this action');
  }

  if (`${order.delivery_status ?? ''}`.toUpperCase() === 'DELIVERED') {
    return ok(res, true, 'Order already delivered');
  }
  const paymentMode = `${order.payment_mode ?? ''}`.toUpperCase();
  const paymentStatus = `${order.payment_status ?? ''}`.toUpperCase();
  const scanVerified = order.delivery_scan_verified === true;
  if (!scanVerified) {
    return fail(res, 409, 'Scan verification required before marking delivered.');
  }
  if (paymentMode !== 'ONLINE' && paymentStatus !== 'PAID') {
    return fail(res, 409, 'Payment pending. Collect payment before marking delivered.');
  }

  await pool.query(
    `UPDATE orders
     SET status = 'DELIVERED',
         delivery_status = 'DELIVERED',
         delivered_at = NOW(),
         delivered_by = $2,
         updated_at = NOW()
     WHERE id = $1`,
    [parsed.data.order_id, req.user.sub],
  );

  await upsertTodayDeliveryLog({
    orderId: parsed.data.order_id,
    routeId: parsed.data.route_id,
    staffId: req.user.sub,
    status: 'DELIVERED',
    paymentStatus: paymentStatus === 'PAID' ? 'PAID' : 'PENDING',
  });

  return ok(res, true, 'Order delivered');
});

deliveryRouter.post('/mark-failed', async (req, res) => {
  const parsed = failedSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const windowGuard = await ensureWithinDeliveryWindow();
  if (!windowGuard.ok) return fail(res, windowGuard.code, windowGuard.message);

  const owned = await pool.query(
    `SELECT o.id, o.route_id
     FROM orders o
     JOIN delivery_route_assignments a
       ON a.route_id = o.route_id
      AND a.business_date = CURRENT_DATE
     WHERE o.id = $1
       AND a.delivery_executive_id = $2`,
    [parsed.data.order_id, req.user.sub],
  );
  if (!owned.rowCount) return fail(res, 403, 'Order does not belong to this delivery executive');

  const guard = await ensureAssignmentForRoute({
    executiveId: req.user.sub,
    routeId: owned.rows[0].route_id,
    requireInProgress: true,
  });
  if (!guard.ok) return fail(res, guard.code, guard.message);

  const reason = parsed.data.failure_reason;
  const status = reason === 'Payment Issue' ? 'RESCHEDULED' : 'NOT_AVAILABLE';

  await pool.query(
    `UPDATE orders
     SET failure_reason = $2,
         updated_at = NOW()
     WHERE id = $1`,
    [parsed.data.order_id, reason],
  );

  await upsertTodayDeliveryLog({
    orderId: parsed.data.order_id,
    routeId: owned.rows[0].route_id,
    staffId: req.user.sub,
    status,
    notes: reason,
    paymentStatus: 'PENDING',
  });

  return ok(res, true, 'Order marked failed');
});

deliveryRouter.post('/collect-payment', async (req, res) => {
  const parsed = collectPaymentSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const windowGuard = await ensureWithinDeliveryWindow();
  if (!windowGuard.ok) return fail(res, windowGuard.code, windowGuard.message);

  const owned = await pool.query(
    `SELECT o.id, o.route_id, o.total, o.payment_mode, o.payment_status, o.delivery_status, a.status AS assignment_status
     FROM orders o
     JOIN delivery_route_assignments a
       ON a.route_id = o.route_id
      AND a.business_date = CURRENT_DATE
     WHERE o.id = $1
       AND a.delivery_executive_id = $2
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
     LIMIT 1`,
    [parsed.data.order_id, req.user.sub],
  );
  if (!owned.rowCount) return fail(res, 403, 'Order does not belong to this delivery executive');

  const order = owned.rows[0];
  const assignmentStatus = `${order.assignment_status ?? ''}`.toUpperCase();
  if (assignmentStatus === 'COMPLETED' || assignmentStatus === 'SETTLEMENT_DONE') {
    return fail(res, 409, 'Route already completed for today');
  }
  if (assignmentStatus !== 'IN_PROGRESS') {
    return fail(res, 409, 'Start route first to perform this action');
  }

  const orderPaymentMode = `${order.payment_mode ?? ''}`.toUpperCase();
  if (orderPaymentMode === 'ONLINE') {
    return fail(res, 409, 'Online payment orders are verified by backend. Manual collection is not allowed.');
  }
  if (`${order.payment_status ?? ''}`.toUpperCase() === 'PAID') {
    return fail(res, 409, 'Payment already collected for this order.');
  }

  const effectiveMode = parsed.data.payment_mode === 'COD' ? 'CASH' : parsed.data.payment_mode;
  const expectedAmount = Number(order.total ?? 0);
  const collected = Number(parsed.data.collected_amount ?? 0);
  if ((effectiveMode === 'CASH' || effectiveMode === 'UPI') && collected <= 0) {
    return fail(res, 400, 'Collected amount must be greater than zero.');
  }
  if ((effectiveMode === 'CASH' || effectiveMode === 'UPI') && collected > expectedAmount * 1.2) {
    return fail(res, 400, 'Collected amount is too high for this order total.');
  }

  await pool.query(
    `UPDATE orders
     SET payment_status = 'PAID',
         payment_mode = COALESCE($2, payment_mode),
         payment_collected_at = NOW(),
         updated_at = NOW()
     WHERE id = $1`,
    [parsed.data.order_id, effectiveMode],
  );

  await upsertTodayDeliveryLog({
    orderId: parsed.data.order_id,
    routeId: order.route_id,
    staffId: req.user.sub,
    status: `${order.delivery_status ?? ''}`.toUpperCase() === 'DELIVERED' ? 'DELIVERED' : null,
    paymentMode: effectiveMode,
    paymentStatus: 'PAID',
  });

  return ok(res, true, 'Payment collected');
});

deliveryRouter.post('/complete-route', async (req, res) => {
  const parsed = routeActionSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const guard = await ensureAssignmentForRoute({
    executiveId: req.user.sub,
    routeId: parsed.data.route_id,
    requireInProgress: true,
  });
  if (!guard.ok) return fail(res, guard.code, guard.message);

  const pending = await pool.query(
    `SELECT COUNT(*)::int AS count
     FROM orders o
     WHERE o.route_id = $1
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
       AND COALESCE(o.delivery_status::text, 'PENDING') NOT IN ('DELIVERED','CANCELLED')
       AND o.failure_reason IS NULL`,
    [parsed.data.route_id],
  );
  if (Number(pending.rows[0]?.count ?? 0) > 0) {
    return fail(res, 409, 'Cannot complete route while pending orders are remaining.');
  }

  const row = await pool.query(
    `UPDATE delivery_route_assignments
     SET status = 'COMPLETED',
         route_end_time = NOW(),
         updated_at = NOW()
     WHERE delivery_executive_id = $1
       AND route_id = $2
       AND business_date = CURRENT_DATE
     RETURNING *`,
    [req.user.sub, parsed.data.route_id],
  );

  if (!row.rowCount) return fail(res, 404, 'No assigned route found for today');
  return ok(res, row.rows[0], 'Route completed');
});

deliveryRouter.post('/cash-handover', async (req, res) => {
  const parsed = cashHandoverSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const guard = await ensureAssignmentForRoute({
    executiveId: req.user.sub,
    routeId: parsed.data.route_id,
    allowCompleted: true,
  });
  if (!guard.ok) return fail(res, guard.code, guard.message);

  const assignmentStatus = `${guard.assignment.status ?? ''}`.toUpperCase();
  if (assignmentStatus !== 'COMPLETED' && assignmentStatus !== 'SETTLEMENT_DONE') {
    return fail(res, 409, 'Complete route before confirming cash handover.');
  }
  if (assignmentStatus === 'SETTLEMENT_DONE') {
    return ok(res, guard.assignment, 'Cash handover already confirmed');
  }

  const totals = await pool.query(
    `SELECT
        COALESCE(
          SUM(o.total) FILTER (
            WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
              AND COALESCE(o.payment_mode, 'CASH') IN ('CASH','COD')
          ),
          0
        )::numeric(12,2) AS total_cash
     FROM orders o
     WHERE o.route_id = $1
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')`,
    [parsed.data.route_id],
  );

  const updated = await pool.query(
    `UPDATE delivery_route_assignments
     SET status = 'SETTLEMENT_DONE',
         cash_handover_confirmed_at = NOW(),
         cash_handover_amount = $2,
         cash_handover_notes = COALESCE($3, cash_handover_notes),
         updated_at = NOW()
     WHERE id = $1
     RETURNING *`,
    [
      guard.assignment.id,
      Number(totals.rows[0]?.total_cash ?? 0),
      parsed.data.notes?.trim() || null,
    ],
  );

  return ok(res, updated.rows[0], 'Cash handover confirmed');
});

deliveryRouter.get('/daily-summary', async (req, res) => {
  const window = await getDeliveryWindowHours();
  const summary = await pool.query(
    `SELECT
        COALESCE(
          SUM(o.total) FILTER (
            WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
              AND COALESCE(o.payment_mode, 'CASH') IN ('CASH','COD')
          ),
          0
        )::numeric(12,2) AS total_cash,
        COALESCE(
          SUM(o.total) FILTER (
            WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
              AND COALESCE(o.payment_mode, 'UPI') = 'UPI'
          ),
          0
        )::numeric(12,2) AS total_upi,
        COALESCE(
          SUM(o.total) FILTER (
            WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PAID'
              AND COALESCE(o.payment_mode, 'ONLINE') = 'ONLINE'
          ),
          0
        )::numeric(12,2) AS total_online,
        COUNT(*) FILTER (WHERE COALESCE(o.payment_status::text, 'PENDING') = 'PENDING')::int AS pending_payments,
        COUNT(*) FILTER (WHERE COALESCE(o.delivery_status::text, 'PENDING') = 'DELIVERED')::int AS total_delivered,
        COUNT(*) FILTER (WHERE o.failure_reason IS NOT NULL OR COALESCE(o.delivery_status::text, 'PENDING') = 'CANCELLED')::int AS total_failed
     FROM delivery_route_assignments a
     JOIN orders o
       ON o.route_id = a.route_id
      AND o.created_at >= CURRENT_DATE
      AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
     WHERE a.delivery_executive_id = $1
       AND a.business_date = CURRENT_DATE`,
    [req.user.sub],
  );

  const assignment = await getTodayAssignment(req.user.sub);
  return ok(res, {
    ...(summary.rows[0] ?? {}),
    route_id: assignment?.route_id ?? null,
    route_code: assignment?.route_code ?? null,
    route_status: assignment?.status ?? 'UNASSIGNED',
    route_start_time: assignment?.route_start_time ?? null,
    route_end_time: assignment?.route_end_time ?? null,
    cash_handover_confirmed_at: assignment?.cash_handover_confirmed_at ?? null,
    cash_handover_amount: Number(assignment?.cash_handover_amount ?? 0),
    delivery_window_start_hour: window.startHour,
    delivery_window_end_hour: window.endHour,
  });
});

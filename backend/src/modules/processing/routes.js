import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { env } from '../../config/env.js';
import { signToken } from '../../utils/jwt.js';
import { normalizeIndianPhone, sendOtpSms } from '../../utils/sms.js';
import { ok, fail } from '../../utils/response.js';
import { authMiddleware } from '../../middleware/auth.js';
import {
  deriveCratesForStops,
  estimateRouteMetrics,
  expectedBarcodeForOrder,
  inferFloorAndFlat,
  optimizeIndependentStops,
  routeTypeForOrders,
} from './helpers.js';

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
  action_type: z.enum(['PRINT', 'REPRINT']).optional(),
  reason: z.string().max(250).optional(),
});

const goodsReceivedSchema = z.object({
  supplier_name: z.string().min(2).max(160),
  invoice_number: z.string().min(1).max(80),
  image_url: z.string().url().optional().nullable(),
  items: z
    .array(
      z.object({
        product_id: z.coerce.number().int().positive(),
        quantity_received: z.coerce.number().positive(),
        rate_per_kg: z.coerce.number().nonnegative(),
      }),
    )
    .min(1),
});

const qualityCheckSchema = z.object({
  goods_received_item_id: z.coerce.number().int().positive(),
  product_id: z.coerce.number().int().positive(),
  good_quantity: z.coerce.number().nonnegative(),
  damaged_quantity: z.coerce.number().nonnegative(),
  waste_quantity: z.coerce.number().nonnegative(),
  damage_reason: z.string().max(250).optional().nullable(),
});

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

async function logStaffActivity(client, payload) {
  await client.query(
    `INSERT INTO staff_activity (processing_staff_id, activity_type, order_id, route_id, details)
     VALUES ($1, $2, $3, $4, $5::jsonb)`,
    [
      payload.processing_staff_id ?? null,
      payload.activity_type,
      payload.order_id ?? null,
      payload.route_id ?? null,
      JSON.stringify(payload.details ?? {}),
    ],
  );
}

async function buildRouteOrderRows(client) {
  const rows = await client.query(
    `SELECT o.id,
            o.route_id,
            o.building_id,
            o.sector_id,
            o.latitude,
            o.longitude,
            o.customer_ref,
            a.line1,
            a.city,
            a.state,
            a.pincode,
            COALESCE(b.name, 'Independent House') AS building_name
     FROM orders o
     JOIN addresses a ON a.id = o.address_id
     LEFT JOIN buildings b ON b.id = o.building_id
     WHERE o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
       AND o.route_id IS NOT NULL
     ORDER BY o.route_id ASC, o.id ASC`,
  );
  return rows.rows;
}

async function rebuildInventoryAllocations(client, generatedRoutes) {
  await client.query('DELETE FROM order_allocations WHERE business_date = CURRENT_DATE');
  await client.query('DELETE FROM inventory_alerts WHERE business_date = CURRENT_DATE');
  await client.query(
    `UPDATE inventory
     SET allocated_qty = 0,
         updated_at = NOW()
     WHERE stock_date = CURRENT_DATE`,
  );

  const inventoryRows = await client.query(
    `SELECT id, product_id, remaining_qty, allocated_qty, quality_check_approved
     FROM inventory
     WHERE stock_date = CURRENT_DATE
     ORDER BY id ASC`,
  );
  const inventoryByProduct = new Map();
  for (const row of inventoryRows.rows) {
    inventoryByProduct.set(row.product_id, {
      inventory_id: row.id,
      remaining_qty: Number(row.remaining_qty ?? 0),
      allocated_qty: Number(row.allocated_qty ?? 0),
      quality_check_approved: row.quality_check_approved,
    });
  }

  const items = await client.query(
    `SELECT oi.order_id,
            oi.product_id,
            oi.quantity::numeric(12,3) AS quantity,
            o.route_id,
            p.name AS product_name
     FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     JOIN products p ON p.id = oi.product_id
     WHERE o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
       AND o.route_id IS NOT NULL
     ORDER BY o.route_id ASC, oi.order_id ASC, oi.id ASC`,
  );

  for (const row of items.rows) {
    const inventory = inventoryByProduct.get(row.product_id) ?? {
      inventory_id: null,
      remaining_qty: 0,
      allocated_qty: 0,
      quality_check_approved: false,
    };
    const available = inventory.quality_check_approved
      ? Math.max(0, inventory.remaining_qty - inventory.allocated_qty)
      : 0;
    const requiredQty = Number(row.quantity ?? 0);
    const reservedQty = Math.min(requiredQty, available);
    const shortageQty = Math.max(0, requiredQty - reservedQty);
    const status =
      shortageQty > 0
        ? 'SHORT'
        : reservedQty > 0
          ? 'RESERVED'
          : 'PENDING_STOCK';

    await client.query(
      `INSERT INTO order_allocations
         (business_date, order_id, route_id, product_id, required_qty, reserved_qty, used_qty, shortage_qty, status, created_at, updated_at)
       VALUES
         (CURRENT_DATE, $1, $2, $3, $4, $5, 0, $6, $7, NOW(), NOW())`,
      [row.order_id, row.route_id, row.product_id, requiredQty, reservedQty, shortageQty, status],
    );

    if (inventory.inventory_id && reservedQty > 0) {
      inventory.allocated_qty += reservedQty;
      await client.query(
        `UPDATE inventory
         SET allocated_qty = $2,
             updated_at = NOW()
         WHERE id = $1`,
        [inventory.inventory_id, inventory.allocated_qty],
      );
    }

    if (shortageQty > 0) {
      await client.query(
        `INSERT INTO inventory_alerts (business_date, product_id, route_id, alert_type, severity, message)
         VALUES (CURRENT_DATE, $1, $2, 'INSUFFICIENT_STOCK', 'HIGH', $3)`,
        [
          row.product_id,
          row.route_id,
          `${row.product_name}: shortage of ${shortageQty} for order #${row.order_id} on route ${row.route_id}.`,
        ],
      );
    }
  }

  for (const route of generatedRoutes) {
    await logStaffActivity(client, {
      activity_type: 'ROUTE_GENERATED',
      route_id: route.route_id,
      details: route,
    });
  }
}

async function generateTodayRoutes() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const todayOrders = await buildRouteOrderRows(client);
    const grouped = new Map();
    for (const row of todayOrders) {
      const list = grouped.get(row.route_id) ?? [];
      list.push(row);
      grouped.set(row.route_id, list);
    }

    const generatedRoutes = [];
    await client.query('DELETE FROM route_crates');

    for (const [routeId, orders] of grouped.entries()) {
      const activeRoute = await ensureRouteForToday(routeId);
      if (!activeRoute) continue;

      const routeType = routeTypeForOrders(orders);
      let ordered = [];
      let optimized = false;
      let totalDistanceKm = 0;
      let estimatedTimeMinutes = 0;

      if (routeType === 'INDEPENDENT') {
        const optimizedRoute = await optimizeIndependentStops(orders);
        ordered = optimizedRoute.ordered;
        optimized = optimizedRoute.optimized;
        totalDistanceKm = optimizedRoute.totalDistanceKm;
        estimatedTimeMinutes = optimizedRoute.estimatedTimeMinutes;
      } else {
        const buildingMap = new Map();
        for (const order of orders) {
          const list = buildingMap.get(order.building_id ?? `house-${order.id}`) ?? [];
          list.push({ ...order, ...inferFloorAndFlat(order.line1) });
          buildingMap.set(order.building_id ?? `house-${order.id}`, list);
        }

        const buildingSequence = await client.query(
          `SELECT building_id, stop_sequence
           FROM route_buildings
           WHERE route_id = $1`,
          [routeId],
        );
        const routeBuildingOrder = new Map(
          buildingSequence.rows.map((row) => [row.building_id, Number(row.stop_sequence ?? 9999)]),
        );

        ordered = [...buildingMap.entries()]
          .sort((a, b) => {
            const orderA = routeBuildingOrder.get(Number(a[0])) ?? 9999;
            const orderB = routeBuildingOrder.get(Number(b[0])) ?? 9999;
            if (orderA !== orderB) return orderA - orderB;
            return `${a[1][0]?.building_name ?? ''}`.localeCompare(`${b[1][0]?.building_name ?? ''}`);
          })
          .flatMap(([, list]) =>
            list.sort((a, b) => {
              if (a.floorNumber !== b.floorNumber) return a.floorNumber - b.floorNumber;
              return `${a.flatNumber}`.localeCompare(`${b.flatNumber}`, undefined, { numeric: true });
            }),
          );

        const metrics = estimateRouteMetrics(
          ordered.filter((item) => item.latitude != null && item.longitude != null),
        );
        totalDistanceKm = metrics.totalDistanceKm;
        estimatedTimeMinutes = metrics.estimatedTimeMinutes;
      }

      const crates = deriveCratesForStops(ordered.length);

      for (let i = 0; i < ordered.length; i++) {
        const item = ordered[i];
        const crate = crates.find((candidate) => i + 1 >= candidate.stop_from && i + 1 <= candidate.stop_to);
        const floorFlat = inferFloorAndFlat(item.line1);

        await client.query(
          `UPDATE orders
           SET floor_number = $2,
               flat_number = $3,
               stop_number = $4,
               route_sequence = $4,
               crate_number = $5,
               updated_at = NOW()
           WHERE id = $1`,
          [item.id, floorFlat.floorNumber, floorFlat.flatNumber || null, i + 1, crate?.crate_code ?? null],
        );
      }

      for (const crate of crates) {
        await client.query(
          `INSERT INTO route_crates
             (route_id, crate_code, stop_from, stop_to, max_capacity, current_orders, created_at, updated_at)
           VALUES
             ($1, $2, $3, $4, $5, $6, NOW(), NOW())`,
          [
            routeId,
            crate.crate_code,
            crate.stop_from,
            crate.stop_to,
            crate.max_capacity,
            crate.current_orders,
          ],
        );
      }

      await client.query(
        `UPDATE routes
         SET optimized = $2,
             total_orders = $3,
             total_distance_km = $4,
             estimated_time_minutes = $5,
             generated_at = NOW(),
             updated_at = NOW()
         WHERE id = $1`,
        [routeId, optimized, ordered.length, totalDistanceKm, estimatedTimeMinutes],
      );

      generatedRoutes.push({
        route_id: routeId,
        route_type: routeType,
        total_orders: ordered.length,
        total_distance_km: totalDistanceKm,
        estimated_time_minutes: estimatedTimeMinutes,
        crates: crates.length,
        optimized,
      });
    }

    await rebuildInventoryAllocations(client, generatedRoutes);
    await client.query('COMMIT');

    const alertCount = await pool.query(
      `SELECT COUNT(*)::int AS count
       FROM inventory_alerts
       WHERE business_date = CURRENT_DATE`,
    );

    return {
      routes: generatedRoutes.length,
      orders: todayOrders.length,
      alerts: Number(alertCount.rows[0]?.count ?? 0),
      generated_routes: generatedRoutes,
    };
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

async function getDashboardPayload() {
  const [routeStats, orderStats, inventoryStats, alertStats, staffStats] = await Promise.all([
    pool.query(
      `SELECT COUNT(*)::int AS total_routes,
              COUNT(*) FILTER (WHERE pending_orders = 0)::int AS routes_packed,
              COUNT(*) FILTER (WHERE pending_orders > 0)::int AS routes_pending
       FROM (
         SELECT o.route_id,
                COUNT(*) FILTER (WHERE COALESCE(o.packing_status::text, 'PLACED') <> 'PACKED')::int AS pending_orders
         FROM orders o
         WHERE o.created_at >= CURRENT_DATE
           AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
           AND o.route_id IS NOT NULL
         GROUP BY o.route_id
       ) grouped`,
    ),
    pool.query(
      `SELECT COUNT(*)::int AS total_orders,
              COUNT(*) FILTER (WHERE COALESCE(packing_status::text, 'PLACED') = 'PACKED')::int AS orders_packed,
              COUNT(*) FILTER (WHERE COALESCE(packing_status::text, 'PLACED') <> 'PACKED')::int AS orders_remaining,
              COUNT(*) FILTER (WHERE COALESCE(print_status::text, 'PLACED') = 'PRINTED')::int AS printed_orders
       FROM orders
       WHERE created_at >= CURRENT_DATE
         AND created_at < (CURRENT_DATE + INTERVAL '1 day')`,
    ),
    pool.query(
      `SELECT COALESCE(SUM(remaining_qty),0)::numeric(12,3) AS inventory_remaining,
              COALESCE(SUM(allocated_qty),0)::numeric(12,3) AS inventory_reserved,
              COUNT(*) FILTER (WHERE remaining_qty <= low_stock_threshold)::int AS low_stock_items
       FROM inventory
       WHERE stock_date = CURRENT_DATE`,
    ),
    pool.query(
      `SELECT COUNT(*)::int AS active_alerts
       FROM inventory_alerts
       WHERE business_date = CURRENT_DATE
         AND acknowledged = FALSE`,
    ),
    pool.query(
      `SELECT COUNT(DISTINCT processing_staff_id)::int AS active_staff,
              COALESCE(
                ROUND(
                  (
                    COUNT(*) FILTER (WHERE activity_type = 'ORDER_PACKED')::numeric
                    / NULLIF(EXTRACT(EPOCH FROM (MAX(created_at) - MIN(created_at))) / 3600, 0)
                  )::numeric,
                  2
                ),
                0
              ) AS packing_speed
       FROM staff_activity
       WHERE DATE(created_at) = CURRENT_DATE`,
    ),
  ]);

  return {
    total_routes: Number(routeStats.rows[0]?.total_routes ?? 0),
    routes_packed: Number(routeStats.rows[0]?.routes_packed ?? 0),
    routes_pending: Number(routeStats.rows[0]?.routes_pending ?? 0),
    total_orders: Number(orderStats.rows[0]?.total_orders ?? 0),
    orders_packed: Number(orderStats.rows[0]?.orders_packed ?? 0),
    orders_remaining: Number(orderStats.rows[0]?.orders_remaining ?? 0),
    printed_orders: Number(orderStats.rows[0]?.printed_orders ?? 0),
    inventory_remaining: Number(inventoryStats.rows[0]?.inventory_remaining ?? 0),
    inventory_reserved: Number(inventoryStats.rows[0]?.inventory_reserved ?? 0),
    low_stock_items: Number(inventoryStats.rows[0]?.low_stock_items ?? 0),
    active_alerts: Number(alertStats.rows[0]?.active_alerts ?? 0),
    active_staff: Number(staffStats.rows[0]?.active_staff ?? 0),
    packing_speed: Number(staffStats.rows[0]?.packing_speed ?? 0),
  };
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

  const staff = await pool.query(
    'SELECT id, active, role_code FROM processing_staff WHERE phone = $1',
    [normalizedPhone],
  );
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
      return ok(
        res,
        {
          phone: normalizedPhone,
          otp,
          bypass_mode: true,
          role_code: staff.rows[0].role_code,
        },
        'OTP fallback mode',
      );
    }
  }

  return ok(
    res,
    { phone: normalizedPhone, otp: env.otpBypass ? otp : null, role_code: staff.rows[0].role_code },
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
    `SELECT id, name, phone, employee_code, active, device_id, role_code
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
    role_code: staff.role_code,
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
        role_code: staff.role_code,
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

processingRouter.get('/dashboard', async (_req, res) => {
  return ok(res, await getDashboardPayload());
});

processingRouter.post('/generate-routes', async (_req, res) => {
  try {
    const result = await generateTodayRoutes();
    return ok(res, result, 'Routes generated');
  } catch (error) {
    return fail(res, 500, `Route generation failed: ${error.message}`);
  }
});

processingRouter.get('/routes-today', async (_req, res) => {
  const rows = await pool.query(
    `WITH todays_orders AS (
       SELECT o.route_id,
              o.sector_id,
              o.building_id,
              COALESCE(o.packing_status::text, 'PLACED') AS packing_status,
              COALESCE(o.print_status::text, 'PLACED') AS print_status
       FROM orders o
       WHERE o.created_at >= CURRENT_DATE
         AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
         AND o.route_id IS NOT NULL
     ),
     order_stats AS (
       SELECT route_id,
              sector_id,
              COUNT(*)::int AS total_orders,
              COUNT(*) FILTER (WHERE packing_status = 'PACKED')::int AS packed_orders,
              COUNT(*) FILTER (WHERE packing_status <> 'PACKED')::int AS pending_orders,
              COUNT(*) FILTER (WHERE print_status = 'PRINTED')::int AS printed_orders,
              COUNT(DISTINCT building_id)::int AS total_buildings
       FROM todays_orders
       GROUP BY route_id, sector_id
     ),
     crate_stats AS (
       SELECT route_id, COUNT(*)::int AS total_crates
       FROM route_crates
       GROUP BY route_id
     )
     SELECT stats.route_id,
            r.route_code,
            r.optimized,
            r.total_distance_km,
            r.estimated_time_minutes,
            r.generated_at,
            s.code AS sector_code,
            s.name AS sector_name,
            stats.total_orders,
            stats.packed_orders,
            stats.pending_orders,
            stats.printed_orders,
            stats.total_buildings,
            COALESCE(crates.total_crates, 0) AS total_crates
     FROM order_stats stats
     JOIN routes r ON r.id = stats.route_id
     JOIN sectors s ON s.id = stats.sector_id
     LEFT JOIN crate_stats crates ON crates.route_id = stats.route_id
     ORDER BY s.code ASC, r.route_code ASC`,
  );

  return ok(res, rows.rows);
});

processingRouter.get('/route-summary/:routeId', async (req, res) => {
  const routeId = Number(req.params.routeId);
  if (!Number.isFinite(routeId) || routeId <= 0) return fail(res, 400, 'Invalid route_id');

  const [routeRow, itemSummary, crates] = await Promise.all([
    pool.query(
      `SELECT r.id AS route_id,
              r.route_code,
              r.optimized,
              r.total_orders,
              r.total_distance_km,
              r.estimated_time_minutes,
              r.generated_at,
              s.code AS sector_code,
              s.name AS sector_name
       FROM routes r
       JOIN sectors s ON s.id = r.sector_id
       WHERE r.id = $1`,
      [routeId],
    ),
    pool.query(
      `SELECT p.name,
              COALESCE(SUM(oi.quantity),0)::numeric(12,3) AS total_quantity
       FROM order_items oi
       JOIN orders o ON o.id = oi.order_id
       JOIN products p ON p.id = oi.product_id
       WHERE o.route_id = $1
         AND o.created_at >= CURRENT_DATE
         AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
       GROUP BY p.name
       ORDER BY p.name ASC`,
      [routeId],
    ),
    pool.query(
      `SELECT crate_code, stop_from, stop_to, max_capacity, current_orders
       FROM route_crates
       WHERE route_id = $1
       ORDER BY stop_from ASC`,
      [routeId],
    ),
  ]);

  if (!routeRow.rowCount) return fail(res, 404, 'Route not found');
  return ok(res, {
    ...routeRow.rows[0],
    item_summary: itemSummary.rows,
    crate_plan: crates.rows,
  });
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
            o.building_id,
            COALESCE(b.name, 'Independent House') AS building_name,
            COALESCE(u.name, 'Customer') AS customer_name,
            u.phone,
            o.total AS order_value,
            COALESCE(o.packing_status::text, 'PLACED') AS packing_status,
            COALESCE(o.print_status::text, 'PLACED') AS print_status,
            o.route_id,
            o.customer_ref,
            o.crate_number,
            COALESCE(pl.locked_until, NULL) AS lock_until,
            ps.name AS locked_by_name,
            COALESCE(
              rc.crate_code,
              plog.crate_number,
              CONCAT('CRATE-', CEIL(COALESCE(o.stop_number, 1)::numeric / 15.0)::text)
            ) AS crate_suggestion,
            CONCAT_WS(', ', a.line1, a.city, a.state, a.pincode) AS address,
            COALESCE(
              JSON_AGG(
                JSON_BUILD_OBJECT(
                  'name', p.name,
                  'quantity', oi.quantity,
                  'unit_price', oi.unit_price,
                  'allocation_status', oa.status,
                  'reserved_qty', oa.reserved_qty,
                  'shortage_qty', oa.shortage_qty
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
     LEFT JOIN order_allocations oa
       ON oa.order_id = o.id
      AND oa.product_id = oi.product_id
      AND oa.business_date = CURRENT_DATE
     LEFT JOIN route_crates rc
       ON rc.route_id = o.route_id
      AND o.stop_number BETWEEN rc.stop_from AND rc.stop_to
     LEFT JOIN LATERAL (
       SELECT crate_number
       FROM packing_log
       WHERE order_id = o.id
       ORDER BY packed_at DESC
       LIMIT 1
     ) plog ON TRUE
     LEFT JOIN processing_order_locks pl
       ON pl.order_id = o.id
      AND pl.locked_until >= NOW()
     LEFT JOIN processing_staff ps
       ON ps.id = pl.processing_staff_id
     WHERE o.route_id = $1
       AND o.created_at >= CURRENT_DATE
       AND o.created_at < (CURRENT_DATE + INTERVAL '1 day')
     GROUP BY o.id, b.name, u.name, u.phone, a.line1, a.city, a.state, a.pincode,
              rc.crate_code, plog.crate_number, pl.locked_until, ps.name
     ORDER BY COALESCE(o.stop_number, 9999) ASC, COALESCE(o.floor_number, 9999) ASC, COALESCE(o.flat_number, 'ZZZ') ASC, o.id ASC`,
    [routeId],
  );

  return ok(res, {
    route_type: routeTypeForOrders(rows.rows),
    orders: rows.rows,
  });
});

processingRouter.get('/route-labels/:routeId', async (req, res) => {
  const routeId = Number(req.params.routeId);
  if (!Number.isFinite(routeId) || routeId <= 0) return fail(res, 400, 'Invalid route_id');

  const labels = await pool.query(
    `SELECT o.id AS order_id,
            COALESCE(u.name, 'Customer') AS customer_name,
            s.code AS sector_code,
            COALESCE(b.name, 'Independent House') AS building_name,
            COALESCE(o.floor_number, 0) AS floor_number,
            COALESCE(o.flat_number, '-') AS flat_number,
            o.route_id,
            COALESCE(o.stop_number, 0) AS stop_number,
            expected_barcode,
            json_build_object(
              'order_id', o.id,
              'route_id', o.route_id,
              'stop_number', o.stop_number,
              'customer_ref', o.customer_ref
            ) AS qr_payload
     FROM (
       SELECT id, route_id, stop_number, customer_ref, sector_id, building_id, floor_number, flat_number,
              CASE
                WHEN customer_ref IS NOT NULL AND customer_ref <> '' THEN UPPER(customer_ref)
                ELSE CONCAT('ORD-', id)
              END AS expected_barcode
       FROM orders
     ) o
     JOIN orders full_order ON full_order.id = o.id
     JOIN users u ON u.id = full_order.user_id
     JOIN sectors s ON s.id = o.sector_id
     LEFT JOIN buildings b ON b.id = o.building_id
     WHERE o.route_id = $1
       AND full_order.created_at >= CURRENT_DATE
       AND full_order.created_at < (CURRENT_DATE + INTERVAL '1 day')
     ORDER BY COALESCE(o.stop_number, 9999) ASC, o.id ASC`,
    [routeId],
  );

  return ok(res, labels.rows);
});

processingRouter.get('/inventory-alerts', async (_req, res) => {
  const rows = await pool.query(
    `SELECT ia.id,
            ia.alert_type,
            ia.severity,
            ia.message,
            ia.acknowledged,
            ia.created_at,
            p.name AS product_name,
            r.route_code
     FROM inventory_alerts ia
     LEFT JOIN products p ON p.id = ia.product_id
     LEFT JOIN routes r ON r.id = ia.route_id
     WHERE ia.business_date = CURRENT_DATE
     ORDER BY ia.created_at DESC`,
  );
  return ok(res, rows.rows);
});

processingRouter.get('/goods-received', async (_req, res) => {
  const rows = await pool.query(
    `SELECT gr.id,
            gr.supplier_name,
            gr.invoice_number,
            gr.image_url,
            gr.total_cost,
            gr.status,
            gr.received_at,
            ps.name AS received_by,
            COALESCE(
              JSON_AGG(
                JSON_BUILD_OBJECT(
                  'id', gri.id,
                  'product_id', gri.product_id,
                  'product_name', p.name,
                  'quantity_received', gri.quantity_received,
                  'rate_per_kg', gri.rate_per_kg,
                  'total_cost', gri.total_cost,
                  'quality_status', gri.quality_status
                )
              ) FILTER (WHERE gri.id IS NOT NULL),
              '[]'::json
            ) AS items
     FROM goods_received gr
     LEFT JOIN processing_staff ps ON ps.id = gr.received_by_processing_staff_id
     LEFT JOIN goods_received_items gri ON gri.goods_received_id = gr.id
     LEFT JOIN products p ON p.id = gri.product_id
     GROUP BY gr.id, ps.name
     ORDER BY gr.received_at DESC, gr.id DESC`,
  );
  return ok(res, rows.rows);
});

processingRouter.post('/goods-received', async (req, res) => {
  const parsed = goodsReceivedSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid goods received payload');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const totalCost = parsed.data.items.reduce(
      (sum, item) => sum + Number(item.quantity_received) * Number(item.rate_per_kg),
      0,
    );

    const receipt = await client.query(
      `INSERT INTO goods_received
         (supplier_name, invoice_number, image_url, total_cost, status, received_at, received_by_processing_staff_id, created_at, updated_at)
       VALUES
         ($1, $2, $3, $4, 'AWAITING_QUALITY_CHECK', NOW(), $5, NOW(), NOW())
       RETURNING id`,
      [
        parsed.data.supplier_name,
        parsed.data.invoice_number,
        parsed.data.image_url ?? null,
        totalCost,
        req.user.sub,
      ],
    );

    for (const item of parsed.data.items) {
      await client.query(
        `INSERT INTO goods_received_items
           (goods_received_id, product_id, quantity_received, rate_per_kg, total_cost, quality_status, created_at, updated_at)
         VALUES
           ($1, $2, $3, $4, $5, 'AWAITING_QUALITY_CHECK', NOW(), NOW())`,
        [
          receipt.rows[0].id,
          item.product_id,
          item.quantity_received,
          item.rate_per_kg,
          Number(item.quantity_received) * Number(item.rate_per_kg),
        ],
      );

      await logStaffActivity(client, {
        processing_staff_id: req.user.sub,
        activity_type: 'GOODS_RECEIVED',
        details: {
          goods_received_id: receipt.rows[0].id,
          product_id: item.product_id,
          quantity_received: item.quantity_received,
        },
      });
    }

    await client.query('COMMIT');
    return ok(res, { goods_received_id: receipt.rows[0].id }, 'Goods received recorded');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Goods received failed: ${error.message}`);
  } finally {
    client.release();
  }
});

processingRouter.get('/quality-queue', async (_req, res) => {
  const rows = await pool.query(
    `SELECT gri.id AS goods_received_item_id,
            gri.goods_received_id,
            gr.supplier_name,
            gr.invoice_number,
            gr.received_at,
            p.id AS product_id,
            p.name AS product_name,
            gri.quantity_received,
            gri.rate_per_kg,
            gri.quality_status
     FROM goods_received_items gri
     JOIN goods_received gr ON gr.id = gri.goods_received_id
     JOIN products p ON p.id = gri.product_id
     WHERE gri.quality_status <> 'APPROVED'
     ORDER BY gr.received_at DESC, gri.id DESC`,
  );
  return ok(res, rows.rows);
});

processingRouter.post('/quality-check', async (req, res) => {
  const parsed = qualityCheckSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid quality check payload');

  const total = parsed.data.good_quantity + parsed.data.damaged_quantity + parsed.data.waste_quantity;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const itemRow = await client.query(
      `SELECT gri.id, gri.goods_received_id, gri.quantity_received
       FROM goods_received_items gri
       WHERE gri.id = $1
         AND gri.product_id = $2
       LIMIT 1`,
      [parsed.data.goods_received_item_id, parsed.data.product_id],
    );
    if (!itemRow.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Goods received item not found');
    }

    const receivedQty = Number(itemRow.rows[0].quantity_received ?? 0);
    if (total > receivedQty + 0.001) {
      await client.query('ROLLBACK');
      return fail(res, 400, 'Quality quantities exceed received quantity');
    }

    await client.query(
      `INSERT INTO quality_checks
         (goods_received_item_id, product_id, good_quantity, damaged_quantity, waste_quantity, damage_reason, approved_at, approved_by_processing_staff_id, created_at, updated_at)
       VALUES
         ($1, $2, $3, $4, $5, $6, NOW(), $7, NOW(), NOW())`,
      [
        parsed.data.goods_received_item_id,
        parsed.data.product_id,
        parsed.data.good_quantity,
        parsed.data.damaged_quantity,
        parsed.data.waste_quantity,
        parsed.data.damage_reason ?? null,
        req.user.sub,
      ],
    );

    await client.query(
      `UPDATE goods_received_items
       SET quality_status = 'APPROVED',
           updated_at = NOW()
       WHERE id = $1`,
      [parsed.data.goods_received_item_id],
    );

    await client.query(
      `INSERT INTO inventory
         (product_id, warehouse_code, opening_stock, purchased_qty, allocated_qty, damaged_qty, wastage_qty, remaining_qty, low_stock_threshold, quality_check_approved, stock_date, created_at, updated_at)
       VALUES
         ($1, 'WH-01', 0, $2, 0, $3, $4, $5, 0, TRUE, CURRENT_DATE, NOW(), NOW())
       ON CONFLICT DO NOTHING`,
      [
        parsed.data.product_id,
        parsed.data.good_quantity,
        parsed.data.damaged_quantity,
        parsed.data.waste_quantity,
        parsed.data.good_quantity,
      ],
    );

    await client.query(
      `UPDATE inventory
       SET purchased_qty = purchased_qty + $2,
           damaged_qty = damaged_qty + $3,
           wastage_qty = wastage_qty + $4,
           remaining_qty = remaining_qty + $2,
           quality_check_approved = TRUE,
           updated_at = NOW()
       WHERE product_id = $1
         AND stock_date = CURRENT_DATE`,
      [
        parsed.data.product_id,
        parsed.data.good_quantity,
        parsed.data.damaged_quantity,
        parsed.data.waste_quantity,
      ],
    );

    await client.query(
      `UPDATE goods_received
       SET status = CASE
         WHEN NOT EXISTS (
           SELECT 1 FROM goods_received_items
           WHERE goods_received_id = $1
             AND quality_status <> 'APPROVED'
         ) THEN 'APPROVED_FOR_PACKING'
         ELSE status
       END,
       updated_at = NOW()
       WHERE id = $1`,
      [itemRow.rows[0].goods_received_id],
    );

    await logStaffActivity(client, {
      processing_staff_id: req.user.sub,
      activity_type: 'QUALITY_APPROVED',
      details: parsed.data,
    });

    await client.query('COMMIT');
    return ok(res, true, 'Quality approved');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Quality check failed: ${error.message}`);
  } finally {
    client.release();
  }
});

processingRouter.post('/lock-order', async (req, res) => {
  const parsed = lockSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');
  const orderId = parsed.data.order_id;

  const order = await pool.query(
    `SELECT id, route_id
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

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await logStaffActivity(client, {
      processing_staff_id: req.user.sub,
      activity_type: 'ORDER_LOCKED',
      order_id: orderId,
      route_id: order.rows[0].route_id,
    });
    await client.query('COMMIT');
  } catch {
    await client.query('ROLLBACK');
  } finally {
    client.release();
  }

  return ok(res, { order_id: orderId, locked_until: new Date(Date.now() + 2 * 60 * 1000) }, 'Order locked');
});

processingRouter.post('/unlock-order', async (req, res) => {
  const parsed = unlockSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const orderRow = await pool.query('SELECT route_id FROM orders WHERE id = $1', [parsed.data.order_id]);

  await pool.query(
    `DELETE FROM processing_order_locks
     WHERE order_id = $1
       AND processing_staff_id = $2`,
    [parsed.data.order_id, req.user.sub],
  );

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await logStaffActivity(client, {
      processing_staff_id: req.user.sub,
      activity_type: 'ORDER_UNLOCKED',
      order_id: parsed.data.order_id,
      route_id: orderRow.rows[0]?.route_id ?? null,
    });
    await client.query('COMMIT');
  } catch {
    await client.query('ROLLBACK');
  } finally {
    client.release();
  }

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
    `SELECT o.id, o.route_id, o.customer_ref, o.packing_status, o.stop_number
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

  const allocationCheck = await pool.query(
    `SELECT COUNT(*)::int AS shortage_rows
     FROM order_allocations
     WHERE business_date = CURRENT_DATE
       AND order_id = $1
       AND shortage_qty > 0`,
    [parsed.data.order_id],
  );
  if (Number(allocationCheck.rows[0]?.shortage_rows ?? 0) > 0) {
    return fail(res, 409, 'Insufficient reserved inventory for this order. Manager attention required.');
  }

  const expected = expectedBarcodeForOrder({ id: order.id, customer_ref: order.customer_ref });
  const provided = `${parsed.data.barcode}`.trim().toUpperCase();
  if (provided !== expected) {
    return fail(res, 409, `Invalid barcode for this order. Expected code: ${expected}`);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    await client.query(
      `UPDATE orders
       SET packing_status = 'PACKED',
           status = 'PACKED',
           packed_at = NOW(),
           packed_by = $2,
           crate_number = COALESCE($3, crate_number),
           updated_at = NOW()
       WHERE id = $1`,
      [order.id, req.user.sub, parsed.data.crate_number ?? null],
    );

    await client.query(
      `INSERT INTO packing_log (order_id, route_id, crate_number, barcode_value, packed_at, status, processing_staff_id, updated_at)
       VALUES ($1, $2, $3, $4, NOW(), 'PACKED', $5, NOW())`,
      [order.id, order.route_id, parsed.data.crate_number ?? null, provided, req.user.sub],
    );

    const allocations = await client.query(
      `SELECT oa.id, oa.product_id, oa.reserved_qty, i.id AS inventory_id, i.remaining_qty, i.allocated_qty
       FROM order_allocations oa
       LEFT JOIN inventory i
         ON i.product_id = oa.product_id
        AND i.stock_date = CURRENT_DATE
       WHERE oa.business_date = CURRENT_DATE
         AND oa.order_id = $1`,
      [order.id],
    );

    for (const allocation of allocations.rows) {
      const reservedQty = Number(allocation.reserved_qty ?? 0);
      if (allocation.inventory_id && reservedQty > 0) {
        await client.query(
          `UPDATE inventory
           SET allocated_qty = GREATEST(0, allocated_qty - $2),
               remaining_qty = GREATEST(0, remaining_qty - $2),
               updated_at = NOW()
           WHERE id = $1`,
          [allocation.inventory_id, reservedQty],
        );
      }

      await client.query(
        `UPDATE order_allocations
         SET used_qty = reserved_qty,
             reserved_qty = 0,
             status = 'USED',
             updated_at = NOW()
         WHERE id = $1`,
        [allocation.id],
      );
    }

    await client.query(
      `DELETE FROM processing_order_locks
       WHERE order_id = $1`,
      [order.id],
    );

    await logStaffActivity(client, {
      processing_staff_id: req.user.sub,
      activity_type: 'ORDER_PACKED',
      order_id: order.id,
      route_id: order.route_id,
      details: {
        crate_number: parsed.data.crate_number ?? null,
        barcode: provided,
        stop_number: order.stop_number,
      },
    });

    await client.query('COMMIT');
    return ok(res, true, 'Order packed');
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Packing failed: ${error.message}`);
  } finally {
    client.release();
  }
});

processingRouter.post('/print-route-labels', async (req, res) => {
  const parsed = printSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const labels = await pool.query(
    `SELECT id
     FROM orders
     WHERE route_id = $1
       AND created_at >= CURRENT_DATE
       AND created_at < (CURRENT_DATE + INTERVAL '1 day')
     ORDER BY COALESCE(stop_number, 9999) ASC, id ASC`,
    [parsed.data.route_id],
  );
  if (!labels.rowCount) return fail(res, 404, 'No labels found for this route');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const updated = await client.query(
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

    for (const row of updated.rows) {
      await client.query(
        `INSERT INTO print_logs
           (business_date, route_id, order_id, action_type, reason, printed_by_processing_staff_id, created_at)
         VALUES
           (CURRENT_DATE, $1, $2, $3, $4, $5, NOW())`,
        [
          parsed.data.route_id,
          row.id,
          parsed.data.action_type ?? 'PRINT',
          parsed.data.reason ?? null,
          req.user.sub,
        ],
      );
    }

    await logStaffActivity(client, {
      processing_staff_id: req.user.sub,
      activity_type: 'LABELS_PRINTED',
      route_id: parsed.data.route_id,
      details: {
        labels_printed: updated.rowCount,
        action_type: parsed.data.action_type ?? 'PRINT',
        reason: parsed.data.reason ?? null,
      },
    });

    await client.query('COMMIT');
    return ok(
      res,
      { route_id: parsed.data.route_id, labels_printed: updated.rowCount },
      'Route labels marked as printed',
    );
  } catch (error) {
    await client.query('ROLLBACK');
    return fail(res, 500, `Label printing failed: ${error.message}`);
  } finally {
    client.release();
  }
});

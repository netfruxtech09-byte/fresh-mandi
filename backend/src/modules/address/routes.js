import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { authMiddleware } from '../../middleware/auth.js';
import { ok, fail } from '../../utils/response.js';

export const addressRouter = express.Router();
addressRouter.use(authMiddleware);

const serviceableCityAliases = new Set([
  'mohali',
  'sas nagar',
  's.a.s nagar',
  's.a.s. nagar',
  'sahibzada ajit singh nagar',
  'ajitgarh',
]);

const schema = z.object({
  label: z.string().min(2),
  line1: z.string().min(2),
  city: z.string().min(2),
  state: z.string().min(2),
  pincode: z.string().min(4),
  sector_id: z.coerce.number().int().positive(),
  building_id: z.coerce.number().int().positive().optional().nullable(),
  is_default: z.boolean().optional(),
});

function normalizePincode(value) {
  return `${value ?? ''}`.replace(/\D/g, '');
}

function normalizeCity(value) {
  return `${value ?? ''}`
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

async function getServiceAddressConfig() {
  const rows = await pool.query(
    `SELECT key, value
     FROM app_settings
     WHERE key IN ('service_city', 'service_pincodes')`,
  );
  const map = Object.fromEntries(rows.rows.map((r) => [r.key, `${r.value ?? ''}`.trim()]));
  return {
    serviceCity: map.service_city || 'Mohali',
    allowedPincodes: new Set(
      (map.service_pincodes || '')
        .split(',')
        .map((v) => v.trim())
        .filter(Boolean),
    ),
  };
}

async function validateAddressCoverage({
  city,
  pincode,
  sectorId,
  buildingId,
}) {
  const { serviceCity, allowedPincodes } = await getServiceAddressConfig();
  const normalizedCity = normalizeCity(city);
  const normalizedPincode = normalizePincode(pincode);

  if (!serviceableCityAliases.has(normalizedCity)) {
    return {
      ok: false,
      message: `Currently we are delivering only in ${serviceCity}. Please choose a valid ${serviceCity} address.`,
    };
  }

  if (normalizedPincode.length !== 6) {
    return {
      ok: false,
      message: 'Please enter a valid 6-digit pincode.',
    };
  }

  if (allowedPincodes.size > 0 && !allowedPincodes.has(normalizedPincode)) {
    return {
      ok: false,
      message: 'Currently we are not delivering at your place. Please use a serviceable address.',
    };
  }

  const sector = await pool.query(
    `SELECT id
     FROM sectors
     WHERE id = $1
       AND active = TRUE
     LIMIT 1`,
    [sectorId],
  );
  if (!sector.rowCount) {
    return {
      ok: false,
      message: 'Selected sector is invalid or inactive. Please select a valid sector.',
    };
  }

  if (buildingId) {
    const building = await pool.query(
      `SELECT id
       FROM buildings
       WHERE id = $1
         AND sector_id = $2
         AND active = TRUE
       LIMIT 1`,
      [buildingId, sectorId],
    );
    if (!building.rowCount) {
      return {
        ok: false,
        message: 'Selected building does not belong to selected sector.',
      };
    }
  }

  return { ok: true, pincode: normalizedPincode };
}

addressRouter.get('/', async (req, res) => {
  const rows = await pool.query(
    'SELECT * FROM addresses WHERE user_id = $1 ORDER BY id DESC',
    [req.user.sub],
  );
  return ok(res, rows.rows);
});

addressRouter.post('/', async (req, res) => {
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const a = parsed.data;
  const coverage = await validateAddressCoverage({
    city: a.city,
    pincode: a.pincode,
    sectorId: a.sector_id,
    buildingId: a.building_id ?? null,
  });
  if (!coverage.ok) return fail(res, 400, coverage.message);

  if (a.is_default) {
    await pool.query(
      'UPDATE addresses SET is_default = false WHERE user_id = $1',
      [req.user.sub],
    );
  }

  const row = await pool.query(
    `INSERT INTO addresses (user_id, label, line1, city, state, pincode, sector_id, building_id, is_default)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     RETURNING *`,
    [
      req.user.sub,
      a.label,
      a.line1,
      a.city.trim(),
      a.state.trim(),
      coverage.pincode,
      a.sector_id,
      a.building_id ?? null,
      a.is_default ?? false,
    ],
  );

  return ok(res, row.rows[0], 'Address added');
});

addressRouter.put('/:id', async (req, res) => {
  const parsed = schema.partial().safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const existing = await pool.query(
    'SELECT * FROM addresses WHERE id = $1 AND user_id = $2 LIMIT 1',
    [req.params.id, req.user.sub],
  );
  if (!existing.rowCount) return fail(res, 404, 'Address not found');

  const current = existing.rows[0];
  const a = parsed.data;

  const finalCity = a.city ?? current.city;
  const finalPincode = a.pincode ?? current.pincode;
  const finalSectorId = a.sector_id ?? current.sector_id;
  const finalBuildingId = a.building_id ?? current.building_id ?? null;
  if (!finalSectorId) {
    return fail(res, 400, 'Please select a valid sector for this address.');
  }

  const coverage = await validateAddressCoverage({
    city: finalCity,
    pincode: finalPincode,
    sectorId: finalSectorId,
    buildingId: finalBuildingId,
  });
  if (!coverage.ok) return fail(res, 400, coverage.message);

  if (a.is_default === true) {
    await pool.query(
      'UPDATE addresses SET is_default = false WHERE user_id = $1',
      [req.user.sub],
    );
  }

  const row = await pool.query(
    `UPDATE addresses SET
      label = COALESCE($1, label),
      line1 = COALESCE($2, line1),
      city = COALESCE($3, city),
      state = COALESCE($4, state),
      pincode = $5,
      sector_id = $6,
      building_id = $7,
      is_default = COALESCE($8, is_default),
      updated_at = NOW()
     WHERE id = $9 AND user_id = $10
     RETURNING *`,
    [
      a.label ?? null,
      a.line1 ?? null,
      a.city?.trim() ?? null,
      a.state?.trim() ?? null,
      coverage.pincode,
      finalSectorId,
      finalBuildingId,
      a.is_default ?? null,
      req.params.id,
      req.user.sub,
    ],
  );

  return ok(res, row.rows[0], 'Address updated');
});

addressRouter.delete('/:id', async (req, res) => {
  const addressId = Number(req.params.id);
  if (!Number.isFinite(addressId) || addressId <= 0) {
    return fail(res, 400, 'Invalid address id');
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const existing = await client.query(
      `SELECT id, is_default
       FROM addresses
       WHERE id = $1 AND user_id = $2
       LIMIT 1`,
      [addressId, req.user.sub],
    );
    if (!existing.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Address not found');
    }

    const wasDefault = existing.rows[0].is_default === true;
    if (wasDefault) {
      await client.query('ROLLBACK');
      return fail(
        res,
        409,
        'Default address cannot be deleted. Please set another address as default first.',
      );
    }

    const result = await client.query(
      'DELETE FROM addresses WHERE id = $1 AND user_id = $2 RETURNING id',
      [addressId, req.user.sub],
    );

    if (!result.rowCount) {
      await client.query('ROLLBACK');
      return fail(res, 404, 'Address not found');
    }

    await client.query('COMMIT');
    return ok(res, true, 'Address deleted');
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    if (err?.code === '23503') {
      return fail(
        res,
        409,
        'This address is linked with existing orders and cannot be deleted. Please keep it or add a new default address.',
      );
    }
    console.error('Delete address error:', err);
    return fail(res, 500, 'Failed to delete address');
  } finally {
    client.release();
  }
});

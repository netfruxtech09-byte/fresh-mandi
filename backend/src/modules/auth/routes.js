import express from 'express';
import { z } from 'zod';

import { pool } from '../../db/pool.js';
import { env } from '../../config/env.js';
import { signToken } from '../../utils/jwt.js';
import { ok, fail } from '../../utils/response.js';
import { normalizeIndianPhone, sendOtpSms } from '../../utils/sms.js';

export const authRouter = express.Router();

const phoneSchema = z.object({ phone: z.string().min(10).max(20) });
const verifySchema = z.object({ phone: z.string().min(10).max(20), otp: z.string().length(6) });

authRouter.post('/otp/request', async (req, res) => {
  const parsed = phoneSchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid phone');

  const normalizedPhone = normalizeIndianPhone(parsed.data.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const deliveryExecutive = await pool.query(
    'SELECT id, active FROM delivery_executives WHERE phone = $1',
    [normalizedPhone],
  );
  if (deliveryExecutive.rowCount) {
    return fail(
      res,
      403,
      'This number is linked to a delivery executive account. Please login from Delivery app.',
    );
  }

  const processingStaff = await pool.query(
    'SELECT id, active FROM processing_staff WHERE phone = $1',
    [normalizedPhone],
  );
  if (processingStaff.rowCount) {
    return fail(
      res,
      403,
      'This number is linked to processing staff account. Please login from Processing app.',
    );
  }

  const otp = env.otpBypass ? env.otpBypassCode : `${Math.floor(100000 + Math.random() * 900000)}`;

  await pool.query(
    `INSERT INTO otp_codes (phone, code, expires_at)
     VALUES ($1, $2, NOW() + INTERVAL '10 minutes')
     ON CONFLICT (phone) DO UPDATE SET code = $2, expires_at = NOW() + INTERVAL '10 minutes', updated_at = NOW()`,
    [normalizedPhone, otp],
  );

  if (!env.otpBypass) {
    try {
      await sendOtpSms(normalizedPhone, otp);
    } catch (error) {
      if (env.otpFallbackOnSmsFailure) {
        return ok(
          res,
          { phone: normalizedPhone, otp },
          `OTP fallback mode: SMS failed (${error.message})`,
        );
      }
      return fail(res, 502, `OTP send failed: ${error.message}`);
    }
  }

  return ok(
    res,
    { phone: normalizedPhone, otp: env.otpBypass ? otp : null },
    env.otpBypass ? 'OTP generated (bypass mode)' : 'OTP sent',
  );
});

authRouter.post('/otp/verify', async (req, res) => {
  const parsed = verifySchema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, 'Invalid payload');

  const normalizedPhone = normalizeIndianPhone(parsed.data.phone);
  if (!normalizedPhone) return fail(res, 400, 'Invalid Indian phone number');

  const deliveryExecutive = await pool.query(
    'SELECT id, active FROM delivery_executives WHERE phone = $1',
    [normalizedPhone],
  );
  if (deliveryExecutive.rowCount) {
    return fail(
      res,
      403,
      'This number is linked to a delivery executive account. Please login from Delivery app.',
    );
  }

  const processingStaff = await pool.query(
    'SELECT id, active FROM processing_staff WHERE phone = $1',
    [normalizedPhone],
  );
  if (processingStaff.rowCount) {
    return fail(
      res,
      403,
      'This number is linked to processing staff account. Please login from Processing app.',
    );
  }

  const { otp } = parsed.data;
  const otpRow = await pool.query(
    `SELECT * FROM otp_codes WHERE phone = $1 AND code = $2 AND expires_at > NOW()`,
    [normalizedPhone, otp],
  );
  if (!otpRow.rowCount) return fail(res, 401, 'Invalid OTP');

  const existingUser = await pool.query('SELECT id FROM users WHERE phone = $1', [normalizedPhone]);
  const isNewUser = existingUser.rowCount === 0;

  const userRow = await pool.query(
    `INSERT INTO users (phone) VALUES ($1)
     ON CONFLICT (phone) DO UPDATE SET updated_at = NOW()
     RETURNING id, phone, name`,
    [normalizedPhone],
  );

  const user = userRow.rows[0];
  const addressCount = await pool.query(
    'SELECT COUNT(*)::int AS count FROM addresses WHERE user_id = $1',
    [user.id],
  );
  const hasAddress = (addressCount.rows[0]?.count ?? 0) > 0;
  const token = signToken({ sub: user.id, phone: user.phone });

  return ok(res, { token, user, is_new_user: isNewUser, has_address: hasAddress }, 'Authenticated');
});

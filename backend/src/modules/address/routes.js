import express from "express";
import { z } from "zod";

import { pool } from "../../db/pool.js";
import { authMiddleware } from "../../middleware/auth.js";
import { ok, fail } from "../../utils/response.js";

export const addressRouter = express.Router();
addressRouter.use(authMiddleware);

const schema = z.object({
  label: z.string().min(2),
  line1: z.string().min(2),
  city: z.string().min(2),
  state: z.string().min(2),
  pincode: z.string().min(4),
  is_default: z.boolean().optional(),
});

addressRouter.get("/", async (req, res) => {
  const rows = await pool.query(
    "SELECT * FROM addresses WHERE user_id = $1 ORDER BY id DESC",
    [req.user.sub],
  );
  return ok(res, rows.rows);
});

addressRouter.post("/", async (req, res) => {
  const parsed = schema.safeParse(req.body);
  if (!parsed.success) return fail(res, 400, "Invalid payload");
  const a = parsed.data;
  if (a.is_default) {
    await pool.query(
      "UPDATE addresses SET is_default = false WHERE user_id = $1",
      [req.user.sub],
    );
  }
  const row = await pool.query(
    `INSERT INTO addresses (user_id, label, line1, city, state, pincode, is_default)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     RETURNING *`,
    [
      req.user.sub,
      a.label,
      a.line1,
      a.city,
      a.state,
      a.pincode,
      a.is_default ?? false,
    ],
  );
  return ok(res, row.rows[0], "Address added");
});

addressRouter.put("/:id", async (req, res) => {
  const parsed = schema.partial().safeParse(req.body);
  if (!parsed.success) return fail(res, 400, "Invalid payload");
  const a = parsed.data;
  const row = await pool.query(
    `UPDATE addresses SET
      label = COALESCE($1, label),
      line1 = COALESCE($2, line1),
      city = COALESCE($3, city),
      state = COALESCE($4, state),
      pincode = COALESCE($5, pincode),
      is_default = COALESCE($6, is_default),
      updated_at = NOW()
     WHERE id = $7 AND user_id = $8
     RETURNING *`,
    [
      a.label ?? null,
      a.line1 ?? null,
      a.city ?? null,
      a.state ?? null,
      a.pincode ?? null,
      a.is_default ?? null,
      req.params.id,
      req.user.sub,
    ],
  );
  return ok(res, row.rows[0], "Address updated");
});

addressRouter.delete("/:id", async (req, res) => {
  addressRouter.delete("/:id", async (req, res) => {
    try {
      const result = await pool.query(
        "DELETE FROM addresses WHERE id = $1 AND user_id = $2 RETURNING id",
        [req.params.id, req.user.sub],
      );

      if (result.rowCount === 0) {
        return fail(res, 404, "Address not found");
      }

      return ok(res, true, "Address deleted");
    } catch (err) {
      console.error("Delete address error:", err);
      return fail(res, 500, "Failed to delete address");
    }
  });
});

import { pool } from '../db/pool.js';
import { fail } from '../utils/response.js';

export async function resolveAdminPermissions(adminId) {
  const result = await pool.query(
    `SELECT DISTINCT p.code
     FROM admin_user_roles aur
     JOIN role_permissions rp ON rp.role_id = aur.role_id
     JOIN permissions p ON p.id = rp.permission_id
     WHERE aur.admin_user_id = $1`,
    [adminId],
  );

  return result.rows.map((row) => row.code);
}

export function requirePermission(permissionCode) {
  return async (req, res, next) => {
    if (req.user?.role !== 'admin') {
      return fail(res, 403, 'Admin access required');
    }

    if (req.user?.role_code === 'SUPER_ADMIN') {
      return next();
    }

    let permissions = Array.isArray(req.user?.permissions) ? req.user.permissions : null;
    if (!permissions) {
      permissions = await resolveAdminPermissions(req.user.sub);
      req.user.permissions = permissions;
    }

    if (!permissions.includes(permissionCode)) {
      return fail(res, 403, `Missing permission: ${permissionCode}`);
    }

    return next();
  };
}

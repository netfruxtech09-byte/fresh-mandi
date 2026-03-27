INSERT INTO categories (name, type, sort_order)
SELECT v.name, v.type, v.sort_order
FROM (
  VALUES
    ('Fruits', 'FRUIT', 1),
    ('Vegetables', 'VEGETABLE', 2)
) AS v(name, type, sort_order)
WHERE NOT EXISTS (
  SELECT 1 FROM categories c WHERE c.name = v.name AND c.type = v.type
);

INSERT INTO products (category_id, name, subcategory, unit, price, image_url)
SELECT c.id, v.name, v.subcategory, v.unit, v.price, NULL
FROM (
  VALUES
    ('FRUIT', 'Apple', 'Seasonal', '1 kg', 120::numeric),
    ('FRUIT', 'Banana', 'Seasonal', '500 g', 40::numeric),
    ('VEGETABLE', 'Tomato', 'Seasonal', '1 kg', 30::numeric),
    ('VEGETABLE', 'Broccoli', 'Out of Season', '250 g', 65::numeric)
) AS v(category_type, name, subcategory, unit, price)
JOIN categories c ON c.type = v.category_type
WHERE NOT EXISTS (
  SELECT 1
  FROM products p
  WHERE p.category_id = c.id
    AND p.name = v.name
    AND COALESCE(p.subcategory, '') = COALESCE(v.subcategory, '')
    AND p.unit = v.unit
);

INSERT INTO delivery_slots (label, starts_at, ends_at)
SELECT v.label, v.starts_at, v.ends_at
FROM (
  VALUES
    ('7:00 AM - 9:00 AM', '07:00:00'::time, '09:00:00'::time),
    ('9:00 AM - 11:00 AM', '09:00:00'::time, '11:00:00'::time)
) AS v(label, starts_at, ends_at)
WHERE NOT EXISTS (
  SELECT 1 FROM delivery_slots d WHERE d.label = v.label
);

INSERT INTO coupons (code, flat_discount, active, expires_at)
VALUES ('FRESH50', 50, true, NOW() + INTERVAL '180 days')
ON CONFLICT (code) DO NOTHING;

INSERT INTO app_settings (key, value)
VALUES
  ('cutoff_hour', '21'),
  ('gst_percent', '5'),
  ('service_city', 'Mohali'),
  ('service_pincodes', '')
ON CONFLICT (key) DO NOTHING;

INSERT INTO sectors (code, name, active)
VALUES
  ('85', 'Sector 85', true),
  ('86', 'Sector 86', true),
  ('87', 'Sector 87', true)
ON CONFLICT (code) DO NOTHING;

INSERT INTO delivery_executives (name, phone, employee_code, active)
VALUES
  ('Demo Delivery Executive', '9999999999', 'DLV-001', true)
ON CONFLICT (phone) DO NOTHING;

INSERT INTO processing_staff (name, phone, employee_code, active)
VALUES
  ('Demo Processing Staff', '9888888888', 'PRC-001', true)
ON CONFLICT (phone) DO NOTHING;

INSERT INTO delivery_route_assignments (business_date, route_id, delivery_executive_id, status)
SELECT CURRENT_DATE, r.id, d.id, 'ASSIGNED'
FROM routes r
JOIN delivery_executives d ON d.phone = '9999999999'
WHERE NOT EXISTS (
  SELECT 1
  FROM delivery_route_assignments a
  WHERE a.business_date = CURRENT_DATE
    AND a.delivery_executive_id = d.id
)
LIMIT 1;

INSERT INTO admin_users (name, email, password_hash, active)
VALUES (
  'Fresh Mandi Admin',
  'admin@freshmandi.local',
  '$2a$10$BIyqY0ZCnu7Lk9AG8Ys8jOgSfNHdFDjBCIQZSeVBzkd/uVHjsY43i',
  true
)
ON CONFLICT (email) DO NOTHING;

INSERT INTO roles (code, name, description)
VALUES
  ('SUPER_ADMIN', 'Super Admin', 'Full system access'),
  ('OPERATIONS_MANAGER', 'Operations Manager', 'Operations and order control'),
  ('PACKING_STAFF', 'Packing Staff', 'Packing and barcode workflow'),
  ('PROCUREMENT_MANAGER', 'Procurement Manager', 'Purchase planning and inventory intake'),
  ('DELIVERY_MANAGER', 'Delivery Manager', 'Delivery assignment and route execution'),
  ('ACCOUNTANT', 'Accountant', 'Payments, settlements, and financial reports')
ON CONFLICT (code) DO NOTHING;

INSERT INTO permissions (code, module, action, description)
VALUES
  ('dashboard:read', 'dashboard', 'read', 'Read dashboard KPIs'),
  ('orders:read', 'orders', 'read', 'Read orders'),
  ('orders:update_status', 'orders', 'update_status', 'Update order status'),
  ('orders:freeze', 'orders', 'freeze', 'Run order cutoff/freeze'),
  ('products:read', 'products', 'read', 'Read products'),
  ('products:write', 'products', 'write', 'Create/update/delete products'),
  ('purchase:read', 'purchase_planning', 'read', 'Read purchase planning'),
  ('purchase:write', 'purchase_planning', 'write', 'Generate/mark purchases'),
  ('inventory:read', 'inventory', 'read', 'Read inventory'),
  ('inventory:write', 'inventory', 'write', 'Update inventory'),
  ('packing:read', 'packing', 'read', 'Read packing routes'),
  ('packing:write', 'packing', 'write', 'Mark packed and assign crate'),
  ('delivery:read', 'delivery', 'read', 'Read delivery plans'),
  ('delivery:write', 'delivery', 'write', 'Assign delivery and update status'),
  ('payments:read', 'payments', 'read', 'Read payments and settlements'),
  ('payments:write', 'payments', 'write', 'Update payments'),
  ('reports:read', 'reports', 'read', 'Read reports'),
  ('reports:export', 'reports', 'export', 'Export PDF/Excel reports'),
  ('customers:read', 'customers', 'read', 'Read customer records'),
  ('customers:write', 'customers', 'write', 'Manage customer controls'),
  ('routes:read', 'routes', 'read', 'Read routes'),
  ('routes:write', 'routes', 'write', 'Manage routes/buildings/sequences'),
  ('settings:read', 'settings', 'read', 'Read system settings'),
  ('settings:write', 'settings', 'write', 'Update system settings'),
  ('users:manage_roles', 'users', 'manage_roles', 'Assign and update role access')
ON CONFLICT (code) DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON
  (
    r.code = 'SUPER_ADMIN'
    OR (r.code = 'OPERATIONS_MANAGER' AND p.code IN (
      'dashboard:read', 'orders:read', 'orders:update_status', 'orders:freeze',
      'packing:read', 'packing:write', 'delivery:read', 'delivery:write',
      'routes:read', 'routes:write', 'reports:read', 'reports:export'
    ))
    OR (r.code = 'PACKING_STAFF' AND p.code IN (
      'dashboard:read', 'orders:read', 'packing:read', 'packing:write'
    ))
    OR (r.code = 'PROCUREMENT_MANAGER' AND p.code IN (
      'dashboard:read', 'purchase:read', 'purchase:write', 'inventory:read', 'inventory:write',
      'products:read'
    ))
    OR (r.code = 'DELIVERY_MANAGER' AND p.code IN (
      'dashboard:read', 'delivery:read', 'delivery:write', 'orders:read', 'routes:read'
    ))
    OR (r.code = 'ACCOUNTANT' AND p.code IN (
      'dashboard:read', 'payments:read', 'payments:write', 'reports:read', 'reports:export'
    ))
  )
ON CONFLICT DO NOTHING;

INSERT INTO admin_user_roles (admin_user_id, role_id)
SELECT a.id, r.id
FROM admin_users a
JOIN roles r ON r.code = 'SUPER_ADMIN'
WHERE LOWER(a.email) = 'admin@freshmandi.local'
ON CONFLICT DO NOTHING;

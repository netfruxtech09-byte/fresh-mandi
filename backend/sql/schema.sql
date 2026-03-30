CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  phone VARCHAR(15) UNIQUE NOT NULL,
  name VARCHAR(120),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS otp_codes (
  phone VARCHAR(15) PRIMARY KEY,
  code VARCHAR(6) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS addresses (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label VARCHAR(50) NOT NULL,
  line1 TEXT NOT NULL,
  city VARCHAR(100) NOT NULL,
  state VARCHAR(100) NOT NULL,
  pincode VARCHAR(10) NOT NULL,
  sector_id INT REFERENCES sectors(id),
  building_id INT REFERENCES buildings(id),
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customers (
  id SERIAL PRIMARY KEY,
  user_id INT UNIQUE REFERENCES users(id) ON DELETE SET NULL,
  full_name VARCHAR(120) NOT NULL,
  phone VARCHAR(15) NOT NULL UNIQUE,
  sector_id INT,
  building_id INT,
  credit_points INT NOT NULL DEFAULT 0,
  blocked BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT
);

CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  type VARCHAR(40) NOT NULL,
  sort_order INT NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  category_id INT NOT NULL REFERENCES categories(id),
  name VARCHAR(150) NOT NULL,
  subcategory VARCHAR(50),
  unit VARCHAR(50) NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  image_url TEXT,
  in_stock BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cart_items (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id INT NOT NULL REFERENCES products(id),
  quantity INT NOT NULL CHECK(quantity > 0),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, product_id)
);

CREATE TABLE IF NOT EXISTS delivery_slots (
  id SERIAL PRIMARY KEY,
  label VARCHAR(80) NOT NULL,
  starts_at TIME NOT NULL,
  ends_at TIME NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS coupons (
  id SERIAL PRIMARY KEY,
  code VARCHAR(40) UNIQUE NOT NULL,
  flat_discount NUMERIC(10,2) NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at TIMESTAMP NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id),
  address_id INT NOT NULL REFERENCES addresses(id),
  slot_id INT NOT NULL REFERENCES delivery_slots(id),
  payment_mode VARCHAR(20) NOT NULL,
  status VARCHAR(20) NOT NULL,
  subtotal NUMERIC(10,2) NOT NULL,
  discount NUMERIC(10,2) NOT NULL DEFAULT 0,
  gst NUMERIC(10,2) NOT NULL DEFAULT 0,
  wallet_redeem NUMERIC(10,2) NOT NULL DEFAULT 0,
  total NUMERIC(10,2) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payments (
  id SERIAL PRIMARY KEY,
  order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(20) NOT NULL,
  reference VARCHAR(80) UNIQUE NOT NULL,
  amount NUMERIC(10,2) NOT NULL,
  status VARCHAR(20) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
  id SERIAL PRIMARY KEY,
  order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id INT NOT NULL REFERENCES products(id),
  quantity INT NOT NULL,
  unit_price NUMERIC(10,2) NOT NULL
);

CREATE TABLE IF NOT EXISTS wallet_transactions (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL,
  type VARCHAR(20) NOT NULL,
  reason TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_devices (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, fcm_token)
);

CREATE TABLE IF NOT EXISTS notifications (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title VARCHAR(120) NOT NULL,
  body TEXT NOT NULL,
  kind VARCHAR(40) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS app_settings (
  key VARCHAR(80) PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS admin_users (
  id SERIAL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  email VARCHAR(160) UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

DO $$
BEGIN
  CREATE TYPE role_code AS ENUM (
    'SUPER_ADMIN',
    'OPERATIONS_MANAGER',
    'PACKING_STAFF',
    'PROCUREMENT_MANAGER',
    'DELIVERY_MANAGER',
    'ACCOUNTANT'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE order_flow_status AS ENUM (
    'PLACED',
    'PRINTED',
    'PACKED',
    'OUT_FOR_DELIVERY',
    'DELIVERED',
    'CANCELLED'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE delivery_status AS ENUM (
    'DELIVERED',
    'NOT_AVAILABLE',
    'RESCHEDULED',
    'CANCELLED'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  CREATE TYPE payment_status AS ENUM (
    'PENDING',
    'PAID',
    'FAILED',
    'REFUNDED'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS roles (
  id SERIAL PRIMARY KEY,
  code role_code NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  description TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

CREATE TABLE IF NOT EXISTS permissions (
  id SERIAL PRIMARY KEY,
  code VARCHAR(80) NOT NULL UNIQUE,
  module VARCHAR(60) NOT NULL,
  action VARCHAR(60) NOT NULL,
  description TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

CREATE TABLE IF NOT EXISTS role_permissions (
  role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id INT NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  created_by INT REFERENCES admin_users(id),
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS admin_user_roles (
  admin_user_id INT NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
  role_id INT NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  created_by INT REFERENCES admin_users(id),
  PRIMARY KEY (admin_user_id, role_id)
);

CREATE TABLE IF NOT EXISTS sectors (
  id SERIAL PRIMARY KEY,
  code VARCHAR(30) NOT NULL UNIQUE,
  name VARCHAR(120) NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

CREATE TABLE IF NOT EXISTS buildings (
  id SERIAL PRIMARY KEY,
  sector_id INT NOT NULL REFERENCES sectors(id),
  name VARCHAR(120) NOT NULL,
  code VARCHAR(40) NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id),
  UNIQUE (sector_id, code)
);

CREATE TABLE IF NOT EXISTS routes (
  id SERIAL PRIMARY KEY,
  route_code VARCHAR(40) NOT NULL UNIQUE,
  sector_id INT NOT NULL REFERENCES sectors(id),
  max_orders INT NOT NULL DEFAULT 120,
  sequence_logic VARCHAR(80) NOT NULL DEFAULT 'tower_then_flat',
  optimized BOOLEAN NOT NULL DEFAULT FALSE,
  total_orders INT NOT NULL DEFAULT 0,
  total_distance_km NUMERIC(10,2) NOT NULL DEFAULT 0,
  estimated_time_minutes INT NOT NULL DEFAULT 0,
  generated_at TIMESTAMP,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

ALTER TABLE routes ADD COLUMN IF NOT EXISTS optimized BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS total_orders INT NOT NULL DEFAULT 0;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS total_distance_km NUMERIC(10,2) NOT NULL DEFAULT 0;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS estimated_time_minutes INT NOT NULL DEFAULT 0;
ALTER TABLE routes ADD COLUMN IF NOT EXISTS generated_at TIMESTAMP;

CREATE TABLE IF NOT EXISTS route_buildings (
  route_id INT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
  building_id INT NOT NULL REFERENCES buildings(id) ON DELETE CASCADE,
  stop_sequence INT NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  created_by INT REFERENCES admin_users(id),
  PRIMARY KEY (route_id, building_id)
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'customers_sector_id_fkey'
  ) THEN
    ALTER TABLE customers
    ADD CONSTRAINT customers_sector_id_fkey
    FOREIGN KEY (sector_id) REFERENCES sectors(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'customers_building_id_fkey'
  ) THEN
    ALTER TABLE customers
    ADD CONSTRAINT customers_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES buildings(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'customers_updated_by_fkey'
  ) THEN
    ALTER TABLE customers
    ADD CONSTRAINT customers_updated_by_fkey
    FOREIGN KEY (updated_by) REFERENCES admin_users(id);
  END IF;
END $$;

ALTER TABLE users ADD COLUMN IF NOT EXISTS updated_by INT REFERENCES admin_users(id);
ALTER TABLE products ADD COLUMN IF NOT EXISTS updated_by INT REFERENCES admin_users(id);
ALTER TABLE payments ADD COLUMN IF NOT EXISTS updated_by INT REFERENCES admin_users(id);
ALTER TABLE addresses ADD COLUMN IF NOT EXISTS sector_id INT REFERENCES sectors(id);
ALTER TABLE addresses ADD COLUMN IF NOT EXISTS building_id INT REFERENCES buildings(id);

ALTER TABLE orders ADD COLUMN IF NOT EXISTS sector_id INT REFERENCES sectors(id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS building_id INT REFERENCES buildings(id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS route_id INT REFERENCES routes(id);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS route_sequence INT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_ref VARCHAR(50);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS printed_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS packed_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS print_status order_flow_status NOT NULL DEFAULT 'PLACED';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS packing_status order_flow_status NOT NULL DEFAULT 'PLACED';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_status order_flow_status NOT NULL DEFAULT 'PLACED';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_status payment_status NOT NULL DEFAULT 'PENDING';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP NOT NULL DEFAULT NOW();
ALTER TABLE orders ADD COLUMN IF NOT EXISTS updated_by INT REFERENCES admin_users(id);

CREATE TABLE IF NOT EXISTS purchase_summary (
  id SERIAL PRIMARY KEY,
  business_date DATE NOT NULL,
  product_id INT NOT NULL REFERENCES products(id),
  required_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  wastage_pct NUMERIC(5,2) NOT NULL DEFAULT 0,
  final_purchase_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  supplier_name VARCHAR(120),
  purchase_cost NUMERIC(12,2),
  purchase_date DATE,
  invoice_url TEXT,
  purchased BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id),
  UNIQUE (business_date, product_id)
);

CREATE TABLE IF NOT EXISTS inventory (
  id SERIAL PRIMARY KEY,
  product_id INT NOT NULL REFERENCES products(id),
  warehouse_code VARCHAR(40) NOT NULL DEFAULT 'WH-01',
  opening_stock NUMERIC(12,3) NOT NULL DEFAULT 0,
  purchased_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  allocated_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  damaged_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  wastage_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  remaining_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  low_stock_threshold NUMERIC(12,3) NOT NULL DEFAULT 0,
  quality_check_approved BOOLEAN NOT NULL DEFAULT FALSE,
  stock_date DATE NOT NULL DEFAULT CURRENT_DATE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id),
  UNIQUE (product_id, warehouse_code, stock_date)
);

CREATE TABLE IF NOT EXISTS packing_log (
  id SERIAL PRIMARY KEY,
  order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  route_id INT REFERENCES routes(id),
  crate_number VARCHAR(40),
  barcode_value VARCHAR(120),
  packed_by INT REFERENCES admin_users(id),
  packed_at TIMESTAMP NOT NULL DEFAULT NOW(),
  status order_flow_status NOT NULL DEFAULT 'PACKED',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

CREATE TABLE IF NOT EXISTS delivery_log (
  id SERIAL PRIMARY KEY,
  order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  route_id INT REFERENCES routes(id),
  delivery_staff_id INT REFERENCES admin_users(id),
  crate_number VARCHAR(40),
  route_start_at TIMESTAMP,
  route_end_at TIMESTAMP,
  status delivery_status NOT NULL,
  payment_mode VARCHAR(30),
  payment_status payment_status NOT NULL DEFAULT 'PENDING',
  notes TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

CREATE TABLE IF NOT EXISTS reports (
  id SERIAL PRIMARY KEY,
  report_type VARCHAR(60) NOT NULL,
  business_date DATE NOT NULL,
  storage_url TEXT,
  generated_by INT REFERENCES admin_users(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id),
  UNIQUE (report_type, business_date)
);

DO $$
BEGIN
  CREATE TYPE delivery_route_status AS ENUM (
    'ASSIGNED',
    'IN_PROGRESS',
    'COMPLETED',
    'SETTLEMENT_DONE'
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS delivery_executives (
  id SERIAL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(15) NOT NULL UNIQUE,
  employee_code VARCHAR(40) UNIQUE,
  device_id VARCHAR(160),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

CREATE TABLE IF NOT EXISTS processing_staff (
  id SERIAL PRIMARY KEY,
  name VARCHAR(120) NOT NULL,
  phone VARCHAR(15) NOT NULL UNIQUE,
  employee_code VARCHAR(40) UNIQUE,
  role_code VARCHAR(40) NOT NULL DEFAULT 'STORE_MANAGER',
  device_id VARCHAR(160),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  last_login_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id)
);

ALTER TABLE processing_staff ADD COLUMN IF NOT EXISTS role_code VARCHAR(40) NOT NULL DEFAULT 'STORE_MANAGER';

CREATE TABLE IF NOT EXISTS processing_order_locks (
  order_id INT PRIMARY KEY REFERENCES orders(id) ON DELETE CASCADE,
  processing_staff_id INT NOT NULL REFERENCES processing_staff(id),
  locked_until TIMESTAMP NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS route_crates (
  id SERIAL PRIMARY KEY,
  route_id INT NOT NULL REFERENCES routes(id) ON DELETE CASCADE,
  crate_code VARCHAR(20) NOT NULL,
  stop_from INT NOT NULL,
  stop_to INT NOT NULL,
  max_capacity INT NOT NULL DEFAULT 15,
  current_orders INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (route_id, crate_code)
);

CREATE TABLE IF NOT EXISTS order_allocations (
  id SERIAL PRIMARY KEY,
  business_date DATE NOT NULL DEFAULT CURRENT_DATE,
  order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  route_id INT REFERENCES routes(id),
  product_id INT NOT NULL REFERENCES products(id),
  required_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  reserved_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  used_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  shortage_qty NUMERIC(12,3) NOT NULL DEFAULT 0,
  status VARCHAR(20) NOT NULL DEFAULT 'RESERVED',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (business_date, order_id, product_id)
);

CREATE TABLE IF NOT EXISTS inventory_alerts (
  id SERIAL PRIMARY KEY,
  business_date DATE NOT NULL DEFAULT CURRENT_DATE,
  product_id INT REFERENCES products(id),
  route_id INT REFERENCES routes(id),
  alert_type VARCHAR(40) NOT NULL,
  severity VARCHAR(20) NOT NULL DEFAULT 'HIGH',
  message TEXT NOT NULL,
  acknowledged BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS print_logs (
  id SERIAL PRIMARY KEY,
  business_date DATE NOT NULL DEFAULT CURRENT_DATE,
  route_id INT REFERENCES routes(id),
  order_id INT REFERENCES orders(id) ON DELETE CASCADE,
  action_type VARCHAR(20) NOT NULL DEFAULT 'PRINT',
  reason TEXT,
  printed_by_processing_staff_id INT REFERENCES processing_staff(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS staff_activity (
  id SERIAL PRIMARY KEY,
  processing_staff_id INT REFERENCES processing_staff(id),
  activity_type VARCHAR(40) NOT NULL,
  order_id INT REFERENCES orders(id) ON DELETE SET NULL,
  route_id INT REFERENCES routes(id) ON DELETE SET NULL,
  details JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS goods_received (
  id SERIAL PRIMARY KEY,
  supplier_name VARCHAR(160) NOT NULL,
  invoice_number VARCHAR(80) NOT NULL,
  image_url TEXT,
  total_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  status VARCHAR(30) NOT NULL DEFAULT 'AWAITING_QUALITY_CHECK',
  received_at TIMESTAMP NOT NULL DEFAULT NOW(),
  received_by_processing_staff_id INT REFERENCES processing_staff(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  UNIQUE (invoice_number)
);

CREATE TABLE IF NOT EXISTS goods_received_items (
  id SERIAL PRIMARY KEY,
  goods_received_id INT NOT NULL REFERENCES goods_received(id) ON DELETE CASCADE,
  product_id INT NOT NULL REFERENCES products(id),
  quantity_received NUMERIC(12,3) NOT NULL DEFAULT 0,
  rate_per_kg NUMERIC(12,2) NOT NULL DEFAULT 0,
  total_cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  quality_status VARCHAR(30) NOT NULL DEFAULT 'AWAITING_QUALITY_CHECK',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS quality_checks (
  id SERIAL PRIMARY KEY,
  goods_received_item_id INT NOT NULL REFERENCES goods_received_items(id) ON DELETE CASCADE,
  product_id INT NOT NULL REFERENCES products(id),
  good_quantity NUMERIC(12,3) NOT NULL DEFAULT 0,
  damaged_quantity NUMERIC(12,3) NOT NULL DEFAULT 0,
  waste_quantity NUMERIC(12,3) NOT NULL DEFAULT 0,
  damage_reason TEXT,
  approved_at TIMESTAMP NOT NULL DEFAULT NOW(),
  approved_by_processing_staff_id INT REFERENCES processing_staff(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS delivery_route_assignments (
  id SERIAL PRIMARY KEY,
  business_date DATE NOT NULL,
  route_id INT NOT NULL REFERENCES routes(id),
  delivery_executive_id INT NOT NULL REFERENCES delivery_executives(id),
  status delivery_route_status NOT NULL DEFAULT 'ASSIGNED',
  route_start_time TIMESTAMP,
  route_end_time TIMESTAMP,
  cash_handover_confirmed_at TIMESTAMP,
  cash_handover_amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  cash_handover_notes TEXT,
  assigned_by INT REFERENCES admin_users(id),
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_by INT REFERENCES admin_users(id),
  UNIQUE (business_date, route_id),
  UNIQUE (business_date, delivery_executive_id)
);

ALTER TABLE delivery_route_assignments ADD COLUMN IF NOT EXISTS cash_handover_confirmed_at TIMESTAMP;
ALTER TABLE delivery_route_assignments ADD COLUMN IF NOT EXISTS cash_handover_amount NUMERIC(12,2) NOT NULL DEFAULT 0;
ALTER TABLE delivery_route_assignments ADD COLUMN IF NOT EXISTS cash_handover_notes TEXT;

ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivered_by INT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS failure_reason TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_collected_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS floor_number INT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS flat_number VARCHAR(20);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS latitude NUMERIC(10,7);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS longitude NUMERIC(10,7);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS stop_number INT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS crate_number VARCHAR(40);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS packed_by INT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_scan_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_scan_verified_at TIMESTAMP;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_scan_verified_by INT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_scan_code VARCHAR(120);
ALTER TABLE delivery_log ADD COLUMN IF NOT EXISTS business_date DATE NOT NULL DEFAULT CURRENT_DATE;
ALTER TABLE packing_log ADD COLUMN IF NOT EXISTS processing_staff_id INT REFERENCES processing_staff(id);
UPDATE delivery_log
SET business_date = DATE(created_at)
WHERE business_date IS DISTINCT FROM DATE(created_at);

WITH dedupe AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY order_id, business_date
           ORDER BY updated_at DESC, id DESC
         ) AS rn
  FROM delivery_log
)
DELETE FROM delivery_log d
USING dedupe x
WHERE d.id = x.id
  AND x.rn > 1;

CREATE INDEX IF NOT EXISTS idx_orders_created_at
  ON orders (created_at);

CREATE INDEX IF NOT EXISTS idx_orders_route_created_at
  ON orders (route_id, created_at);

CREATE INDEX IF NOT EXISTS idx_orders_sector_created_at
  ON orders (sector_id, created_at);

CREATE INDEX IF NOT EXISTS idx_orders_building_created_at
  ON orders (building_id, created_at);

CREATE INDEX IF NOT EXISTS idx_orders_route_stop
  ON orders (route_id, stop_number);

CREATE INDEX IF NOT EXISTS idx_route_crates_route_id
  ON route_crates (route_id);

CREATE INDEX IF NOT EXISTS idx_processing_order_locks_order_locked_until
  ON processing_order_locks (order_id, locked_until);

CREATE INDEX IF NOT EXISTS idx_order_allocations_business_order
  ON order_allocations (business_date, order_id);

CREATE INDEX IF NOT EXISTS idx_order_allocations_product_business
  ON order_allocations (product_id, business_date);

CREATE INDEX IF NOT EXISTS idx_inventory_stock_date_product
  ON inventory (stock_date, product_id);

CREATE INDEX IF NOT EXISTS idx_packing_log_order_packed_at
  ON packing_log (order_id, packed_at DESC);

CREATE INDEX IF NOT EXISTS idx_route_buildings_route_sequence
  ON route_buildings (route_id, stop_sequence);

CREATE INDEX IF NOT EXISTS idx_orders_route_created_date
  ON orders (route_id, (DATE(created_at)));

CREATE INDEX IF NOT EXISTS idx_orders_route_status_created_at
  ON orders (route_id, delivery_status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_route_failure_created_at
  ON orders (route_id, failure_reason, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_orders_route_stop_created_at
  ON orders (route_id, stop_number, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_assignments_exec_date
  ON delivery_route_assignments (delivery_executive_id, business_date);

CREATE INDEX IF NOT EXISTS idx_delivery_assignments_route_date_exec
  ON delivery_route_assignments (route_id, business_date, delivery_executive_id);

CREATE INDEX IF NOT EXISTS idx_delivery_assignments_date_status
  ON delivery_route_assignments (business_date, status);

CREATE INDEX IF NOT EXISTS idx_delivery_log_order_created_at
  ON delivery_log (order_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_delivery_log_order_created_date
  ON delivery_log (order_id, (DATE(created_at)));

CREATE UNIQUE INDEX IF NOT EXISTS idx_delivery_log_order_business_date
  ON delivery_log (order_id, business_date);

CREATE INDEX IF NOT EXISTS idx_processing_locks_staff_until
  ON processing_order_locks (processing_staff_id, locked_until);

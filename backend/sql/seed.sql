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
  ('gst_percent', '5')
ON CONFLICT (key) DO NOTHING;

INSERT INTO admin_users (name, email, password_hash, active)
VALUES (
  'Fresh Mandi Admin',
  'admin@freshmandi.local',
  '$2a$10$BIyqY0ZCnu7Lk9AG8Ys8jOgSfNHdFDjBCIQZSeVBzkd/uVHjsY43i',
  true
)
ON CONFLICT (email) DO NOTHING;

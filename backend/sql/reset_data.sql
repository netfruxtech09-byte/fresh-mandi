TRUNCATE TABLE
  payments,
  order_items,
  orders,
  cart_items,
  wallet_transactions,
  notifications,
  user_devices,
  products,
  categories,
  delivery_slots,
  coupons,
  app_settings,
  addresses,
  otp_codes,
  users
RESTART IDENTITY CASCADE;

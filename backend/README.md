# Fresh Mandi Backend

## Stack
- Node.js + Express
- PostgreSQL
- JWT auth

## Run
```bash
cp .env.example .env
npm install
npm run db:init
npm run db:up
npm run migrate
npm run seed
npm run dev
```

To delete all data but keep schema/tables:
```bash
npm run db:reset-data
npm run seed
```

If you already have PostgreSQL installed locally, ensure it is running on `localhost:5432`
or update `DATABASE_URL` in `.env`.

## Core Features
- OTP authentication
- User profile + address CRUD
- Product catalog and filters
- Cart + suggestions
- Checkout with coupon, GST, wallet redemption
- UPI/COD payment flow with payment intent + confirmation routes
- Delivery slots + cutoff validation
- Order history, details, reorder
- FCM token storage + notifications feed
- Admin settings (cutoff/menu controls) + nightly reminder trigger endpoint

## Admin Panel
- Web URL: `http://localhost:4000/admin`
- Default admin login (from seed):
  - email: `admin@freshmandi.local`
  - password: `Admin@123`
  - Change this immediately for production.

### Admin Capabilities
- Secure admin login (JWT)
- Dashboard totals + 7-day order/revenue graph
- Product CRUD (name, category, subcategory, unit, price, image URL, stock)
- Order listing and status updates (`PENDING_PAYMENT`, `CONFIRMED`, `PACKED`, `OUT_FOR_DELIVERY`, `DELIVERED`, `CANCELLED`)
- App settings update (`cutoff_hour`, `gst_percent`)
- Manual trigger for nightly reminder job

### Product Image Storage (Cloudinary)
For production, configure Cloudinary so uploaded images are durable:

- `CLOUDINARY_CLOUD_NAME`
- `CLOUDINARY_API_KEY`
- `CLOUDINARY_API_SECRET`
- Optional: `CLOUDINARY_FOLDER` (default: `freshmandi/products`)

If Cloudinary vars are not set:
- local/dev: backend falls back to local disk upload
- production/serverless: upload API fails fast with a config error (no local fallback)

This prevents non-durable image uploads in production.

### Admin API Endpoints
- `POST /api/v1/admin/auth/login`
- `GET /api/v1/admin/me`
- `GET /api/v1/admin/dashboard`
- `GET /api/v1/admin/products`
- `POST /api/v1/admin/products`
- `PUT /api/v1/admin/products/:id`
- `DELETE /api/v1/admin/products/:id`
- `GET /api/v1/admin/orders`
- `GET /api/v1/admin/orders/:id`
- `PATCH /api/v1/admin/orders/:id/status`
- `GET /api/v1/admin/settings`
- `PUT /api/v1/admin/settings`
- `POST /api/v1/admin/jobs/night-reminder`

## OTP SMS
- Dev mode (default): `OTP_BYPASS=true` returns OTP in API response.
- Real SMS mode: set `OTP_BYPASS=false`.
- Optional dev safety: `OTP_FALLBACK_ON_SMS_FAILURE=true` returns OTP if SMS provider fails.
- Free provider included: `textbelt` (`SMS_PROVIDER=textbelt`, `SMS_TEXTBELT_KEY=textbelt`).
  - Textbelt free key is rate-limited (typically very low daily quota).
  - For production India traffic, replace with MSG91/Twilio/AWS SNS credentials.

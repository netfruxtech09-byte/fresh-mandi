# Deployment Instructions

## Vercel (Backend + Admin in one deployment)
Admin panel is served from the same backend at `/admin`.

1. Install and login to Vercel (on your machine):
```bash
npm i -g vercel
vercel login
```

2. Deploy backend folder:
```bash
cd backend
vercel --prod
```

3. In Vercel project settings, add environment variables from `backend/.env.example`:
- `DATABASE_URL` (use a managed Postgres URL)
- `JWT_SECRET`
- `OTP_BYPASS`
- `OTP_BYPASS_CODE`
- `OTP_FALLBACK_ON_SMS_FAILURE`
- `SMS_PROVIDER`
- `SMS_TEXTBELT_KEY`
- `CUT_OFF_HOUR`
- `GST_PERCENT`
- `PAYMENT_BYPASS`

4. Verify URLs:
- API health: `https://<your-backend-domain>/health`
- Admin panel: `https://<your-backend-domain>/admin`

5. Set Flutter API URL:
```bash
cd app
flutter run --dart-define=API_BASE_URL=https://<your-backend-domain>/api/v1
```
For release builds, use the same `--dart-define`.

## Backend (Render / Railway / ECS)
1. Provision PostgreSQL and set `DATABASE_URL`.
2. Set env vars from `backend/.env.example`.
3. Add payment provider secrets (`RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` or Stripe secrets).
4. Run:
```bash
cd backend
npm ci
npm run migrate
npm run seed
npm start
```
5. Expose port `4000` (or env `PORT`).

## Flutter App
1. Configure `--dart-define=API_BASE_URL=https://<api-domain>/api/v1`.
2. Android release:
```bash
cd app
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.example.com/api/v1
```
3. iOS release:
```bash
flutter build ipa --release --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

## Push Notifications
- Configure Firebase project for Android + iOS.
- Upload APNS key and Android SHA certificates.
- Use `/notifications/fcm-token` endpoint to map user devices.
- Trigger reminders via `POST /api/v1/admin/jobs/night-reminder` from a nightly scheduler (cron/worker).

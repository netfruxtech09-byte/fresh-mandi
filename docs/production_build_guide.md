# Production Build Guide

## Checklist
- Replace mock payment intent secrets with live Razorpay/Stripe server SDK credentials.
- Add rate limiting on auth endpoints.
- Add Redis for OTP and session throttling.
- Add TLS termination and WAF.
- Add observability: Sentry + structured logs.
- Configure app signing, bundle identifiers, and store metadata.

## Flutter hardening
- Enable obfuscation/split debug info for release.
- Add crash reporting and analytics.
- Add golden tests and integration tests for checkout flow.
- Add `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist` for Firebase.
- Configure APNS (iOS) and notification channels (Android).

## Backend hardening
- Add request id + audit logs.
- Add idempotency keys for payment webhook handling.
- Add migrations with versioning tool (Prisma/Knex/Flyway).
- Add webhook signature verification for Razorpay/Stripe callbacks.

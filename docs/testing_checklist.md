# Testing Checklist

## Unit Tests
- Auth repository: request OTP/verify OTP success and failure.
- Cart provider: add/update/remove quantity.
- Price calc: subtotal + GST + coupon + wallet redemption.
- Cutoff logic at 8:59 PM vs 9:00 PM.

## Integration Tests
- Login -> OTP -> address -> browse -> cart -> checkout -> confirmation.
- Coupon validation with expired and active coupons.
- Reorder flow from order history.
- Wallet credit earn/redeem across two orders.
- Notification registration and fetch.

## API Tests
- JWT-protected endpoints reject invalid/missing token.
- Address CRUD scoped by user.
- Order creation fails when cart empty.
- Order creation blocked after cutoff.

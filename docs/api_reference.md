# API Reference (Summary)

Base URL: `https://backend-rho-one-36.vercel.app/api/v1`

## Auth
- `POST /auth/otp/request`
- `POST /auth/otp/verify`

## Profile
- `GET /users/me`
- `PATCH /users/me`

## Address
- `GET /addresses`
- `POST /addresses`
- `PUT /addresses/:id`
- `DELETE /addresses/:id`

## Catalog
- `GET /catalog/categories`
- `GET /catalog/products?categoryId=1&subcategory=Seasonal&q=apple`

## Cart
- `GET /cart`
- `POST /cart/items`
- `DELETE /cart/items/:productId`
- `GET /cart/suggestions`

## Order
- `POST /orders`
- `GET /orders`
- `GET /orders/:id`
- `POST /orders/:id/reorder`

## Wallet/Coupons/Slots
- `GET /wallet`
- `GET /coupons/validate/:code`
- `GET /slots`

## Notifications
- `POST /notifications/fcm-token`
- `GET /notifications`

## Admin
- `GET /admin/settings`
- `PUT /admin/settings`
- `POST /admin/jobs/night-reminder`

## Payments
- `POST /payments/create-intent`
- `POST /payments/confirm`

import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import path from 'path';
import { fileURLToPath } from 'url';

import { authRouter } from './modules/auth/routes.js';
import { userRouter } from './modules/user/routes.js';
import { addressRouter } from './modules/address/routes.js';
import { catalogRouter } from './modules/catalog/routes.js';
import { cartRouter } from './modules/cart/routes.js';
import { orderRouter } from './modules/order/routes.js';
import { walletRouter } from './modules/wallet/routes.js';
import { couponRouter } from './modules/coupon/routes.js';
import { slotRouter } from './modules/slot/routes.js';
import { notificationRouter } from './modules/notification/routes.js';
import { adminRouter } from './modules/admin/routes.js';
import { paymentRouter } from './modules/payment/routes.js';
import { deliveryRouter } from './modules/delivery/routes.js';
import { processingRouter } from './modules/processing/routes.js';
import { getUploadsDir } from './utils/uploads.js';

const app = express();
const __dirname = path.dirname(fileURLToPath(import.meta.url));

app.set('etag', false);
app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        baseUri: ["'self'"],
        objectSrc: ["'none'"],
        frameAncestors: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", 'data:', 'blob:', 'https://res.cloudinary.com', 'https://*.cloudinary.com'],
        connectSrc: ["'self'"],
        fontSrc: ["'self'", 'data:'],
        upgradeInsecureRequests: [],
      },
    },
  }),
);
app.use(cors());
app.use(express.json({ limit: '10mb' }));

app.use('/admin', express.static(path.resolve(__dirname, '../public/admin')));
app.use('/uploads', express.static(getUploadsDir(__dirname)));

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

app.use('/api/v1/auth', authRouter);
app.use('/api/v1/users', userRouter);
app.use('/api/v1/addresses', addressRouter);
app.use('/api/v1/catalog', catalogRouter);
app.use('/api/v1/cart', cartRouter);
app.use('/api/v1/orders', orderRouter);
app.use('/api/v1/wallet', walletRouter);
app.use('/api/v1/coupons', couponRouter);
app.use('/api/v1/slots', slotRouter);
app.use('/api/v1/notifications', notificationRouter);
app.use('/api/v1/admin', adminRouter);
app.use('/api/v1/payments', paymentRouter);
app.use('/api/v1/delivery', deliveryRouter);
app.use('/api/v1/processing', processingRouter);

export default app;

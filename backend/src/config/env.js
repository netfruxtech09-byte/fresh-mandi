import dotenv from 'dotenv';

dotenv.config();

export const env = {
  port: Number(process.env.PORT ?? 4000),
  databaseUrl: process.env.DATABASE_URL ?? process.env.POSTGRES_URL ?? '',
  jwtSecret: process.env.JWT_SECRET ?? 'dev_secret',
  otpBypass: `${process.env.OTP_BYPASS}` === 'true',
  otpBypassCode: process.env.OTP_BYPASS_CODE ?? '123456',
  smsProvider: process.env.SMS_PROVIDER ?? 'textbelt',
  smsTextbeltKey: process.env.SMS_TEXTBELT_KEY ?? 'textbelt',
  otpFallbackOnSmsFailure: `${process.env.OTP_FALLBACK_ON_SMS_FAILURE}` === 'true',
  cutOffHour: Number(process.env.CUT_OFF_HOUR ?? 21),
  deliveryWindowStartHour: Number(process.env.DELIVERY_WINDOW_START_HOUR ?? 6),
  deliveryWindowEndHour: Number(process.env.DELIVERY_WINDOW_END_HOUR ?? 10),
  processingCrateCapacity: Number(process.env.PROCESSING_CRATE_CAPACITY ?? 15),
  googleMapsApiKey: process.env.GOOGLE_MAPS_API_KEY ?? '',
  googleRouteOptimizationUrl:
    process.env.GOOGLE_ROUTE_OPTIMIZATION_URL ??
    'https://routes.googleapis.com/directions/v2:computeRoutes',
  gstPercent: Number(process.env.GST_PERCENT ?? 5),
  paymentBypass: `${process.env.PAYMENT_BYPASS}` === 'true',
  cloudinaryCloudName: process.env.CLOUDINARY_CLOUD_NAME ?? '',
  cloudinaryApiKey: process.env.CLOUDINARY_API_KEY ?? '',
  cloudinaryApiSecret: process.env.CLOUDINARY_API_SECRET ?? '',
  cloudinaryFolder: process.env.CLOUDINARY_FOLDER ?? 'freshmandi/products',
};

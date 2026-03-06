import crypto from 'crypto';

import { env } from '../config/env.js';

export function isCloudinaryConfigured() {
  return Boolean(env.cloudinaryCloudName && env.cloudinaryApiKey && env.cloudinaryApiSecret);
}

export async function uploadImageToCloudinary({ buffer, mimeType, filename }) {
  const timestamp = Math.floor(Date.now() / 1000);
  const paramsToSign = {
    folder: env.cloudinaryFolder,
    timestamp,
  };

  const signaturePayload = Object.entries(paramsToSign)
    .filter(([, value]) => value !== undefined && value !== null && `${value}`.length > 0)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join('&');

  const signature = crypto
    .createHash('sha1')
    .update(`${signaturePayload}${env.cloudinaryApiSecret}`)
    .digest('hex');

  const form = new FormData();
  form.append('file', new Blob([buffer], { type: mimeType }), filename);
  form.append('api_key', env.cloudinaryApiKey);
  form.append('timestamp', `${timestamp}`);
  form.append('signature', signature);
  if (env.cloudinaryFolder) {
    form.append('folder', env.cloudinaryFolder);
  }

  const response = await fetch(`https://api.cloudinary.com/v1_1/${env.cloudinaryCloudName}/image/upload`, {
    method: 'POST',
    body: form,
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const reason = payload?.error?.message || payload?.message || 'Unknown Cloudinary error';
    throw new Error(`Cloudinary upload failed: ${reason}`);
  }

  const url = payload?.secure_url || payload?.url;
  if (!url) {
    throw new Error('Cloudinary upload failed: missing URL in response');
  }

  return {
    url,
    publicId: payload?.public_id ?? null,
  };
}

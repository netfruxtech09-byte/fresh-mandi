import { env } from '../config/env.js';

function normalizeIndianPhone(phone) {
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10 && /^[6-9]\d{9}$/.test(digits)) {
    return `+91${digits}`;
  }
  if (digits.length === 12 && digits.startsWith('91') && /^[6-9]\d{9}$/.test(digits.slice(2))) {
    return `+${digits}`;
  }
  return null;
}

async function sendViaTextbelt({ to, message }) {
  const response = await fetch('https://textbelt.com/text', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      phone: to,
      message,
      key: env.smsTextbeltKey,
    }),
  });

  const data = await response.json();
  if (!data.success) {
    throw new Error(data.error || 'SMS send failed');
  }
}

export async function sendOtpSms(rawPhone, otp) {
  const phone = normalizeIndianPhone(rawPhone);
  if (!phone) {
    throw new Error('Invalid Indian phone number format');
  }

  const message = `Fresh Mandi OTP: ${otp}. Valid for 10 minutes.`;

  if (env.smsProvider === 'textbelt') {
    await sendViaTextbelt({ to: phone, message });
    return { phone };
  }

  throw new Error('Unsupported SMS provider');
}

export { normalizeIndianPhone };

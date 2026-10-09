export const normalizeEmail = (value) => String(value ?? '').trim().toLowerCase();
export const isEmail = (value) => typeof value === 'string' && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
export const validPassword = (value) => typeof value === 'string' && value.length >= 10 && value.length <= 200;

export function normalizePhone(value) {
  let phone = String(value ?? '').trim().replace(/[۰-۹٠-٩]/g, (digit) => {
    const code = digit.charCodeAt(0);
    return String(code >= 0x6f0 ? code - 0x6f0 : code - 0x660);
  }).replace(/[\s()-]/g, '');
  if (/^09\d{9}$/.test(phone)) phone = '+98' + phone.slice(1);
  if (/^0098\d{10}$/.test(phone)) phone = '+' + phone.slice(2);
  return /^\+[1-9]\d{7,14}$/.test(phone) ? phone : null;
}

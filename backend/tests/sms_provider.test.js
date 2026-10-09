import test from 'node:test';
import assert from 'node:assert/strict';
import { createEmailProvider, createSmsProvider, safelyDeliver } from '../src/auth_delivery.js';

const secret = 'SYNTHETIC_SMS_SECRET_MARKER_20261008';
const endpoint = 'https://sms-gateway.example.test/otp';
const env = { SMS_PROVIDER: 'webhook', SMS_PROVIDER_URL: endpoint, SMS_PROVIDER_TOKEN: secret };
const message = { phone: '+155500000001', code: '765432', expiresIn: 300, idempotencyKey: '11111111-1111-4111-8111-111111111111' };
const sensitive = `${secret} ${message.phone} ${message.code}`;
const safeError = (error, code) => {
  assert.equal(error.message, code);
  assert.equal(String(error.stack).includes(secret), false);
  assert.equal(String(error.stack).includes(message.phone), false);
  assert.equal(String(error.stack).includes(message.code), false);
  assert.equal(error.cause, undefined);
  return true;
};

test('SMS remains disabled without an explicit webhook selection and makes no outbound request', async () => {
  let calls = 0;
  for (const selection of [undefined, '', 'none', 'disabled']) {
    const provider = createSmsProvider({ env: { ...env, SMS_PROVIDER: selection }, fetchImpl: async () => { calls++; } });
    assert.equal(provider.configured, false);
    assert.equal(provider.status, 'UNVERIFIED');
    assert.equal((await provider.sendOtp(message)).delivered, false);
  }
  assert.equal(calls, 0);
});

test('explicit HTTPS webhook uses bearer authentication, minimal OTP data and an opaque idempotency key', async () => {
  const calls = [];
  const provider = createSmsProvider({ env, fetchImpl: async (url, options) => { calls.push({ url, options }); return new Response('', { status: 202 }); } });
  assert.equal(provider.configured, true);
  assert.equal(provider.status, 'CONFIGURED_UNVERIFIED');
  assert.equal(JSON.stringify(provider).includes(secret) || JSON.stringify(provider).includes(endpoint), false);
  assert.equal((await provider.sendOtp({ ...message, privateNotes: 'MUST-NOT-SEND' })).delivered, true);
  assert.equal(calls.length, 1);
  const { url, options } = calls[0];
  assert.equal(url === endpoint, true);
  assert.equal(options.method, 'POST');
  assert.equal(options.redirect, 'error');
  assert.equal(options.headers.Authorization === `Bearer ${secret}`, true);
  assert.equal(options.headers['Idempotency-Key'] === message.idempotencyKey, true);
  assert.equal(options.headers['Content-Type'], 'application/json');
  assert.ok(options.signal instanceof AbortSignal);
  const payload = JSON.parse(options.body);
  assert.deepEqual(Object.keys(payload).sort(), ['code', 'expiresIn', 'phone']);
  assert.equal(payload.phone === message.phone && payload.code === message.code && payload.expiresIn === 300, true);
});

test('unsupported or unsafe explicit SMS configuration fails clearly without echoing configuration secrets', () => {
  let calls = 0;
  const bad = [
    { SMS_PROVIDER: 'unknown' }, { SMS_PROVIDER_URL: '' }, { SMS_PROVIDER_URL: 'http://sms-gateway.example.test/otp' },
    { SMS_PROVIDER_URL: `https://user:${secret}@sms-gateway.example.test/otp` },
    { SMS_PROVIDER_URL: `https://sms-gateway.example.test/otp#${secret}` },
    { SMS_PROVIDER_URL: sensitive }, { SMS_PROVIDER_TOKEN: '' }, { SMS_PROVIDER_TOKEN: 'short' },
    { SMS_PROVIDER_TOKEN: secret + '\n' },
  ];
  for (const config of bad) assert.throws(() => createSmsProvider({ env: { ...env, ...config }, fetchImpl: async () => { calls++; } }), (error) => {
    assert.match(error.message, /^sms_provider_(unsupported|url_invalid|token_invalid)$/);
    assert.equal(String(error.stack).includes(secret), false);
    return true;
  });
  assert.equal(calls, 0);
});

test('webhook rejection exposes only a sanitized error and retries only transient response statuses', async () => {
  for (const status of [302, 400, 401, 429, 503]) {
    let bodyRead = false;
    const provider = createSmsProvider({ env, fetchImpl: async () => ({ ok: false, status, async text() { bodyRead = true; return sensitive; }, async json() { bodyRead = true; return { error: sensitive }; } }) });
    await assert.rejects(provider.sendOtp(message), (error) => {
      safeError(error, 'sms_provider_rejected');
      assert.equal(error.retryable, status === 429 || status >= 500);
      return true;
    });
    assert.equal(bodyRead, false);
  }
});

test('webhook network exceptions cannot expose provider URL, OTP or authentication material', async () => {
  const provider = createSmsProvider({ env, fetchImpl: async () => { throw new Error(sensitive); } });
  await assert.rejects(provider.sendOtp(message), (error) => {
    safeError(error, 'sms_provider_unavailable');
    assert.equal(error.retryable, false);
    return true;
  });
});

test('webhook timeout actually aborts its transport and returns a sanitized uncertain-delivery error', async () => {
  let aborted = false;
  const provider = createSmsProvider({ env, timeoutMs: 20, fetchImpl: async (_url, { signal }) => new Promise((_resolve, reject) => {
    const keepAlive = setTimeout(() => reject(new Error('Synthetic transport ignored abort')), 1000);
    signal.addEventListener('abort', () => { aborted = true; clearTimeout(keepAlive); reject(new Error(sensitive)); }, { once: true });
  }) });
  await assert.rejects(provider.sendOtp(message), (error) => {
    safeError(error, 'sms_provider_timeout');
    assert.equal(error.retryable, false);
    return true;
  });
  assert.equal(aborted, true);
});

test('webhook retries preserve one auth-delivery idempotency key and production logs contain metadata only', async () => {
  const keys = [], logs = [];
  const provider = createSmsProvider({ env, fetchImpl: async (_url, options) => {
    keys.push(options.headers['Idempotency-Key']);
    return new Response(sensitive, { status: keys.length < 3 ? 503 : 202 });
  } });
  const originalLog = console.log;
  let result;
  try {
    console.log = (line) => { logs.push(String(line)); };
    result = await safelyDeliver({ configured: provider.configured, send: (payload) => provider.sendOtp(payload) }, message, { attemptId: message.idempotencyKey, env: { NODE_ENV: 'production' } });
  } finally { console.log = originalLog; }
  assert.equal(result.delivered, true);
  assert.equal(keys.length, 3);
  assert.equal(keys.every((key) => key === message.idempotencyKey), true);
  assert.equal(logs.length, 1);
  const event = JSON.parse(logs[0]);
  assert.deepEqual(Object.keys(event).sort(), ['attemptId', 'status', 'type']);
  assert.equal(event.status, 'accepted');
  assert.equal(event.type, 'auth_delivery');
  assert.equal(logs[0].includes(secret) || logs[0].includes(message.phone) || logs[0].includes(message.code), false);
});

test('test runner disables inherited external delivery configuration for default providers', () => {
  assert.equal(createSmsProvider().configured, false);
  assert.equal(createEmailProvider().configured, false);
});

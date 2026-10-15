import test from 'node:test';
import assert from 'node:assert/strict';
import { createKavenegarSmsProvider } from '../src/kavenegar_sms.js';
import { createSmsProvider } from '../src/auth_delivery.js';

const apiKey = 'SyntheticKavenegarApiKey123456789';
const template = 'lifeguideotp';
// Fixture approval only: fetch is always injected; these are not live settings.
const env = { SMS_PROVIDER: 'kavenegar', SMS_LIVE_ENABLED: 'true', KAVENEGAR_TEMPLATE_APPROVED: 'true', KAVENEGAR_API_KEY: apiKey, KAVENEGAR_TEMPLATE: template };
const request = { phone: '+989121234567', code: '082735', expiresIn: 300,
  idempotencyKey: '11111111-2222-4333-8444-555555555555' };
const ok = () => new Response(JSON.stringify({
  return: { status: 200, message: 'Accepted' },
  entries: { messageid: 123, status: 1 },
}), { status: 200, headers: { 'content-type': 'application/json' } });
const safeError = (error, expected) => {
  assert.equal(error.message, expected);
  assert.equal(error.retryable, false);
  assert.equal(error.cause, undefined);
  for (const value of [apiKey, request.phone, request.code]) {
    assert.equal(String(error.stack).includes(value), false);
  }
  return true;
};

test('Kavenegar is opt-in and existing SMS provider selection remains intact', () => {
  const defaultProvider = createSmsProvider({ env: {} });
  assert.equal(defaultProvider.configured, false);
  assert.equal(createSmsProvider({ env: { SMS_PROVIDER: 'disabled' } }).configured, false);
  const kavenegar = createSmsProvider({ env, fetchImpl: async () => ok() });
  assert.equal(kavenegar.configured, true);
  assert.equal(kavenegar.status, 'CONFIGURED_UNVERIFIED');
  assert.equal(JSON.stringify(kavenegar).includes(apiKey), false);
  assert.equal(JSON.stringify(kavenegar).includes(template), false);
});

test('Kavenegar VerifyLookup uses fixed HTTPS host, Iranian recipient, approved template and one token', async () => {
  const calls = [];
  const provider = createKavenegarSmsProvider({ env, fetchImpl: async (url, options) => {
    calls.push({ url, options });
    return ok();
  } });
  assert.deepEqual(await provider.sendOtp({ ...request, ignoredPrivateNotes: 'do-not-send' }), { delivered: true });
  assert.equal(calls.length, 1);
  const target = new URL(calls[0].url);
  assert.equal(target.protocol, 'https:');
  assert.equal(target.host, 'api.kavenegar.com');
  assert.equal(target.pathname, `/v1/${apiKey}/verify/lookup.json`);
  assert.equal(target.searchParams.get('receptor'), '09121234567');
  assert.equal(target.searchParams.get('token'), '082735');
  assert.equal(target.searchParams.get('template'), 'lifeguideotp');
  assert.equal(target.searchParams.get('type'), 'sms');
  assert.equal([...target.searchParams.keys()].length, 4);
  const options = calls[0].options;
  assert.equal(options.method, 'GET');
  assert.equal(options.redirect, 'error');
  assert.ok(options.signal instanceof AbortSignal);
  assert.equal(options.headers.Accept, 'application/json');
  assert.equal(options.body, undefined);
});

test('Kavenegar rejects invalid environment without any outbound call or secret echo', () => {
  for (const config of [
    { KAVENEGAR_API_KEY: '' },
    { KAVENEGAR_API_KEY: 'short' },
    { KAVENEGAR_API_KEY: apiKey + '\\n' },
    { KAVENEGAR_TEMPLATE: '' },
    { KAVENEGAR_TEMPLATE: '../password' },
    { KAVENEGAR_TEMPLATE: 'LifeGuide template' },
    { KAVENEGAR_TEMPLATE: '%token' },
  ]) {
    assert.throws(() => createKavenegarSmsProvider({ env: { ...env, ...config } }), error => {
      assert.match(error.message, /^sms_provider_(token|template)_invalid$/);
      assert.equal(error.retryable, false);
      assert.equal(error.stack.includes(apiKey), false);
      return true;
    });
  }
});

test('Kavenegar rejects unapproved phone shape, token and overlong lifespan before calling fetch', async () => {
  let calls = 0;
  const provider = createKavenegarSmsProvider({ env, fetchImpl: async () => { calls++; return ok(); } });
  for (const message of [
    { ...request, phone: '+15550000001' },
    { ...request, phone: '09121234567' },
    { ...request, code: '12345' },
    { ...request, code: '12&456' },
    { ...request, expiresIn: 301 },
    { ...request, idempotencyKey: 'bad' },
  ]) {
    await assert.rejects(provider.sendOtp(message), error => safeError(error, 'sms_provider_input_invalid'));
  }
  assert.equal(calls, 0);
});

test('Kavenegar provider failures never cause automatic non-idempotent SMS retries', async () => {
  for (const status of [301, 400, 401, 403, 429, 500, 503]) {
    let readBody = false;
    const provider = createKavenegarSmsProvider({ env, fetchImpl: async () => ({
      status,
      body: { async cancel() { readBody = true; } },
    }) });
    await assert.rejects(provider.sendOtp(request), error => safeError(error, 'sms_provider_rejected'));
    assert.equal(readBody, true);
  }
});

test('Kavenegar treats HTTP200 provider rejection, malformed JSON or missing entries as failures', async () => {
  const cases = [
    [JSON.stringify({ return: { status: 411 }, entries: { messageid: 2 } }), 'sms_provider_rejected'],
    [JSON.stringify({ return: { status: 200 } }), 'sms_provider_rejected'],
    [JSON.stringify({ return: { status: 200 }, entries: [] }), 'sms_provider_rejected'],
    ['not json', 'sms_provider_malformed_response'],
    ['x'.repeat(8193), 'sms_provider_malformed_response'],
  ];
  for (const [body, code] of cases) {
    const provider = createKavenegarSmsProvider({ env, fetchImpl: async () => new Response(body, { status: 200 }) });
    await assert.rejects(provider.sendOtp(request), error => safeError(error, code));
  }
});

test('Kavenegar transport exception never exposes API key, phone or code', async () => {
  const provider = createKavenegarSmsProvider({ env,
    fetchImpl: async () => { throw new Error(`failed ${apiKey} ${request.phone} ${request.code}`); } });
  await assert.rejects(provider.sendOtp(request), error => safeError(error, 'sms_provider_unavailable'));
});

test('Kavenegar bounded timeout aborts fetch with sanitized error', async () => {
  let aborted = false;
  const provider = createKavenegarSmsProvider({ env, timeoutMs: 20, fetchImpl: async (_url, { signal }) => new Promise((_resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('fixture ignored abort')), 400);
    signal.addEventListener('abort', () => { aborted = true; clearTimeout(timer); reject(new Error(apiKey)); }, { once: true });
  }) });
  await assert.rejects(provider.sendOtp(request), error => safeError(error, 'sms_provider_timeout'));
  assert.equal(aborted, true);
});

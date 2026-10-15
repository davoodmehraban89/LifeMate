import test from 'node:test';
import assert from 'node:assert/strict';
import { createSmsProvider } from '../src/auth_delivery.js';

const config = { NODE_ENV: 'production', SMS_PROVIDER: 'kavenegar',
  KAVENEGAR_API_KEY: 'SyntheticApprovalFixtureNotALiveKey2026', KAVENEGAR_TEMPLATE: 'lifeguideotp' };
test('configured credentials cannot enable real SMS before both explicit live and template approval flags', () => {
  for (const flags of [{}, { SMS_LIVE_ENABLED: 'true' }, { KAVENEGAR_TEMPLATE_APPROVED: 'true' },
    { SMS_LIVE_ENABLED: 'true', KAVENEGAR_TEMPLATE_APPROVED: 'TRUE' }]) {
    let calls = 0;
    const provider = createSmsProvider({ env: { ...config, ...flags }, fetchImpl: async () => { calls++; assert.fail('No network allowed'); } });
    assert.equal(provider.configured, false);
    assert.equal(provider.status, 'APPROVAL_REQUIRED');
    assert.equal(calls, 0);
  }
});
test('nonproduction network providers also remain gated; development uses injected test-only adapters', () => {
  assert.equal(createSmsProvider({ env: { ...config, NODE_ENV: 'development' } }).configured, false);
});
test('the two explicit flags permit adapter construction but never send a message by themselves', () => {
  let calls = 0;
  const provider = createSmsProvider({ env: { ...config, SMS_LIVE_ENABLED: 'true', KAVENEGAR_TEMPLATE_APPROVED: 'true' }, fetchImpl: async () => { calls++; } });
  assert.equal(provider.configured, true);
  assert.equal(calls, 0);
});

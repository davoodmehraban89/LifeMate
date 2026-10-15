import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

test('direct production server start fails closed instead of bypassing shared auth IP and request guards', () => {
  const result = spawnSync(process.execPath, ['src/server.js'], {
    cwd: new URL('../', import.meta.url),
    env: { ...process.env, NODE_ENV: 'production', PORT: '0', SMS_PROVIDER: 'disabled', EMAIL_FROM: '',
      JWT_SECRET: 'synthetic-entrypoint-guard-fixture-not-live-2026',
      SMTP_HOST: '', RESEND_API_KEY: '', AI_API_KEY: '', AI_BASE_URL: '', AI_MODEL: '' },
    timeout: 2000, encoding: 'utf8',
  });
  assert.equal(result.status, 1, 'Use npm start; server.js must not open an unguarded production listener');
  assert.match(result.stderr, /production_entrypoint_required/);
  assert.doesNotMatch(result.stdout, /listening|startup/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const operations = fs.readFileSync(new URL('../src/operations.js', import.meta.url), 'utf8');
const entrypoint = fs.readFileSync(new URL('../src/entrypoint.js', import.meta.url), 'utf8');

test('operations layer provides correlation, safe telemetry and security headers', () => {
  assert.match(operations, /x-request-id/i);
  assert.match(operations, /x-content-type-options/i);
  assert.match(operations, /x-frame-options/i);
  assert.match(operations, /referrer-policy/i);
  assert.match(operations, /durationMs/);
  assert.doesNotMatch(operations, /req\.body/);
  assert.doesNotMatch(operations, /authorization/i);
});

test('operations layer defines bounded rate-limit profiles and retry-after', () => {
  assert.match(operations, /120/);
  assert.match(operations, /10\s*\*\s*60/);
  assert.match(operations, /30/);
  assert.match(operations, /Retry-After/);
  assert.match(operations, /rate_limited/);
});

test('production entrypoint exposes liveness and database readiness separately', () => {
  assert.match(entrypoint, /outer\.get\('\/live'/);
  assert.match(entrypoint, /outer\.get\('\/ready'/);
  assert.match(entrypoint, /select 1 as ok/);
  assert.match(entrypoint, /requestContext/);
  assert.match(entrypoint, /rateLimit/);
});

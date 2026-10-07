import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const read = (path) => fs.readFileSync(new URL(`../../${path}`, import.meta.url), 'utf8');

test('Cloudflare Worker deployment is configured for PostgreSQL', () => {
  const config = read('backend/wrangler.jsonc');
  assert.match(config, /lifeguide-api/);
  assert.match(config, /2026-10-07/);
  assert.match(config, /nodejs_compat/);
  assert.match(config, /src\/worker\.js/);

  const worker = read('backend/src/worker.js');
  assert.match(worker, /DATABASE_URL/);
  assert.match(worker, /NEON_DATABASE_URL/);
  assert.match(worker, /httpServerHandler/);
  assert.match(worker, /lifeguide-api/);
});

test('migration runbook preserves rollback until verification passes', () => {
  const runbook = read('docs/operations/CLOUDFLARE_NEON_MIGRATION.md');
  assert.match(runbook, /Neon PostgreSQL/i);
  assert.match(runbook, /Cloudflare Workers/i);
  assert.match(runbook, /Railway/i);
  assert.match(runbook, /rollback/i);
  assert.match(runbook, /pg_dump/);
  assert.match(runbook, /pg_restore/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('Cloudflare QA deploys only isolated LifeGuide web assets and disables live API until secure runtime exists', async () => {
  const script = await read('../../scripts/build-cloudflare-pages-qa.sh');
  assert.match(script,/FLUTTER_VERSION="3\.47\.6"/);
  assert.match(script,/flutter build web --release --no-web-resources-cdn --pwa-strategy=none/);
  assert.match(script,/self_host_web\.mjs build\/web/);
  assert.match(script,/apiBaseUrl!=='\/api'/);
  assert.match(script,/Cache-Control: no-store/);
  assert.doesNotMatch(script,/railway\.app|railway\.com|KAVENEGAR_API_KEY|SERVICE_ROLE_KEY|POSTGRES_PASSWORD|DATABASE_URL/);
});

test('QA API gateway paths fail closed with JSON 503, not SPA index.html fallback', async () => {
  for (const path of ['../../functions/api.ts','../../functions/api/[[path]].ts']) {
    const source = await read(path);
    assert.match(source,/503/);
    assert.match(source,/application\/json/);
    assert.match(source,/no-store/);
    assert.match(source,/lifeguide_api_not_ready/);
    assert.doesNotMatch(source,/fetch\s*\(/);
    assert.doesNotMatch(source,/service_role|supabaseKey|Authorization\s*:/i);
  }
  const ready=await read('../../functions/ready.ts');
  assert.match(ready,/status: 503/);
  assert.match(ready,/qa_backend_not_connected/);
  const health=await read('../../functions/health.ts');
  assert.match(health,/component: "pwa_gateway_only"/);
  assert.match(health,/backend: "not_connected"/);
});

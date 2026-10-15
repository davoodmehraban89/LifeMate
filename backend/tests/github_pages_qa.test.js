import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const read = path => readFile(new URL(path, import.meta.url), 'utf8');

test('LifeGuide GitHub Pages QA build reuses checked Flutter bundle without credentials', async () => {
  const script = await read('../../scripts/build-github-pages-qa.sh');
  assert.match(script, /bash scripts\/build-cloudflare-pages-qa\.sh/);
  assert.match(script, /touch "\$out\/\.nojekyll"/);
  assert.match(script, /config\.apiBaseUrl !== '\/api'/);
  assert.match(script, /config\.apiFallbackUrls\.length !== 0/);
  assert.match(script, /<base href="\/">/);
  assert.match(script, /site-check\.txt/);
  assert.doesNotMatch(script,/KAVENEGAR_API_KEY|DATABASE_URL|SUPABASE_SERVICE_ROLE_KEY|\.up\.railway\.app/);
});

test('GitHub Pages workflow deploys only after configured Pages action approval', async () => {
  const workflow = await read('../../.github/workflows/lifeguide-github-pages-qa.yml');
  assert.match(workflow,/infra\/lifeguide-github-pages-qa/);
  assert.match(workflow,/scripts\/build-github-pages-qa\.sh/);
  assert.match(workflow,/actions\/configure-pages@v5/);
  assert.match(workflow,/actions\/upload-pages-artifact@v4/);
  assert.match(workflow,/actions\/deploy-pages@v4/);
  assert.match(workflow,/pages: write/);
  assert.match(workflow,/id-token: write/);
  assert.match(workflow,/github-pages/);
  assert.doesNotMatch(workflow,/main\]|deployment-static|KAVENEGAR_API_KEY|DATABASE_URL|SUPABASE_SERVICE_ROLE_KEY/);
});

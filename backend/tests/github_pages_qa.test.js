import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const read = path => readFile(new URL(path, import.meta.url), 'utf8');
const run = promisify(execFile);

test('LifeGuide GitHub Pages QA supports repo-path smoke before a custom domain', async () => {
  const script = await read('../../scripts/build-github-pages-qa.sh');
  const sharedBuilder = await read('../../scripts/build-cloudflare-pages-qa.sh');
  assert.match(script, /LIFEGUIDE_PAGES_BASE_HREF:-\/LifeMate\//);
  assert.match(script, /\/LifeMate\/\|\//);
  assert.match(script, /LIFEGUIDE_FLUTTER_BASE_HREF="\$LIFEGUIDE_PAGES_BASE_HREF"/);
  assert.match(sharedBuilder, /LIFEGUIDE_FLUTTER_BASE_HREF:-\//);
  assert.match(sharedBuilder, /--base-href "\$LIFEGUIDE_FLUTTER_BASE_HREF"/);
  assert.match(script, /bash scripts\/build-cloudflare-pages-qa\.sh/);
  assert.match(script, /touch "\$out\/\.nojekyll"/);
  assert.match(script, /const expectedApiBase = base === '\/' \? '\/api' : base \+ 'api'/);
  assert.match(script, /config\.apiBaseUrl = expectedApiBase/);
  assert.match(script, /config\.apiFallbackUrls\.length !== 0/);
  assert.match(script, /<base href="/);
  assert.match(script, /site-check\.txt/);
  assert.doesNotMatch(script, /KAVENEGAR_API_KEY|DATABASE_URL|SUPABASE_SERVICE_ROLE_KEY|\.up\.railway\.app/);
});

test('LifeGuide Pages QA refuses unsupported base URLs before invoking Flutter', async () => {
  const script = new URL('../../scripts/build-github-pages-qa.sh', import.meta.url).pathname;
  await assert.rejects(
    () => run('bash', [script], {env: {...process.env, LIFEGUIDE_PAGES_BASE_HREF: '/untrusted/'}}),
    error => error.code === 2 && /Unsupported LifeGuide Pages QA base href/.test(error.stderr),
  );
});

test('GitHub Pages QA fails before an expensive Flutter build when Pages is off', async () => {
  const workflow = await read('../../.github/workflows/lifeguide-github-pages-qa.yml');
  assert.match(workflow, /infra\/lifeguide-github-pages-qa/);
  assert.match(workflow, /actions\/configure-pages@v5/);
  assert.match(workflow, /LIFEGUIDE_PAGES_BASE_HREF: \/LifeMate\//);
  assert.match(workflow, /scripts\/build-github-pages-qa\.sh/);
  assert.match(workflow, /actions\/upload-pages-artifact@v4/);
  assert.match(workflow, /actions\/deploy-pages@v4/);
  assert.match(workflow, /pages: write/);
  assert.match(workflow, /id-token: write/);
  assert.match(workflow, /github-pages/);
  assert(workflow.indexOf('actions/configure-pages@v5') <
    workflow.indexOf('scripts/build-github-pages-qa.sh'),
    'Configure-pages must fail before Flutter fetch/build when disabled.');
  assert.doesNotMatch(workflow, /main\]|deployment-static|KAVENEGAR_API_KEY|DATABASE_URL|SUPABASE_SERVICE_ROLE_KEY/);
});

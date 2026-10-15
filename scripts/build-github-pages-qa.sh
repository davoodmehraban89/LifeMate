#!/usr/bin/env bash
# LifeGuide QA STATIC-ONLY Pages artifact. No login/API or family sync is hosted here.
# Default GitHub project Pages URL: /LifeMate/. Switch to / ONLY after GitHub
# accepts the isolated qa.lifeguide.ir custom hostname.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

export LIFEGUIDE_PAGES_BASE_HREF="${LIFEGUIDE_PAGES_BASE_HREF:-/LifeMate/}"
case "$LIFEGUIDE_PAGES_BASE_HREF" in
  /LifeMate/|/) ;;
  *) echo "Unsupported LifeGuide Pages QA base href" >&2; exit 2 ;;
esac
export LIFEGUIDE_FLUTTER_BASE_HREF="$LIFEGUIDE_PAGES_BASE_HREF"

# Reuse pinned Flutter 3.47.6 self-hosting/asset checks, not a second build pipeline.
bash scripts/build-cloudflare-pages-qa.sh
out="apps/lifemate/build/web"

# Cloudflare-specific response header directives cannot secure GitHub Pages.
rm -f "$out/_headers"
touch "$out/.nojekyll"

node --input-type=module <<'NODE'
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
const path = 'apps/lifemate/build/web/';
const base = process.env.LIFEGUIDE_PAGES_BASE_HREF;
const expectedApiBase = base === '/' ? '/api' : base + 'api';
const config = JSON.parse(readFileSync(path + 'config.json', 'utf8'));
if (config.apiBaseUrl !== '/api' ||
    !Array.isArray(config.apiFallbackUrls) ||
    config.apiFallbackUrls.length !== 0) {
  throw new Error('QA config must start fail-closed with no external API fallback');
}
// Keep the unimplemented endpoint inside this app's path on github.io; do not
// accidentally target another project hosted under the same origin.
config.apiBaseUrl = expectedApiBase;
writeFileSync(path + 'config.json', JSON.stringify(config) + '\n');
const index = readFileSync(path + 'index.html', 'utf8');
if (!index.includes(`<base href="${base}">`) || !index.includes('LifeGuide')) {
  throw new Error('Pages index base href does not match the selected hosting path');
}
for (const file of ['main.dart.js', 'flutter_bootstrap.js', 'lifeguide-sw.js',
  'manifest.json', 'favicon.png', 'canvaskit']) {
  if (!existsSync(path + file)) throw new Error('Missing QA web asset: ' + file);
}
const version = process.env.GITHUB_SHA?.slice(0,12) || 'local';
writeFileSync(path + 'site-check.txt',
  'LifeGuide GitHub Pages QA STATIC_ONLY ' + version + ' BASE=' + base + '\n');
NODE

test -s "$out/main.dart.js"
test -s "$out/site-check.txt"
echo "LifeGuide Pages QA static artifact built for $LIFEGUIDE_PAGES_BASE_HREF (API unavailable)."

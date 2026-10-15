#!/usr/bin/env bash
# LifeGuide QA: STATIC PWA ONLY, built for GitHub Pages with a custom-domain root.
# Do not use this as proof of user login / API readiness.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

# Reuse the already-tested, pinned Flutter 3.47.6 build and local asset bundling.
bash scripts/build-cloudflare-pages-qa.sh
out="apps/lifemate/build/web"

# _headers is a Cloudflare Pages directive; it does not protect GitHub Pages.
rm -f "$out/_headers"
touch "$out/.nojekyll"

node --input-type=module <<'NODE'
import { readFileSync, writeFileSync } from 'node:fs';
const path = 'apps/lifemate/build/web/';
const config = JSON.parse(readFileSync(path + 'config.json','utf8'));
if (config.apiBaseUrl !== '/api' ||
    !Array.isArray(config.apiFallbackUrls) ||
    config.apiFallbackUrls.length !== 0) {
  throw new Error('QA app must not silently fall back to Railway or an unverified backend');
}
const index = readFileSync(path + 'index.html','utf8');
if (!index.includes('<base href="/">') || !index.includes('LifeGuide')) {
  throw new Error('GitHub Pages custom-domain root assets not configured');
}
const version = process.env.GITHUB_SHA?.slice(0,12) || 'local';
writeFileSync(path + 'site-check.txt', 'LifeGuide GitHub Pages QA STATIC_ONLY ' + version + '\n');
NODE

test -s "$out/main.dart.js"
test -s "$out/site-check.txt"
echo "GitHub Pages QA static artifact prepared. API registration remains unavailable."

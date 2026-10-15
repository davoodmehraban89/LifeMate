#!/usr/bin/env bash
# LifeGuide v0.7.1 QA PWA -> Cloudflare Pages. This DOES NOT deploy the backend.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
export CI=true
FLUTTER_VERSION="3.47.6"
FLUTTER_ROOT="${HOME}/.lifeguide-qa-flutter"
if [[ ! -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
  git clone --quiet --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
fi
export PATH="${FLUTTER_ROOT}/bin:${PATH}"
flutter config --no-analytics >/dev/null
flutter precache --web
cd apps/lifemate
flutter pub get
node tool/test_web_bootstrap.mjs
node --test tool/test_offline_worker.mjs
# Root is the existing Cloudflare behaviour. GitHub Pages QA may require
# a repository subpath before the custom .ir hostname is configured.
LIFEGUIDE_FLUTTER_BASE_HREF="${LIFEGUIDE_FLUTTER_BASE_HREF:-/}"
case "$LIFEGUIDE_FLUTTER_BASE_HREF" in
  /|/LifeMate/) ;;
  *) echo "Unsupported LifeGuide QA base href" >&2; exit 2 ;;
esac
flutter build web --release --no-web-resources-cdn --pwa-strategy=none --base-href "$LIFEGUIDE_FLUTTER_BASE_HREF"
node tool/self_host_web.mjs build/web
node tool/test_web_bootstrap.mjs
test -s build/web/index.html
test -s build/web/main.dart.js
test -s build/web/config.json
# The existing PWA expects a same-origin /api; until a verified QA API exists
# the Pages Function responds 503 JSON, never an HTML fallback or Railway.
node -e "const x=require('./build/web/config.json');if(x.apiBaseUrl!=='/api'||x.apiFallbackUrls.length)process.exit(1)"
cat > build/web/_headers <<'HEADERS'
/*
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  X-Frame-Options: DENY
  Permissions-Policy: camera=(), microphone=(), geolocation=()
/config.json
  Cache-Control: no-store
/main.dart.js
  Cache-Control: no-cache
/flutter_bootstrap.js
  Cache-Control: no-cache
/manifest.json
  Cache-Control: no-cache
HEADERS
printf 'LifeGuide QA PWA static build complete. API remains disabled until verified.\n'

# Stage0 readiness while owner-PC acceptance is pending

The owner has no access to the home PC. No immediate owner action is required. Actual Windows/PowerShell/Docker Desktop and physical Android/Safari acceptance remain **UNVERIFIED**. This packet addresses independently reproducible preparation failures; it does not deploy the candidate or make the old public domain a new test endpoint.

## Actual Git checkout regression

Root independently ran the regression with **Node22.23.3**, using the real previously built/postprocessed/stamped web artifact. No Flutter build, provenance restamp, application-source edit or binary rewrite ran.

```text
RED EXPECTED: exit1 old checkout policy rejected real checked artifact at manifest.json
PASS original checked artifact
PASS actual Git checkout core.autocrlf=false
PASS core.autocrlf=false: three shell scripts retain LF;13 font/icon binaries are byte-identical
PASS actual Git checkout core.autocrlf=true
PASS core.autocrlf=true: three shell scripts retain LF;13 font/icon binaries are byte-identical
PASS source change is still rejected
PASS artifact change is still rejected
PASS prebuilt checkout regression: provenance, Windows checkout, shell endings, binary preservation and tamper rejection; no build or restamp performed.
```

Commands actually run:

```bash
node scripts/test-prebuilt-checkout.mjs
node scripts/prebuilt-web-check.mjs apps/lifemate
```

The RED run temporarily removed only the new LF rule and restored its exact bytes in a `finally` block before the GREEN run. The original Git configuration was never changed. Each test uses Git's real `checkout-index`, copies the existing artifact into an isolated temporary checkout, runs the unchanged integrity checker and removes the temporary checkout. Synthetic tamper probes modify only temporary copies.

Root policy `* text=auto eol=lf` preserves text endings under Windows-style `core.autocrlf=true` and leaves binary bytes intact. Backup/restore/local-deploy shell inputs retain Linux-executable endings. Existing font-license whitespace rules are preserved. The recorded artifact is still47 inputs, source digest `1eeb1d833d63331e1a24a322836f8d9bf1f24205267e33286ff3a2349a6eff53`, artifact digest `c6937cc01490dd289d09adc1e84a32824c720cb22d97a470e99e78fabd1cf1b0`, recorded2026-10-09T06:22:16.747Z. Git emulation on Linux is not an actual Windows execution.

CI runs the regression after the real release web build/postprocessing/provenance step. [Run37900944165](https://github.com/davoodmehraban89/LifeMate/actions/runs/37900944165) on source `7d35ee64a8d4aee51a92ee5fe551e8b3c33761e9` completed successfully; its actual log passes both Git modes, three shell endings,13 binary inputs and both tamper refusals. [Sanitized receipt](evidence/ci-stage0-readiness-2026-10-09.json). The earlier application receipts from [isolation verification](2026-10-09-isolation-verification.md) remain historical evidence.

## Actual TLS regression and real local smoke

The reachability script previously inherited `NODE_TLS_REJECT_UNAUTHORIZED=0`. A specialist reproduced the problem with an actual loopback HTTPS server and an untrusted temporary CA: the old script reported `exit=0, TLS=PASS`. Node22.23.3 baseline suite was RED with3 passes/2 failures. This was not a successful trust check; it demonstrated a false positive. No public endpoint was contacted by that regression.

The fix sets `rejectUnauthorized:true` for every request, captures `socket.authorized` in the response callback and requires strict `true` before reporting TLS PASS. Root independently ran the permanent suite on Node22.23.3:

```text
ok1 trusted local CA and matching hostname pass read-only smoke without TLS-disable
ok2 untrusted CA fails before opted-in synthetic auth or writes
ok3 inherited NODE_TLS_REJECT_UNAUTHORIZED=0 cannot produce a false TLS PASS
Local untrusted fixture: exit=1, TLS=not recorded
ok4 inherited TLS-disable cannot reach opted-in synthetic auth or writes
ok5 trusted CA with hostname mismatch fails before opted-in synthetic auth or writes
tests5; pass5; fail0; cancelled0; skipped0; todo0
```

```bash
node --test scripts/test-reachability-smoke.mjs
ROOT_CA_FILE=/path/to/public-local-ca.pem node scripts/reachability-smoke.mjs https://127.0.0.1:8443
```

Root also executed the second command against the existing real synthetic Compose stack at **2026-10-09T07:43:47.247Z**, with its normal public CA and no TLS-disable setting. **5 checks PASS:** TLS chain/hostname, database health, PWA HTML/manifest, same-origin/no-store runtime config and anonymous planner401. API write round-trip was intentionally not opted into in this run and remains **UNVERIFIED for this run**; prior write acceptance is separately recorded. No new task/session or credential was created. The local regression's CA/private keys are generated outside the repository and removed by teardown; no private key is tracked. [Real local read-only receipt](evidence/stage0-readiness-https-2026-10-09.json).

The same completed CI ran the5 TLS tests on Node22:5 passed, zero failures/skips. Actual device TLS trust and Iran reachability are separate pending gates.

## Actual CI build and installer delivery

All three jobs completed SUCCESS: backend130/130, runtime-family9/9, TLS5/5, Flutter68 passed, Chrome guards3 passed, analyzer clean, twelve restored migration checksums, compiled-instance8 cases and expiry queue retention. The new Windows-style checkout regression passed against the web artifact built in that run. The release web build took40.9s and runtime asset check recorded13 local requests/zero external/missing/errors. These browser tests use intercepted synthetic responses and do not prove real Safari or TLS.

The actual APK was built and its binary manifest inspected on the runner: **ir.lifeguide.app,0.5.1,versionCode4,لایف‌گاید**, minSDK24/targetSDK36, backup/cleartext=false. `apksigner` reported `Verifies`/v2=true with Android Debug certificate. [LifeGuide-debug-apk](https://github.com/davoodmehraban89/LifeMate/actions/runs/37900944165/artifacts/11602957035) and [LifeGuide-web](https://github.com/davoodmehraban89/LifeMate/actions/runs/37900944165/artifacts/11602657441) are uploaded test artifacts, not a public release.

APK SHA256 is `7697b6e2ce094823c32dd50ede34f34bf4626154e0c50b92b36b72a14dccbaef`. ZIP SHA256 is `0fff8f3361230d2ea98e25d64f57496ccf10d12a983f4f9cb78a852c58d17f8e`. The official GitHub connector downloaded the ZIP into a reusable FileService reference for private delivery. A local GET of its temporary download URL returned403, so independent local ZIP extraction/APK inspection remain **UNVERIFIED**; runner inspection is separately evidenced. No ZIP was mislabeled as an APK.

The debug certificate hash `32b5fb29e0a669ba75628d819a9ca36c84cf4e8ad2b6798bc280032e03d6d1fb` differs from the previous same-package CI artifact. An in-place upgrade between those two debug APKs is not supported. Do not uninstall or clear app data to solve a signature error while unsent work exists. Owner-stable release signing and physical install/upgrade are still **UNVERIFIED**; no owner key was created, public release performed or data cleared.

## Public-domain read-only checks

At07:32:31UTC, actual public DNS and static HTTPS GET observed the old0.1.0/build1 on `app.lifeguide.ir`, with `/config.json` returning HTML200. [Sanitized receipt and precise limits](2026-10-09-public-domain.md). A separate parse/assertion run passed5/5 checks on that recorded response set; those assertions are snapshot consistency checks, not additional network/device acceptance.

No public login/write, live server/CDN/DNS change, new account/payment, merge, release, real-data migration or owner-PC access occurred.

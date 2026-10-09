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

CI is configured to run the regression after the real release web build/postprocessing/provenance step. Execution of that new CI step remains **UNVERIFIED** until a new run produces evidence; the previous successful0.5.1 CI did not include it. The application build/test receipts from [isolation verification](2026-10-09-isolation-verification.md) remain historical evidence for the unchanged application source.

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

CI is configured to run the5 TLS tests on Node22. Execution of that new CI step is **UNVERIFIED** until a new run reports it. Actual device TLS trust and Iran reachability are separate pending gates.

## Public-domain read-only checks

At07:32:31UTC, actual public DNS and static HTTPS GET observed the old0.1.0/build1 on `app.lifeguide.ir`, with `/config.json` returning HTML200. [Sanitized receipt and precise limits](2026-10-09-public-domain.md). A separate parse/assertion run passed5/5 checks on that recorded response set; those assertions are snapshot consistency checks, not additional network/device acceptance.

No public login/write, live server/CDN/DNS change, new account/payment, merge, release, real-data migration or owner-PC access occurred.

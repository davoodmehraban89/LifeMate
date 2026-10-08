# LifeGuide / لایف‌گاید — وضعیت واقعی پروژه

Updated: 2026-10-08. Backend version: **0.5.0**. Branch: **feat/online-family-stage0**, based on main `abdc9d9d032bc6746c8390b902a2e52d82991530`. Repository remains `davoodmehraban89/LifeMate`.

**Status: shared online Stage 0 stack verified locally with synthetic data; hardware/release gates remain open. Not a complete operational product or public release.** Prior COMPLETE/READY claims are retained only in [historical checkpoint](docs/history/2026-10-05-project-state.md); they do not prove this candidate's acceptance. [Draft PR #10](https://github.com/davoodmehraban89/LifeMate/pull/10) is open; main is not merged.

## Baseline and reuse

[Main gap analysis](docs/audits/2026-10-08-online-gap-analysis.md) was written before new implementation. GitHub refs verified: local persistence `62e82ba`, backend safety `e5e3e41`, Cloudflare/Neon `7a83ca8`; only isolated backend safety commit reused. Login-free LocalOnlyApi and managed-host adapters were not merged into the online product. Main already contains family/guardian identity, planner/offline queue, authorization tests and **Feature 1** Iranian education/catalog/calendar/preferences; these are preserved. Feature 1 household persona is a preference, not a server grant of parental access. Health/cycle UI and external AI/voice remain disabled.

## Current implementation

- Shared Node/Express/Argon2id/PostgreSQL with migrations 0007–0012: optional email/phone identity, verification delivery recovery, rate-limited resend, opt-in HTTPS webhook SMS adapter, hashed tokens and refresh rotation. Test runner removes inherited live delivery/AI settings.
- Current family/membership/guardian checks, private notes stripped from shared task views, report metrics scoped per visible task. Family archival and revoked membership/guardian relationships close access. Selected grants do not resurrect after rejoining.
- Canonical plan creation version1, stable UUID offline mutations, request-hash idempotency, row/owner locks, expected-version conflicts, canonical server acknowledgement; edit and safe archive use real storage.
- Study sessions/intervals/events survive backend restart; start/pause/resume/stop, corrections/archive, overlap/duplicate protection. Timer/self-reported durations are explicitly not proof of study. Guardian confirmation requires authorized evidence.
- Persian RTL parent views, allowed learning reports, activity timestamps, last-refresh/error state and polling. Seven/thirty-day reports include all of today in Tehran, without changing server freshness timestamps. Android endpoint settings/fallback selection and web no-store config.json use one chosen HTTPS API; endpoint/account switch clears old credentials/cache.
- Client queue/cache scoped to endpoint+authenticated user, durable enqueue-before-send, FIFO chains, malformed-ack rejection, conflicts retained, logout generation invalidation. Explicit server conflict choice journals local payloads before removing their full pending chain. Storage failures are not mistaken for network outages.
- Subject/class and private learning check-in CRUD/archive now use owner validation and retain linked homework/history. Profile category and editable display name remain independent of family permissions.
- Self-hosted Compose API/Postgres/nginxTLS + backup cron/healthchecks; tested synthetic backup/restore uses existing scripts. Runtime web fonts/CanvasKit are bundled locally. Notification polling uses a replaceable delivery port; background push is not enabled.
- Product rebrand **LifeGuide**, Android **ir.lifeguide.app**, release key required from secrets; automatic public publishing and unused fix workflow removed. Deployment and signed-APK workflows are manual and disabled by default.

## Execution evidence so far

Actual output and A–H limits are recorded in [online acceptance](docs/audits/2026-10-08-online-acceptance.md) and [Stage 0 verification](docs/audits/2026-10-08-stage0-verification.md). Root reran Node22.23.3 against a fresh PostgreSQL16 database: **130/130 passed, zero failures/skips**. All twelve migrations applied, four SQL matrices passed, syntax check covered 38 files and dependency audit reported zero vulnerabilities. The independent real-entrypoint/HTTP/DB eight-step substitute passed **9/9**. Flutter aggregate **64/64**, analyzer clean; final frozen-source release web build **57.5s**. Compiled browser request test observed 14 local requests, zero external/missing/error; its HTTPS responses are explicitly intercepted and do not prove real TLS.

Local prebuilt Compose PostgreSQL/API/nginxTLS/backup are healthy. Real trusted HTTPS smoke passed create/read/archive/logout; synthetic family task and 1500-second paused session survive API image recreation. Mother/father browser rendering and session restart evidence are recorded separately from backend substitutes. Backup cron, two concurrent distinct archives and fresh synthetic restore/privacy/session drill passed. Complete SDK Dockerfile image build failed with disk/snapshot exhaustion; **UNVERIFIED**, while the checked host/CI web artifact has a lighter Compose packaging path. Historical checksum-less ledger entries are not retrospectively certified; fresh twelve-entry ledgers have checksums.

The first source CI passed backend tests/SQL but failed backup due to non-executable scripts; file mode and PostgreSQL16 client/container invocation were fixed and local restore retained **12/12** ledger/checksum entries. Final source commit **`7d9366832adaaab4cc3f24ef4d928fddd307fdc9`**, [CI run 37810558847](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847): **all three jobs succeeded**, including 130 backend tests, 64 Flutter tests, PostgreSQL16 backup/restore, release web build and actual debug APK build/upload. [LifeGuide-web](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847/artifacts/11563914781) and [LifeGuide-debug-apk](https://github.com/davoodmehraban89/LifeMate/actions/runs/37810558847/artifacts/11565283053) are test artifacts; debug signing is not a release. Independent downloaded APK inspection/install and release signing remain **UNVERIFIED**. Subsequent handover documentation does not change the application source tested by that run. No live host, DNS, production deploy, real-data migration, merge, signup, purchase or public release ran.

## UNVERIFIED acceptance and remaining gates

- Real Android three-device lifecycle/install/upgrade; iPhone/iPad Safari login, Add to Home Screen and safe PWA update.
- Windows PowerShell/WSL2/mkcert owner-PC installation and trusted mobile TLS.
- VPN-free API/PWA/APK reachability inside Iran; foreign VPS/payment/KYC eligibility. No suitable long-term free/no-card VPS was verified; Stage 0 LAN is the primary recommendation.
- Real email/SMS delivery/provider/payment, timing-indistinguishability of registration, background push.
- Owner release keystore/certificate, genuinely signed LifeGuide.apk and public availability.
- Legal/consent/retention gates for minor wellbeing and cycle data; in-country sensitive storage policy. These gates are flagged, not implemented or certified.
- Complete account contact/closure, active-member role/admin transfer, and legacy life-context/year/term lifecycle CRUD; richer school/check-in UI and detailed exam/grade reports. Subject/class/check-in API CRUD is now tested, but that does not complete every auxiliary entity or its UI.
- Separate least-privilege PostgreSQL runtime/migration roles before real data; encrypted/off-PC backups and periodic restore. Compose currently uses its bootstrap DB role.
- Fully offline cold PWA startup, browser eviction/storage quota and hardware accessibility/update behavior. Cross-tab browser cache/token coordination is not implemented/tested; use one active PWA/tab per browser profile for this candidate. Pending study events must receive acknowledgement before another event is recorded.

## Next and operator responsibilities

Owner runs [Stage 0](docs/operations/STAGE0.md) using the checked prebuilt web artifact, synthetic accounts and A–H hardware acceptance; record real Android/Safari/Windows and VPN-free Iran results before operational use. The next engineering packet should close browser cross-tab coordination, least-privilege database roles, remaining account/membership lifecycle CRUD and detailed school UI/report gaps. Owner chooses hosting, DNS, SMS/email provider and signing key outside chat; any live change needs its explicit approval. [Hosting ADR](docs/decisions/0009-provider-neutral-hosting.md), [naming ADR](docs/decisions/0010-lifeguide-naming.md), [migration/rollback](docs/operations/DOMESTIC_MIGRATION.md).

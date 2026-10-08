# LifeGuide / لایف‌گاید — وضعیت واقعی پروژه

Updated: 2026-10-08. Backend version: **0.5.0**. Branch: **feat/online-family-stage0**, based on main `abdc9d9d032bc6746c8390b902a2e52d82991530`. Repository remains `davoodmehraban89/LifeMate`.

**Status: online Stage 0 candidate, integration in progress. Not a complete operational product or public release.** Prior COMPLETE/READY claims are retained only in [historical checkpoint](docs/history/2026-10-05-project-state.md); they do not prove this candidate's acceptance.

## Baseline and reuse

[Main gap analysis](docs/audits/2026-10-08-online-gap-analysis.md) was written before new implementation. GitHub refs verified: local persistence `62e82ba`, backend safety `e5e3e41`, Cloudflare/Neon `7a83ca8`; only isolated backend safety commit reused. Login-free LocalOnlyApi and managed-host adapters were not merged into the online product. Main already contains family/guardian identity, planner/offline queue, authorization tests and **Feature 1** Iranian education/catalog/calendar/preferences; these are preserved. Feature 1 household persona is a preference, not a server grant of parental access. Health/cycle UI and external AI/voice remain disabled.

## Current implementation

- Shared Node/Express/Argon2id/PostgreSQL with migrations 0007 onward: optional email/phone identity, verification delivery recovery, rate-limited resend, provider port, hashed tokens and refresh rotation.
- Current family/membership/guardian checks, private notes stripped from shared task views, report metrics scoped per visible task. Family archival and revoked membership/guardian relationships close access. Selected grants do not resurrect after rejoining.
- Canonical plan creation version1, stable UUID offline mutations, request-hash idempotency, row/owner locks, expected-version conflicts, canonical server acknowledgement; edit and safe archive use real storage.
- Study sessions/intervals/events survive backend restart; start/pause/resume/stop, corrections/archive, overlap/duplicate protection. Timer/self-reported durations are explicitly not proof of study. Guardian confirmation requires authorized evidence.
- Persian RTL parent views, allowed learning reports, activity timestamps, last-refresh/error state and polling. Android endpoint settings/fallback selection and web no-store config.json use one chosen HTTPS API; endpoint/account switch clears old credentials/cache.
- Client queue/cache scoped to endpoint+authenticated user, durable enqueue-before-send, FIFO chains, malformed-ack rejection, conflicts retained, logout generation invalidation. Storage failures are not mistaken for network outages.
- Self-hosted Compose API/Postgres/nginxTLS + backup cron/healthchecks; tested synthetic backup/restore uses existing scripts. Runtime web fonts/CanvasKit are bundled locally. Notification polling uses a replaceable delivery port; background push is not enabled.
- Product rebrand **LifeGuide**, Android **ir.lifeguide.app**, release key required from secrets; automatic public publishing and unused fix workflow removed. Deployment and signed-APK workflows are manual and disabled by default.

## Execution evidence so far

Actual output is recorded in [Stage 0 verification](docs/audits/2026-10-08-stage0-verification.md). Before final integration, the team executed fresh real PostgreSQL migrations and backend tests (95 passed), an independent HTTP/DB eight-step scenario (9 assertions passed), focused runtime/session/endpoint tests, and focused offline tests. Root executed proxy HTTP tests (3 passed), offline FIFO/ack/scope tests (8 passed), local bootstrap regression and diff checks. These counts are intermediate; final aggregate results belong in the handover report.

Local Compose PostgreSQL/API/backup are healthy; repeat migrations and scheduled backup plus synthetic restore/privacy/session drill ran successfully. First gateway builds failed (SDK/proxy/source issues), were not counted as success, and are being rebuilt. No live host, DNS, production deploy, real-data migration, merge or public release ran.

## UNVERIFIED acceptance and remaining gates

- Real Android three-device lifecycle/install/upgrade; iPhone/iPad Safari login, Add to Home Screen and safe PWA update.
- Windows PowerShell/WSL2/mkcert owner-PC installation and trusted mobile TLS.
- VPN-free API/PWA/APK reachability inside Iran; foreign VPS/payment/KYC eligibility. No suitable long-term free/no-card VPS was verified; Stage 0 LAN is the primary recommendation.
- Real email/SMS delivery/provider/payment, timing-indistinguishability of registration, background push.
- Owner release keystore/certificate, genuinely signed LifeGuide.apk and public availability.
- Legal/consent/retention gates for minor wellbeing and cycle data; in-country sensitive storage policy. These gates are flagged, not implemented or certified.
- Complete lifecycle CRUD for legacy auxiliary school/context/check-in entities and richer report UX must be audited against scope. Existing implementations must not be called complete merely because tests pass.

## Next and operator responsibilities

Finish the local HTTPS/PWA integration and actual aggregate regression; open/update the feature PR with exact evidence and unverified gaps. Owner then runs [Stage 0](docs/operations/STAGE0.md) with synthetic accounts and A–H hardware acceptance. Owner chooses hosting, DNS, SMS/email provider and signing key outside chat; any live change needs its explicit approval. [Hosting ADR](docs/decisions/0009-provider-neutral-hosting.md), [naming ADR](docs/decisions/0010-lifeguide-naming.md), [migration/rollback](docs/operations/DOMESTIC_MIGRATION.md).

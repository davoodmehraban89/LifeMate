# LifeGuide Changelog

## 0.5.1 — 2026-10-09 — online isolation hardening

- Separate PostgreSQL bootstrap, migration, API and read-only backup credentials; reject excessive existing ownership/privileges before provisioning.
- Require explicit, backup-validated adoption of existing application objects; retain current migrations and server-side family permissions.
- Acquire an exclusive browser Web Lock before Flutter, session or cache startup; show a Persian retry screen for a second instance or unsupported browsers.
- Preserve account-scoped unsent mutations on forced session expiry; invalidate stale handles and recover only after the same account authenticates again. Deliberate logout/server switch retains its discard policy.
- Add real PostgreSQL role/restore and compiled Chromium regressions to CI, plus inspection of the actual debug APK manifest/signature.
- Real-device/Safari, Windows, Iran reachability, live providers and owner-signed release remain UNVERIFIED. See PROJECT_STATE.md for execution evidence.

## 0.5.0 — 2026-10-08 — online Stage 0 candidate

- Rebrand product as LifeGuide / لایف‌گاید; preserve repository, schema and JWT protocol identifiers.
- Reuse main identity/family/planner/Feature 1 instead of replacing it with the login-free local test API.
- Add provider-neutral Docker Compose PostgreSQL/API/TLS/PWA package, backup cron, local deployment, reachability and synthetic restore/migration runbooks.
- Add email delivery failure recovery, generic registration response, rate-limited verification resend, optional email/phone OTP provider boundary and ownership/password proof.
- Harden active memberships, guardian privacy, invitation reuse and disabled external AI/voice/sensitive data gates.
- Add real study sessions with pause/resume, versioned/idempotent events, overlap protection and authorized reports; recorded time is not evidence of study.
- Add runtime endpoint configuration, scoped session/cache/queue, server acknowledgements, optimistic versions and visible conflicts.
- Preserve discarded conflict payloads in an explicit recovery journal; test reminder replay, private school/class/check-in CRUD/archive and complete Tehran-day report windows.
- Add disabled-by-default HTTPS SMS webhook adapter and isolate live delivery/AI environment variables from all test processes.
- Set Android ID ir.lifeguide.app; require real owner release signing; remove automatic public publishing and unused fix workflow.
- Real-device/Safari, reachability from Iran, live provider delivery and official signed release remain UNVERIFIED. See PROJECT_STATE.md for actual execution evidence.

## 0.3.0 — historical Phase 5 candidate

Added operational headers/rate limits/probes, PostgreSQL backup/restore scripts, CI and release runbooks. Historical CI/hosting results do not prove current online acceptance.

## 0.2.0 — historical Phase 4

Added goals/check-ins, advisory guides, proposals and guardian summaries. Sensitive features in the current candidate are disabled pending consent/legal/in-country gates.

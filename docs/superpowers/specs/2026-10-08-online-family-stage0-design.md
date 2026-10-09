# LifeGuide — online family system, Stage 0 design

The owner's 2026-10-08 execution brief authorizes local implementation, synthetic tests, documentation and a private PR. Hosting selection, production deployment, DNS, real-data migration, final merge and public release remain owner actions. This design builds on main, not a replacement of its domain model. See the committed [gap analysis](../../audits/2026-10-08-online-gap-analysis.md).

## Deployment and data authority

Stage 0 runs PostgreSQL, the existing Express API and a TLS reverse proxy on one Windows LAN host through Docker Compose. PWA, `/api`, `/config.json` and optional `/downloads/LifeGuide.apk` share one HTTPS origin. The same package moves to an owner-controlled Linux server without a managed database. Docker volumes hold PostgreSQL; tested pg_dump/restore and an operator-managed backup target precede migration. No automated live cutover is authorized. mkcert trust is installed by the operator on test devices; no certificate-validation bypass is permitted.

No suitable long-term free/no-card VPS or Iran reachability is assumed. The hosting ADR records actual official sources and UNVERIFIED eligibility/reachability. No accounts, purchases or foreign-host real personal data are part of implementation.

## Existing code to preserve

Retain identity/family/guardian tables, Argon2id, hashed tokens, refresh rotation, planner/school APIs, sharing model, reminders/outbox, Feature 1 Iran curriculum/calendar and existing authorization tests. Reuse request/session repair commit `148c260` selectively. Do not import its Railway endpoint or the local-only entrypoint. Keep repository paths, database identifiers and JWT issuer/audience as compatible protocol identifiers.

## Identity and privacy

Registration uses one verified contact channel, email or phone; failure to deliver never becomes a false post-commit 500 or a dead-end duplicate account. Production register/resend responses are generic. Resend/OTP have bounded expiry, attempts, cooldown and rate limits. SMS is an explicit provider port, disabled without operator configuration; no real provider send is executed by tests. Phone-only members can accept contact-bound invitations through an authorized share link.

Every authenticated route checks a current session and active account. Guardian reads require current membership, current roles and current guardian relation. Shared-record reads require current record visibility and current grants; revocation cannot resurrect old grants. Parent reports and calendars redact private notes and exclude private items even from aggregates. Sensitive wellbeing/cycle APIs are closed by default; legal/consent/in-country-storage decisions are flags for later work. External AI/voice execution is disabled.

## Study and activity model

Reuse `plan_item`; add study sessions, non-overlapping intervals, activity-state events and an idempotency ledger. A session stores child/activity IDs, source, start/end, pause/resume intervals, status, recorded duration, version and last acknowledgement. Start/pause/resume/stop are explicit user actions. Duration is computed from accepted intervals; duplicate mutations and overlapping sessions do not count twice. Timer and self-reported records are clearly labelled as recorded information, never evidence of actual study.

Activity states planned/started/paused/completed/verified retain timestamp and source. Verification requires an authorized guardian's explicit confirmation after completion. Ending a study session does not silently complete the homework. Ordinary planner updates reconcile activity history; both planner and activity versions remain coherent.

## Client and synchronization

Web loads same-origin config.json without caching. Android stores validated HTTPS primary/alternate URLs in settings; switching server clears the old authentication scope and prevents replay to the new origin. Release identity is permanently `ir.lifeguide.app`; official release signing requires operator secrets and never falls back to debug signing. Release without those secrets is UNVERIFIED, not a release APK.

Session restoration uses persisted opaque refresh credentials, fresh server verification and refresh rotation. Offline cache and pending changes are scoped to server plus user. Authentication/permission/server/storage errors remain visible; only explicitly classified transport failures permit an offline cache view. Cache views show age and pending state.

The existing offline queue becomes serialized, durable and UUID-based. Mutation ID and entity ID are stable, persisted before send, and removed only after accepted/already-applied server acknowledgement. Retries reuse the exact payload; the server stores a canonical request hash and rejects changed-payload reuse. Updates use an expected record version. Conflicts keep the pending change visible for review; no silent last-writer-wins. Study events use the same durable storage with their separate server ledger. Polling refreshes shared data while the foreground app is active; no correctness depends on realtime or FCM.

PWA assets, CanvasKit and fonts are served locally. A network-first versioned app shell excludes API/auth/config responses from service-worker caches. Runtime request checks supplement built-output checks for external gstatic/googleapis dependencies. Real Safari installation and device trust are UNVERIFIED until tested on those devices.

## Acceptance evidence

Run synthetic HTTP/PostgreSQL tests for the eight-step child/mother/father scenario, independent DB checks, permission revocation, duplicate/concurrent mutations, pause/resume/restart and token/rate/delivery failures. Run Flutter unit/widget tests and browser substitutes over local HTTPS with independent child/parent sessions. Run Compose health, TLS, PWA, round-trip and synthetic backup/restore. Record exact commands, exit codes, artifacts and substitutions. A–H real Android/iPhone/Safari and inside-Iran reachability remain UNVERIFIED where hardware/location is unavailable. Green CI alone is not completion.

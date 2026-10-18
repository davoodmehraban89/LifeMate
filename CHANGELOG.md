# LifeGuide Changelog

## 0.7.2 — 2026-10-18 — نامزد آزمون برنامهٔ هفتگی (منتشرنشده)

- برنامهٔ خصوصی روزانه، روزدرمیان و هفتگی با ساعت مستقل هر روز، پایان صریح، نوبت‌های واقعی PostgreSQL و تیک/ویرایش مستقل.
- صف پایدار با شناسهٔ ثابت و بازیابی پیش‌نویس ردشده؛ خانهٔ کودک با قدم بعدی، کارهای امروز و پیشرفت به‌جای شش کارت تکراری.
- پورت اعلان محلی Android با مجوز اختیاری ساعت دقیق، حالت تقریبی، عنوان همراه قابل تنظیم و حذف اعلان‌های قدیمی هنگام تغییر/خروج.
- Backend0.7.2 و Flutter0.7.2+8؛ نصب واقعی، اعلان سیستم، ورود خصوصی کودک و بهره‌برداری آنلاین هنوز UNVERIFIED/مسدودند. هیچ merge/deploy/schema زنده اجرا نشد.

## Unreleased — approved Flutter mobile navigation

- Implement the owner-approved compact RTL home, separate child/adult menus and back navigation in the existing Flutter client; reuse real API-backed education/family/study/notification views.
- Open the selected task in a detail route; edit/complete/archive through existing durable PlanSync and distinguish pending data from server acknowledgement. Shared nonowner records remain read-only and are hidden on revocation/background.
- Preserve cached planner access during same-scope transport failures and refresh task versions after returning from study. No backend version/schema, domain or deployment changes; package remains0.7.1.
- [Verification and limitations](docs/ux/2026-10-16-flutter-navigation-implementation.md).

## Unreleased — synthetic child identity sandbox

- Add local-only managed child creation with required date of birth, explicit synthetic consent and creator/recipient guardian approval; no real-data or legal-consent approval.
- Bind parent-issued devices to restricted database scope and issuer, revoke prior devices on recovery and preserve restrictions through refresh. Deny private legacy routes and managed-child age/role upgrades.
- Add local migrations0024/0025 and real PostgreSQL authorization, concurrency, expiry and restricted-role regressions. Production remains disabled even with the sandbox flag.
- Backend package remains0.7.1; this is not a release. [Evidence and limits](docs/audits/2026-10-16-child-identity-sandbox.md).

## Unreleased — Phase 1 auth hardening

- Share auth/session IP quotas in PostgreSQL across processes and restart, storing domain-separated HMAC metadata rather than raw addresses; retain separate contact cooldowns.
- Recheck one-time token, refresh and OTP expiry after database lock waits with fresh wall time.
- Require explicit live-SMS and Kavenegar template approval flags; defaults remain disabled.
- Reject direct production server startup that bypasses shared security middleware. Preserve the existing 20 migration files and add local migration0023; no live schema or deployment changed.
- Verification and remaining Phase1 policy gates: [auth audit](docs/audits/2026-10-15-phase1-auth-hardening.md). Backend package version remains0.7.1; this is not a release.

## 0.7.1 — 2026-10-12 — shared-network session recovery

- Fix a real three-account PWA acceptance blocker: public auth capabilities no longer consume sensitive login/delivery attempts, and refresh/logout have a separate bounded session bucket.
- Keep strict sensitive-auth limits and trusted-proxy rules; near-match methods/paths remain strict. Add production-entrypoint PostgreSQL tests for shared-IP family rotation and rate-limit boundaries.
- The initial auth-only hotfix kept Flutter0.7.0+6. Follow-up client0.7.1+7 shows exact minute/second durations in parent totals, daily trends, subjects and tasks; zero and whole-minute labels stay compatible. Bound the daily label width for narrow RTL screens and update the public static cache version.
- Release signing, hardware/Safari/Iran access and real content review remain UNVERIFIED.

## 0.7.0 — 2026-10-12 — learning and family operations (test candidate)

- Preserve Feature 1 and the real shared backend; add owner-private goal mutation receipts, version conflicts, durable client retry and check-in/history UI.
- Add role/admin-transfer/invitation lifecycle with current authorization, atomic invalidation and age-aware safeguards; keep profile category independent of permissions.
- Add explicit school context/year/term editors and versioned lifecycle; preserve linked task/grade/class history when archived.
- Add owner-only quiz/review history and period-scoped parent metrics; clear stale or denied views and stabilize report source fingerprints.
- Add explicitly granted consented-feedback moderation and non-sensitive development briefs; withdrawals invalidate later reads/exports. No external AI, automatic messages or deployment.
- Add a dedicated local synthetic-only publication CLI with review/hash/version gates and immutable attempt history; all real teaching media and question banks remain DRAFT.
- Expose progress updates in Chromium accessibility semantics and add a public offline startup notice without caching API/auth/config or private data.
- Harden expired/revoked-session writes after database lock waits; expand real PostgreSQL/runtime-role acceptance.
- Real Android/Safari/Windows/Iran, full educational review, live hosting, owner release signing and complete product acceptance remain UNVERIFIED; see PROJECT_STATE.

## 0.6.0 — 2026-10-11 — reviewed learning infrastructure (test candidate)

- Preserve existing online family/planner/study and Feature 1; add grade/academic-track catalogue, deterministic unit IDs and repeatable metadata importer.
- Keep all 1348 researched videos DRAFT; require full edition, accuracy, suitability, rights and question-coverage review before learner exposure; reject stale review context.
- Add optional in-page Aparat player behind explicit loading, with isolated web/native navigation and lifecycle controls; no media rehosting or automatic completion.
- Add owner-private, versioned/idempotent progress and lesson-linked plans using real PostgreSQL; durable account-scoped queues and acknowledgement checks.
- Add reviewed/versioned quiz infrastructure, server grading and explanatory feedback, private attempts and pilot1/3-day review schedule. No real reviewed question bank or guaranteed mastery claim.
- Add consented educational feedback, persistent rate limits, withdrawal redaction and late-response guard; no private-chat extraction or external AI.
- Separate runtime read-only teaching catalogue from migrator/importer writes; future tables default read-only until explicit grants.
- Explain fresh-install Android server setup; preserve runtime URL/fallback configuration without inventing an approved public endpoint.
- Full video review, complete curriculum/exams, vocational tracks, Safari/Android device playback/install, public backend and owner-signed release remain UNVERIFIED or unimplemented; see PROJECT_STATE.

## 0.5.1 — 2026-10-09 — online isolation hardening

- Separate PostgreSQL bootstrap, migration, API and read-only backup credentials; reject excessive existing ownership/privileges before provisioning.
- Require explicit, backup-validated adoption of existing application objects; retain current migrations and server-side family permissions.
- Acquire an exclusive browser Web Lock before Flutter, session or cache startup; show a Persian retry screen for a second instance or unsupported browsers.
- Preserve account-scoped unsent mutations on forced session expiry; invalidate stale handles and recover only after the same account authenticates again. Deliberate logout/server switch retains its discard policy.
- Add real PostgreSQL role/restore and compiled Chromium regressions to CI, plus inspection of the actual debug APK manifest/signature.
- Preserve LF text and binary bytes across Windows Git checkouts; test the existing checked web artifact, executable shell inputs and tamper rejection without restamping it.
- Require verified TLS explicitly in the reachability smoke script, including when an inherited Node environment requests insecure TLS; reject invalid trust/hostname before login or writes.
- Record the read-only public-domain audit: old0.1.0/build1 remains on app.lifeguide.ir; owner-PC/mobile acceptance waits until PC/LAN access is available.
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

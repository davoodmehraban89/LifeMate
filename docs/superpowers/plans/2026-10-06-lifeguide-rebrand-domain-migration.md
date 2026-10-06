# LifeGuide Rebrand & Domain Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand the existing LifeMate release candidate to LifeGuide, move public identity to lifeguide.ir, isolate transactional email, and preserve the working shared backend/database.

**Architecture:** Keep the existing repository, backend, database schema, and Railway staging services. Change user-facing brand/configuration in reversible steps, then attach LifeGuide-owned domains and email identity, followed by CI and end-to-end smoke tests.

**Tech Stack:** Flutter/Dart, Android, Flutter Web/PWA, Node.js/Express, PostgreSQL, Railway, Resend, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-06-lifeguide-rebrand-domain-migration-design.md`

## Global Constraints

- Canonical product name: `LifeGuide`.
- Primary owned domain: `lifeguide.ir`.
- PWA target: `https://app.lifeguide.ir`.
- API target: `https://api.lifeguide.ir`.
- Transactional sender: `LifeGuide <no-reply@lifeguide.ir>`.
- Do not alter Factoreasy or any unrelated project's DNS, domains, API keys, senders, or services.
- Do not reset the database or rename historical schema solely for branding.
- Keep Railway-generated domains as rollback endpoints until custom-domain validation completes.
- No secrets in repository or documentation.

## Review Focus

- Old `LifeMate` strings remain in active user-facing flows: repository audit must distinguish harmless historical/internal identifiers from visible brand copy.
- Password shorter than 10 characters: registration must reject locally with the exact Persian guidance before calling the API.
- Successful registration: user must see an explicit instruction to check email and activate the account.
- Email provider failure: UI/backend must not falsely claim delivery when the provider rejects the message.
- Cross-project contamination: runtime configuration must contain no Factoreasy sender/domain/API key references.

---

### Task 1: Audit and branch the rebrand

**Files:**
- Inspect: `apps/lifemate/**`
- Inspect: `backend/**`
- Inspect: `README.md`, `PROJECT_STATE.md`, `docs/**`

**Interfaces:**
- Consumes: approved rebrand spec.
- Produces: exact list of active brand/configuration files and a dedicated implementation branch.

- [ ] Create a rebrand branch from current `main`.
- [ ] Search active source/configuration for `LifeMate`, `lifemate`, `com.example.lifemate`, current public URLs, and email sender configuration.
- [ ] Classify each match as user-facing, protocol-sensitive, historical documentation, or safe internal identifier.
- [ ] Confirm no planned edit touches unrelated project resources.

### Task 2: Fix registration UX and brand-facing Flutter UI

**Files:**
- Modify: `apps/lifemate/lib/main.dart`
- Test: `apps/lifemate/test/app_test.dart`

**Interfaces:**
- Produces: LifeGuide visible brand, 10-character password validation, and post-registration email instruction.

- [ ] Add/repair widget tests asserting `LifeGuide`, `حداقل ۱۰ کاراکتر`, and the successful-registration check-email instruction.
- [ ] Verify tests fail before implementation.
- [ ] Replace active user-facing LifeMate branding with LifeGuide and implement local password validation.
- [ ] Make successful registration show a clear activation-email instruction rather than a generic result.
- [ ] Run Flutter tests and confirm pass.

### Task 3: Rebrand PWA and Android release metadata

**Files:**
- Modify: `apps/lifemate/web/index.html`
- Modify: `apps/lifemate/web/manifest.json`
- Modify: Android app manifest/Gradle files discovered by audit.
- Modify: deployment/build files that name the APK.

**Interfaces:**
- Produces: LifeGuide PWA metadata, Android label, production-safe application ID, and `LifeGuide.apk` artifact path.

- [ ] Add static/config checks for LifeGuide PWA title/name and Android application ID/label.
- [ ] Update PWA metadata to LifeGuide.
- [ ] Change Android user-facing label to LifeGuide.
- [ ] Replace `com.example.lifemate` with the approved stable identifier `ir.lifeguide.app` if audit confirms no conflicting package structure requirement.
- [ ] Change stable APK artifact naming to `LifeGuide.apk` and `/downloads/LifeGuide.apk`.
- [ ] Run Flutter analyze/test/web build/APK build through CI.

### Task 4: Rebrand backend email copy without protocol breakage

**Files:**
- Modify: backend source files containing transactional email copy.
- Test: corresponding backend auth/email tests.

**Interfaces:**
- Produces: LifeGuide verification/reset/invitation copy while retaining compatible database/JWT internals unless explicitly safe to change.

- [ ] Add backend tests asserting LifeGuide transactional subjects/body copy.
- [ ] Verify tests fail before implementation.
- [ ] Replace user-visible email copy with LifeGuide.
- [ ] Do not rename JWT issuer/audience or schema identifiers merely for appearance.
- [ ] Run backend tests.

### Task 5: Configure LifeGuide domain and email isolation

**Files:**
- Runtime configuration only; no secrets committed.

**Interfaces:**
- Consumes: Railway domain targets and Resend DNS records.
- Produces: verified `app.lifeguide.ir`, `api.lifeguide.ir`, and `no-reply@lifeguide.ir` sender configuration.

- [ ] Generate/attach Railway custom-domain targets for app and API without deleting current Railway domains.
- [ ] Add `lifeguide.ir` to Resend and obtain exact DNS verification records.
- [ ] Ask the domain owner only for DNS changes that cannot be performed with available connectors.
- [ ] Verify DNS/domain status before switching runtime URLs.
- [ ] Create/use a LifeGuide-only restricted Resend sending key; do not reuse unrelated-domain credentials.
- [ ] Set `EMAIL_FROM=LifeGuide <no-reply@lifeguide.ir>` only after domain verification.
- [ ] Set `PUBLIC_APP_URL` and CORS to approved LifeGuide origins while retaining necessary staging rollback origin during migration.
- [ ] Audit runtime variables for unrelated project domain/sender references.

### Task 6: Update documentation and release identity

**Files:**
- Modify: `README.md`
- Modify: `PROJECT_STATE.md`
- Modify: active release/operations docs as discovered by audit.

**Interfaces:**
- Produces: current documentation that names LifeGuide and records remaining historical/internal LifeMate identifiers intentionally retained.

- [ ] Update current product/release documentation to LifeGuide.
- [ ] Record the domain layout and rollback endpoints without secrets.
- [ ] Document intentionally retained internal/historical identifiers.

### Task 7: CI, deploy, and end-to-end verification

**Files:**
- CI/workflow files only if required by changed artifact names/configuration.

**Interfaces:**
- Consumes: Tasks 2-6.
- Produces: green CI, deployed LifeGuide PWA/API, stable LifeGuide APK, and documented smoke-test evidence.

- [ ] Run required GitHub Actions checks and resolve failures before merge.
- [ ] Deploy backend/PWA changes on Railway.
- [ ] Verify `https://app.lifeguide.ir` and `https://api.lifeguide.ir` over HTTPS.
- [ ] Verify PWA and Android connect to the same API/database.
- [ ] Execute registration with >10-character password and confirm real verification email reaches an external inbox.
- [ ] Verify email activation then login.
- [ ] Verify forgot/reset password and family invitation email paths.
- [ ] Smoke-test profile, family creation, parent/child relationship, planner, education profile, calendar, logout/session behavior.
- [ ] Confirm `/downloads/LifeGuide.apk` is stable and not a temporary Actions artifact.
- [ ] Re-audit active runtime/source for Factoreasy references and unresolved user-facing LifeMate branding.
- [ ] Merge only after CI and required release-candidate checks pass.

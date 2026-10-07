# Personalized Profile Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the test APK profile entry and persistence model, establish explicit girl-minor/boy-minor/adult profile context, and add privacy-safe foundations for relevant health and guidance personalization.

**Architecture:** Keep family authorization roles independent from profile category. The test-only role-entry app uses local persistent profile state and routes both minor categories to the student shell and adults to the adult shell. Production PostgreSQL gains an explicit profile category plus dedicated private health-cycle storage; guidance consumes minimized profile context rather than gender stereotypes.

**Tech Stack:** Flutter/Dart, shared_preferences, Node.js/Express, PostgreSQL, node:test.

**Spec:** `docs/superpowers/specs/2026-10-07-personalized-profile-guidance-design.md`

## Global Constraints
- First-run choices are exactly «فرزند دختر»، «فرزند پسر»، «بزرگسال».
- Display name is independent from profile category and must persist.
- `member_role` remains the authorization model and is not repurposed for girl/boy.
- Menstrual-cycle functionality is explicit opt-in and private by default.
- Guidance must not infer temperament/interests/ability from sex/profile category.
- Existing child wellbeing privacy boundaries remain intact.
- Security-bypassed entrypoint remains test-only.

## Review Focus
- Empty/whitespace display names must not replace a valid persisted name.
- Restarting the test app must restore category/name rather than returning to generic «فرزند».
- Changing category must not silently delete existing profile/health data.
- Adult/minor shell routing must not depend on whether a family has already been created.
- Sensitive cycle records must not leak through guardian/family summary endpoints.

---

### Task 1: Persistent test profile and corrected first-run choices

**Files:**
- Modify: `apps/lifemate/pubspec.yaml`
- Create: `apps/lifemate/lib/local_test_profile.dart`
- Modify: `apps/lifemate/lib/role_entry_main.dart`
- Modify: `apps/lifemate/test/role_entry_test.dart`

**Interfaces:**
- Produces: `LocalTestProfileStore.load/save`, profile category values `girl_minor|boy_minor|adult`, mutable display name.
- Consumes: existing `HomeShell` and `IdentityApi`.

- [ ] Write widget/unit tests proving the three exact choices, name entry/edit, persistence after recreation, and empty-name rejection.
- [ ] Run `flutter test test/role_entry_test.dart` and verify RED for missing persistence/new choices.
- [ ] Add `shared_preferences` and implement local test profile persistence.
- [ ] Refactor `LocalRoleTestApi` so `getProfile()` reflects persisted edits and category-specific theme defaults.
- [ ] Run the focused Flutter test and verify GREEN.
- [ ] Commit.

### Task 2: Shell routing independent of family creation

**Files:**
- Modify: `apps/lifemate/lib/main.dart`
- Modify: `apps/lifemate/lib/role_entry_main.dart`
- Test: `apps/lifemate/test/role_entry_test.dart`

**Interfaces:**
- Consumes: profile category from Task 1.
- Produces: explicit shell-mode/profile-category signal used by `HomeShell`.

- [ ] Add tests proving both minor categories receive student navigation and adult receives adult navigation before any family exists.
- [ ] Run focused test and verify RED.
- [ ] Add explicit shell context to `HomeShell`; retain family membership only for authorization/family features.
- [ ] Run focused test and verify GREEN.
- [ ] Commit.

### Task 3: Editable profile UI

**Files:**
- Modify: `apps/lifemate/lib/main.dart`
- Test: `apps/lifemate/test/role_entry_test.dart`

**Interfaces:**
- Consumes: `IdentityApi.getProfile/updateProfile`.
- Produces: profile page that edits display name and refreshes visible profile state.

- [ ] Add widget test setting display name to «آرام», navigating away/back, and confirming «آرام» remains.
- [ ] Run focused test and verify RED.
- [ ] Implement profile editor in the shell/profile area with validation and refresh.
- [ ] Run focused test and verify GREEN.
- [ ] Commit.

### Task 4: Production profile-category schema and API

**Files:**
- Create: `backend/migrations/0007_profile_personalization.sql`
- Modify: `backend/src/server.js`
- Modify: `backend/tests/api.test.js`
- Modify: `backend/tests/schema_test.sql`

**Interfaces:**
- Produces: `profile.profile_category` constrained to `girl_minor|boy_minor|adult`; GET/PATCH profile support.
- Consumes: existing profile API and family roles unchanged.

- [ ] Add schema/API tests for category values, updates, and independence from family role.
- [ ] Run backend tests/schema test and verify RED.
- [ ] Add migration and API handling without deriving authorization from category.
- [ ] Run backend tests/schema test and verify GREEN.
- [ ] Commit.

### Task 5: Private opt-in cycle data foundation

**Files:**
- Modify: `backend/migrations/0007_profile_personalization.sql`
- Create: `backend/src/health.js`
- Modify: `backend/src/server.js`
- Create: `backend/tests/health.test.js`
- Modify: `backend/tests/schema_test.sql`

**Interfaces:**
- Produces: owner-authenticated cycle settings/records API; private-by-default storage.
- Consumes: authenticated user identity and profile category.

- [ ] Add tests for explicit opt-in, owner access, disabled-state gating, and guardian/family non-access.
- [ ] Run health/schema tests and verify RED.
- [ ] Implement minimal owner-only health-cycle endpoints and tables.
- [ ] Run health/schema tests and verify GREEN.
- [ ] Commit.

### Task 6: Guidance context minimization

**Files:**
- Modify: `backend/src/phase4.js`
- Modify: `backend/tests/phase4.test.js`

**Interfaces:**
- Consumes: profile category/age and explicit health opt-in only when relevant.
- Produces: minimized guidance context with no stereotype-based rules.

- [ ] Add tests proving profile category does not hard-code personality/advice and private health context is omitted unless explicitly relevant/enabled.
- [ ] Run phase-4 tests and verify RED.
- [ ] Implement context builder with allowlisted fields.
- [ ] Run phase-4 tests and verify GREEN.
- [ ] Commit.

### Task 7: Full review, regression verification, and APK build

**Files:**
- Modify only if RED→GREEN fixes are required.
- Update: `PROJECT_STATE.md` if present.

**Interfaces:**
- Consumes: Tasks 1–6.
- Produces: verified test APK and review findings.

- [ ] Run full Flutter tests.
- [ ] Run full backend tests and schema checks.
- [ ] Build release APK with `flutter build apk --release --target=lib/role_entry_main.dart`.
- [ ] Review role entry, name persistence, routing, privacy boundaries, RTL/copy, mock/incomplete paths.
- [ ] Fix Critical/Important findings using RED→GREEN tests.
- [ ] Record verified state and commit.

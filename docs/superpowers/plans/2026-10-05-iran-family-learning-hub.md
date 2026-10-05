# Feature 1 — Iranian Family & Learning Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the final owner-testable Iranian family, education, Jalali calendar, reminder-preference and private cycle-tracking feature set.

**Architecture:** Extend the existing phase-based backend with `0005` + `phase6.js`, expose a compact API client surface, and add a focused Flutter hub without restructuring earlier phases. Preserve existing authorization as the security authority.

**Tech Stack:** PostgreSQL, Node/Express, Flutter/Dart, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-05-iran-family-learning-hub-design.md`

## Global Constraints
- No public production deployment.
- No copyrighted textbook PDF binaries committed without verified redistribution rights.
- Menstrual entries owner-only.
- Persona metadata never grants authorization.
- Jalali week begins Saturday for Iranian locale.

## Review Focus
- Guardian attempting to read private cycle data must have no route/capability.
- Invalid grade/stage combinations must be rejected.
- Grade 7 must map to secondary first cycle, local year 1.
- Sensitive notification preview defaults off.
- External textbook URLs must be trusted HTTPS sources.

---

### Task 1: Red-first contracts
**Files:** create `backend/tests/phase6_contract.test.js`, `backend/tests/phase6_schema_test.sql`; create Flutter pure-model tests.
- [ ] Add failing contract/schema tests for required files/tables/guardrails.
- [ ] Push and observe CI failure before implementation.

### Task 2: Data model and seed catalog
**Files:** create `backend/migrations/0005_iran_family_learning.sql`.
- [ ] Add persona, education profile, curriculum/textbook, official calendar, notification preference and cycle tables.
- [ ] Seed stage/grade mapping and Grade 7 curriculum metadata.
- [ ] Run migration/schema gates.

### Task 3: API
**Files:** create `backend/src/phase6.js`; modify `backend/src/server.js`.
- [ ] Implement authenticated owner/guardian-safe profile APIs.
- [ ] Implement catalog/calendar/preferences APIs.
- [ ] Implement owner-only cycle CRUD/list API.
- [ ] Run backend tests and syntax checks.

### Task 4: Flutter integration
**Files:** create `apps/lifemate/lib/iran_hub.dart`; modify `api.dart`, `phase3_ui.dart`, navigation as required.
- [ ] Add education/persona setup.
- [ ] Add Jalali-first calendar/event view.
- [ ] Add textbook/catalog view using official metadata links.
- [ ] Add notification settings and private cycle tracker.
- [ ] Run format/analyze/widget tests.

### Task 5: Release outputs
**Files:** modify `.github/workflows/ci.yml`, release docs/state.
- [ ] Retain Web release bundle and Android APK as CI artifacts.
- [ ] Document iOS signing gate and build command.
- [ ] Run full CI and verify all jobs.
- [ ] Open PR, review diff/security, merge only after green CI.
- [ ] Verify post-merge main CI.
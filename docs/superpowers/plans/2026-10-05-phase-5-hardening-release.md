# Phase 5 Hardening & Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden LifeMate operationally and make the existing Android/Web/PWA/API stack release-ready without performing a production release.

**Architecture:** Preserve the current Flutter + Node/Express + PostgreSQL architecture. Add focused backend middleware, CI restore verification and operational documentation; keep production-sensitive AI/voice gates disabled.

**Tech Stack:** Node 22, Express 5, PostgreSQL, Flutter, GitHub Actions, Railway staging.

**Spec:** `docs/superpowers/specs/2026-10-05-phase-5-hardening-release-design.md`

## Global Constraints
- No production deploy/public release without explicit approval.
- Never log secrets, auth headers, passwords, wellbeing notes or AI transcripts.
- General rate limit default 120/min/IP; auth 10/10min/IP; AI 30/10min/identity-or-IP.
- `/live` is process-only; `/ready` verifies database connectivity; `/health` remains compatible.
- Existing Phase 1–4 behavior and tests must remain green.

## Review Focus
- Proxy/IP handling must not let a caller trivially bypass limits.
- Rate limiting must not break test suites or CORS preflight.
- Error logging must not serialize request bodies or credentials.
- Readiness must return non-2xx when PostgreSQL is unavailable.
- Backup/restore drill must prove data, not merely schema creation.

---

### Task 1: Backend hardening middleware
**Files:** create `backend/src/operations.js`; create `backend/tests/operations.test.js`; modify `backend/src/server.js`; modify `backend/package.json`.
**Produces:** request correlation, security headers, JSON telemetry, `/live`, `/ready`, and configurable rate limiting.
- [ ] Add failing operations tests for headers/request ID/rate limits/readiness/log redaction.
- [ ] Verify CI failure on tests before implementation.
- [ ] Implement minimal operations middleware and wire it into server.
- [ ] Run backend tests/check/audit to green.

### Task 2: Backup/restore drill
**Files:** create `backend/scripts/backup.sh`; create `backend/scripts/restore.sh`; create `backend/scripts/restore-smoke.sql`; modify `.github/workflows/ci.yml`.
**Produces:** repeatable native PostgreSQL backup/restore commands and CI data round-trip gate.
- [ ] Add CI restore-drill gate that fails until scripts exist.
- [ ] Implement scripts and representative smoke data assertion.
- [ ] Verify CI restore drill green.

### Task 3: Release/incident operations documentation
**Files:** create `docs/operations/DEPLOYMENT.md`, `ROLLBACK.md`, `BACKUP_RESTORE.md`, `INCIDENT_RESPONSE.md`, `PRODUCTION_CHECKLIST.md`; create `CHANGELOG.md`; modify `README.md` as needed.
**Produces:** executable runbooks and release gates.
- [ ] Add contract test asserting required runbooks and mandatory safety clauses.
- [ ] Implement runbooks and changelog.
- [ ] Verify contract test green.

### Task 4: Cross-platform release regression gates
**Files:** modify `.github/workflows/ci.yml`; add/modify Flutter tests only where needed.
**Produces:** format/analyze/test + Web release + Android debug/release-safe build metadata + PWA manifest/accessibility smoke gates.
- [ ] Add failing contract assertions for release metadata/PWA accessibility requirements.
- [ ] Implement minimal manifest/index/release checks.
- [ ] Verify Flutter/Web/Android CI green.

### Task 5: Staging verification and project-state closeout
**Files:** update `PROJECT_STATE.md`; update Phase 5 design/decision docs if rulings occur.
**Produces:** verified staging evidence and accurate completion record.
- [ ] Deploy only to staging using existing Railway services.
- [ ] Verify migration/API `/live`, `/ready`, `/health` and logs.
- [ ] Verify final branch CI completely green.
- [ ] Record exact verification evidence in `PROJECT_STATE.md`.
- [ ] Open PR for review; do not merge or deploy production without explicit approval.

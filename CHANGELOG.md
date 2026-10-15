# Changelog

## Unreleased — Phase 1 repository cleanup
- Aligned current entry documents with the final LifeGuide / لایف‌گاید name and the completed Phase 0 audit; online/device acceptance remains unverified.
- Removed the obsolete branch-specific self-committing unused-variable workflow.
- Assigned the frontend ADR a date-based identifier to resolve duplicate ADR 0004, preserving the decision and historical backend ADRs.
- This documentation/workflow cleanup does not change the backend version, runtime, database, hosting or public site.

## 0.4.0 — Existing backend baseline
- Matches `backend/package.json` on the audited main baseline; this heading is not a new release or deployment.
- Existing Feature 1 includes Iranian family/education settings, textbook catalog metadata, the 1405 calendar and notification preferences. Audit findings and current safety gates limit release readiness.

## 0.3.0 — Phase 5 candidate
- Added production-entrypoint request correlation, privacy-safe structured HTTP telemetry and security headers.
- Added configurable general/auth/AI rate limiting with `Retry-After` responses.
- Added separate liveness and database-readiness probes.
- Added PostgreSQL backup/restore scripts and automated CI restore drill.
- Strengthened PWA RTL/iOS install metadata and release checks.
- Added deployment, rollback, backup/restore, incident-response and production-readiness runbooks.

## 0.2.0 — Phase 4
- Added learning goals/check-ins, wellbeing check-ins, advisory AI guides, explicit plan proposals, guardian summaries and privacy-preserving family guidance.

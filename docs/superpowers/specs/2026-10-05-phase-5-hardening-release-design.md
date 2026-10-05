# Phase 5 — Hardening, Observability & Release Design

Status: Approved by Phase 5 start instruction on 2026-10-05.

## Goal
Make the existing LifeMate Android + Web/PWA + Node/PostgreSQL system operationally safe and release-ready without expanding the product scope or enabling public production exposure of minor-sensitive wellbeing AI.

## Scope
1. Backend operational hardening: request IDs, structured logs, security headers, bounded request body, rate limiting for auth/AI/general API traffic, and explicit readiness/liveness endpoints.
2. Observability: privacy-safe request/error telemetry and documented alert signals. No wellbeing note, AI transcript, password, token, authorization header, or secret may be logged.
3. Data resilience: documented PostgreSQL backup/restore procedure and a CI-verifiable restore drill using migrations plus representative data.
4. Regression gates: backend integration/contract tests, dependency audit, Flutter format/analyze/tests, Android build, Web/PWA release build, accessibility/RTL smoke assertions, and release metadata checks.
5. Release operations: staging verification, version/changelog discipline, deployment/rollback/runbooks, environment variable inventory, and production checklist.

## Non-goals / production gates
- No production deploy or public release in this phase without a separate explicit approval.
- No destructive production migration.
- No activation of an external AI provider for minor-sensitive wellbeing data until the existing legal/privacy/provider gates pass.
- No voice-provider activation until privacy review passes.

## Architecture
Keep the current provider-neutral Node/Express API and PostgreSQL. Add a small in-process hardening layer with no new infrastructure dependency: request correlation, structured JSON logging, security headers and memory-bounded fixed-window rate limiting suitable for the current single-instance staging footprint. Document that multi-instance production must move the limiter to shared storage before horizontal scaling.

Expose `/live` for process liveness and `/ready` for database readiness; retain `/health` for compatibility. Logs are JSON lines with requestId, method, route/path, status, durationMs and error class only. Sensitive request/response bodies are never logged.

Backups use PostgreSQL-native `pg_dump`/`pg_restore`. CI performs a restore drill against an ephemeral PostgreSQL service to prove the documented commands and schema/data round-trip. Production backup scheduling remains a hosting operation and is not silently enabled.

## Rate limits
Defaults are configurable by environment. General API: 120 requests/minute/IP. Auth-sensitive endpoints: 10 requests/10 minutes/IP. AI message/family-guidance endpoints: 30 requests/10 minutes/identity-or-IP. Responses use HTTP 429 with `Retry-After` and `{error:"rate_limited"}`.

## Acceptance criteria
- Existing Phase 1–4 tests stay green.
- New hardening tests prove request IDs, security headers, readiness semantics, structured error behavior and rate-limit rejection.
- No sensitive values are emitted by telemetry tests.
- CI includes an automated PostgreSQL backup/restore drill.
- Flutter/Web/PWA and Android build gates remain green.
- Operational runbooks exist for deploy, rollback, backup/restore, incident response and production release.
- Staging health/readiness are verified after deployment.
- `PROJECT_STATE.md` records Phase 5 completion only after all automated gates and staging checks pass.

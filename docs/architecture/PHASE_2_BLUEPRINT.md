# LifeMate — Phase 2 Implementation Blueprint

## Repository structure
```text
apps/lifemate/                 Flutter application (Android + Web/PWA)
  lib/
    app/                       bootstrap, routing, theme, localization
    features/auth/
    features/profile/
    features/family/
    shared/
  web/                         manifest, icons, PWA integration
  test/
backend/
  migrations/                 standard PostgreSQL schema + constraints/policies
  tests/                      authorization/database tests
  README.md                   API/identity adapter contract
docs/                         product, UX, architecture, safety, quality, decisions
.github/workflows/             CI and staging verification
```

## Architecture style
Feature-oriented Flutter modules behind application repositories. Flutter never receives privileged database credentials. A server/API boundary owns identity-session validation and relationship-aware authorization. PostgreSQL is the durable relational source of truth. Managed database, identity, email, storage and realtime providers are adapters rather than domain dependencies.

## Environments
At minimum: **local**, **staging**, **production**. Staging and production use separate database credentials/data. Environment-specific public API configuration is injected at build/deploy; privileged credentials exist only in server/CI secret stores. Real `.env` files are never committed.

## Phase 2 vertical slice
1. App shell + Persian RTL + role/profile-aware theme.
2. Email/password auth contract + verification/recovery/change-password UX.
3. Profile creation/editing.
4. Family Workspace + invitation + membership.
5. Guardian relationship and baseline server authorization contract.
6. Teen/Parent authenticated home shells.
7. CI and isolated PostgreSQL staging smoke.

## Student navigation baseline
MyStudyLife is the primary information-architecture benchmark for the student surface. Direct destinations remain visible for Today, Schedule, Calendar, Tasks, Exams/Grades, Focus and AI; LifeMate Family/Wellbeing extensions are additive rather than hiding these core destinations behind a generic School layer.

## PWA integration
Own `manifest.json`, branded icons/apple-touch-icon, standalone metadata, install guidance and explicit service-worker strategy. Push is capability-detected and is not required for Phase 2 identity acceptance.

## Configuration rule
Any credential that can read another user's private data, administer identity, send privileged email, or bypass authorization is server-only.

## Migration rule
Schema, constraints and authorization-relevant database changes travel together in versioned PostgreSQL migrations and tests. Destructive migrations require explicit approval and rollback/backup consideration.

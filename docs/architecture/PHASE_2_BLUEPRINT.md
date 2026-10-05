# LifeMate — Phase 2 Implementation Blueprint

## Proposed repository structure
```text
apps/lifemate/                 Flutter application (Android + Web/PWA)
  lib/
    app/                       bootstrap, routing, theme, localization
    features/auth/
    features/profile/
    features/family/
    shared/                    reusable UI/domain utilities with strict scope
  web/                         manifest, icons, bootstrap, custom SW/web integration
  test/
supabase/
  migrations/                 versioned schema + grants + RLS
  functions/                  privileged server workflows; no client secrets
  tests/                      database/RLS allow+deny tests
docs/                         product, UX, architecture, safety, quality, decisions
.github/workflows/             CI after scaffold
```

## Architecture style
Feature-oriented Flutter modules with domain/service boundaries; avoid a giant shared layer. UI may validate and cache, but backend policies are authoritative for permissions. Supabase is accessed through repository/service interfaces so AI/provider logic and complex privileged workflows remain server-side.

## Environments
At minimum: **local**, **staging**, **production**. Staging and production use separate Supabase projects/secrets/data. Environment-specific public configuration is injected at build/deploy; secrets/service-role/provider keys exist only in server secret stores. `.env` with real credentials is never committed.

## Phase 2 first vertical slice
1. App shell + localization/RTL + theme.
2. Email/password auth + verification/recovery/change-password.
3. Profile creation.
4. Family Workspace + invitation + membership.
5. Guardian relationship and baseline permission enforcement.
6. Teen/Parent authenticated home shells.
7. CI and staging smoke.

This slice deliberately proves identity and authorization before planner/school data expands the schema.

## PWA integration
Own `manifest.json`, icons/apple-touch-icon, standalone metadata, install guidance and custom service-worker strategy. Push subscription is capability-detected and implemented only after the core auth/family slice is stable.

## Configuration rule
Public client identifiers are separated from secrets. Any credential that bypasses RLS or accesses AI/email/push provider privileged APIs is server-only.

## Migration rule
Schema/grant/RLS changes travel together in versioned migrations and include database tests. Destructive migrations require explicit approval and rollback/backup consideration.
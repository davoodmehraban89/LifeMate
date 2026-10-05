# Phase 2 — Product Foundation & Identity Implementation Plan

Status: IN PROGRESS

## Acceptance contract
Phase 2 is complete only when a real Flutter Android/Web-PWA scaffold exists; email/password auth supports verification, recovery and password change; profiles and family workspaces exist; invitations and guardian relationships are server-authorized; RTL/theme shells exist for teen/parent; CI builds/tests Android and Web; and a separate staging PostgreSQL backend has been exercised.

## Architecture revision
Supabase is no longer a required platform dependency. LifeMate uses provider-neutral backend ports with PostgreSQL as the durable relational core. Neon is the preferred managed PostgreSQL target when its connector is operational, but application/domain code must not depend on Neon-specific APIs.

Provider boundaries:
- Database: PostgreSQL 17-compatible SQL; managed target may be Neon.
- Authorization: server-side policy/service layer backed by relational membership/guardian grants; PostgreSQL RLS may provide defense in depth where supported.
- Authentication: `IdentityProvider` port; provider implementation can be changed without altering domain entities.
- Object storage: `ObjectStorage` port; not required for Phase 2 identity acceptance.
- Email: `TransactionalEmail` port for verification/recovery/invitations.
- Realtime: optional adapter; no Phase 2 domain rule depends on realtime delivery.

## Execution order
1. Scaffold Flutter app and platform assets.
2. RED tests for role/theme/auth/family domain behavior, then minimal GREEN implementation.
3. Add provider-neutral client repositories for auth/profile/family flows.
4. Add versioned PostgreSQL schema, constraints, authorization policy tests and optional RLS defense-in-depth policies.
5. Add authentication UI: sign-in/up, verification state, forgot/reset/change password.
6. Add profile + family workspace + invitation + membership/guardian UI.
7. Add Persian RTL authenticated Teen/Parent shells and MyStudyLife-inspired direct student navigation.
8. Add CI: format, analyze, tests, Android debug build, Web build, secret scan.
9. Attach an isolated staging PostgreSQL environment, apply migrations, run authorization/smoke tests.
10. Verify branch, update PROJECT_STATE, PR review and merge only after green evidence.

## Product rulings carried into implementation
- Student IA uses MyStudyLife as benchmark: direct access to Today, Schedule, Calendar, Tasks, Exams/Grades, Focus and AI; LifeMate family/wellbeing extensions remain additive.
- Theme defaults: girl/teen profile white + soft pink; boy/teen white + blue; parent/adult white + blue. Theme remains user-overridable later.
- Admin ownership never implies blanket access to private teen content.
- No wellbeing/AI production exposure in Phase 2.

## Environment rule
Local, staging and production are distinct. Staging must not reuse Finora/EasyFactor infrastructure. The codebase must remain deployable to standard PostgreSQL even if a managed-provider connector is temporarily unavailable.

# Phase 2 — Product Foundation & Identity Implementation Plan

Status: IN PROGRESS

## Acceptance contract
Phase 2 is complete only when a real Flutter Android/Web-PWA scaffold exists; email/password auth supports verification, recovery and password change; profiles and family workspaces exist; invitations and guardian relationships are server-authorized; RTL/theme shells exist for teen/parent; CI builds/tests Android and Web; and a separate staging backend has been exercised.

## Execution order
1. Scaffold Flutter app and platform assets.
2. RED tests for role/theme/auth/family domain behavior, then minimal GREEN implementation.
3. Add Supabase client repositories for auth/profile/family flows.
4. Add versioned SQL schema, RLS and allow/deny tests.
5. Add authentication UI: sign-in/up, verification state, forgot/reset/change password.
6. Add profile + family workspace + invitation + membership/guardian UI.
7. Add Persian RTL authenticated Teen/Parent shells and MyStudyLife-inspired direct student navigation.
8. Add CI: format, analyze, tests, Android debug build, Web build, secret scan.
9. Provision/attach isolated staging Supabase, apply migrations, run RLS/smoke/advisors.
10. Verify branch, update PROJECT_STATE, PR review and merge only after green evidence.

## Product rulings carried into implementation
- Student IA uses MyStudyLife as benchmark: direct access to Today, Schedule, Calendar, Tasks, Exams/Grades, Focus and AI; LifeMate family/wellbeing extensions remain additive.
- Theme defaults: girl/teen profile white + soft pink; boy/teen white + blue; parent/adult white + blue. Theme remains user-overridable later.
- Admin ownership never implies blanket access to private teen content.
- No wellbeing/AI production exposure in Phase 2.

## Environment rule
Local, staging and production are distinct. Staging must not reuse Finora/EasyFactor projects. Creating a new Supabase project is an external cost action and therefore requires its required cost confirmation; until that gate is available, code/config must remain deploy-ready but Phase 2 cannot be truthfully marked COMPLETE.

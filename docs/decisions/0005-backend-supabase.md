# ADR-0005 — Backend/Auth Baseline: Supabase

- **Status:** Accepted for Phase 2 baseline
- **Date:** 2026-10-05

## Decision
Use **Supabase** as the initial backend platform: PostgreSQL + Supabase Auth + Row Level Security, with Edge Functions/server-side code for privileged workflows, AI orchestration and secrets.

## Why
LifeMate needs relational family/guardian/resource relationships, granular authorization and email/password recovery. Supabase Auth integrates JWT identity with PostgreSQL RLS, allowing authorization to remain consistent across Android and Web/PWA clients.

## Security contract
- Enable RLS on every exposed application table.
- Explicitly set grants and separate policies by operation; do not assume RLS alone removes broad grants.
- Test allow and deny paths for authorization policies.
- Publishable client key may exist in clients; service-role/secret keys never do.
- Privileged AI/provider calls, invitation administration and sensitive safety workflows execute server-side.
- Views/functions must be reviewed for RLS/security-definer behavior before exposure.

## Auth baseline
Email/password with email verification, non-enumerating forgot-password response, time-limited recovery flow, authenticated password change and controlled redirect URLs. Custom SMTP/provider selection is an operational Phase 2 task, not a reason to build custom authentication.

## Alternatives considered
Custom API/Postgres would provide full control but adds auth/security/operations work before core product value. Firebase simplifies some mobile flows but the relational authorization model is a less direct fit for family/guardian/resource policy. Supabase remains replaceable behind domain/service boundaries if later scale or compliance requirements justify migration.
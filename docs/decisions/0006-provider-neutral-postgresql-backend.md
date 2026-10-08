# ADR-0006 — Provider-neutral PostgreSQL Backend

- **Status:** Superseded hosting recommendation; PostgreSQL/adapter invariants retained
- **Superseded by:** [ADR-0009](0009-provider-neutral-hosting.md) for hosting
- **Date:** 2026-10-05
- **Supersedes:** any Phase 2 assumption that Supabase is a mandatory backend platform

## Context
Phase 2 originally treated Supabase as the likely combined database/auth/backend provider. Creation of an isolated LifeMate staging project was blocked by account-level project limits. More importantly, tying identity, authorization, storage, realtime and database behavior to one BaaS creates unnecessary platform coupling for a long-lived family product.

## Decision
LifeMate will use PostgreSQL as its durable relational source of truth while exposing infrastructure through explicit application ports/adapters.

The managed PostgreSQL host is replaceable. The former Neon preference is historical. The active target is self-hosted PostgreSQL in the same provider-neutral Compose package as the API and PWA; managed database services are excluded by ADR-0009.

Required ports:
- `IdentityProvider`: registration, email verification, login/session, password recovery/change.
- `LifeMateApi`: authenticated application boundary; clients do not receive privileged database credentials.
- `TransactionalEmail`: verification, password recovery and family invitation messages.
- `ObjectStorage`: future profile/media assets.
- `RealtimeTransport`: optional event delivery; business correctness cannot depend on it.

PostgreSQL owns profiles, family workspaces, memberships, guardian relationships, invitations and authorization-relevant state. Authorization is enforced server-side. Database constraints and, where operationally suitable, RLS are defense-in-depth rather than the only authorization boundary.

## Consequences
### Positive
- Staging/production can move between managed PostgreSQL providers.
- Auth can change without rewriting family/profile domain tables.
- Flutter clients stay independent of database vendor SDKs.
- Testing authorization through API/service contracts becomes straightforward.
- LifeMate is no longer blocked by Supabase project quotas.

### Cost
- We own a small backend/API layer instead of relying entirely on generated BaaS APIs.
- Email verification/recovery and session handling need an explicit identity adapter.
- Realtime/storage require separate adapters if/when introduced.

## Guardrails
- Never place database owner/service credentials in Flutter/Web clients.
- Never use client-side role checks as the security boundary.
- Never let Family Owner/Admin imply automatic access to private teen content.
- Migrations remain standard PostgreSQL SQL wherever practical.

# ADR-0005 — Backend/Auth Baseline: Supabase

- **Status:** Superseded
- **Date:** 2026-10-05
- **Superseded by:** [ADR-0006](0006-provider-neutral-postgresql-backend.md)

Supabase was initially selected as the Phase 2 combined PostgreSQL/Auth/RLS platform. The project subsequently moved to a provider-neutral PostgreSQL architecture with explicit identity/API/email/storage adapters. This file remains only as decision history and must not be used as current implementation guidance.

The existing Supabase QA database observed in the 2026-10-15 audit does not reinstate this combined-backend/auth decision. It establishes the current QA database state, not a new hosting or identity policy. See [current state](../../PROJECT_STATE.md).

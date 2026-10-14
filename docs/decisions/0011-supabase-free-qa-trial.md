# ADR 0011 — Supabase Free trial as isolated LifeGuide QA (conditional)

Date: 2026-10-15  
Status: **PROPOSED FOR QA ONLY — not activated**

## Context

Owner explicitly requests an independent **LifeGuide** Supabase organization and a no-payment online test environment for child/parent Android+PWA shared state. International card payments are unavailable. Current application 0.7.1 uses Node/Express, PostgreSQL, native Argon2 and custom auth; previous production hosting ADR 0009 selected a self-hosted Compose approach due to cost, reachability and runtime constraints.

Connected Supabase account already has an unrelated Free organization `Finora`, with projects `Finora` (INACTIVE) and `EasyFactor` (ACTIVE_HEALTHY). The Supabase Free active-project allowance is account-wide, not renewed for each organization. No LifeGuide organization/project has yet been created, and organization creation is unavailable through the connected Supabase connector.

## Decision boundaries

1. **Evaluate** a separate `LifeGuide` Free organization and `LifeGuide-QA` project, only after the provider returns **exactly $0** for creation and confirms capacity. Nothing in this ADR authorizes payment.
2. The evaluation is exclusively synthetic and isolated. **Never alter** Finora/EasyFactor, existing Railway, DNS, the current production backend/database, or user data.
3. Supabase-hosted PostgreSQL may preserve much of the relational model, but does **not** provide long-running Express hosting. The runtime/auth/database-role differences require a compatibility spike. This is **not** a production migration approval, nor proof of an interchangeable service.
4. Keep current LifeGuide 0.7.1 test branch/CI source and stacked PRs untouched. Prototype any adapters only in an isolated branch.
5. Child privacy and parent visibility must be verified by server-side negative tests, RLS if accessing via PostgREST, consent and audit semantics, not user-interface hiding. Public client must not receive privileged credentials.
6. Public PWA hosting, Safari/Add to Home Screen, Android connectivity, backup/recovery, access from Iran without VPN, sanctions/terms and the Free tier's pause policy are independent acceptance gates.

## Rejection and exit criteria

- If provider requires billing details, project creation costs > $0, two active slots are full, or Iran access/terms are unacceptable, **stop without attempting to bypass restrictions**.
- No real-data import, account migration, release, permanent architecture change, domain change, or irreversible action without new explicit approval.
- If the spike is successful, compare ongoing operations/backup limits against ADR 0009 before choosing any production architecture.

## Status and references

- `docs/operations/SUPABASE_QA_BOOTSTRAP.md`: actionable zero-cost gates and verification ledger.
- `docs/decisions/0009-provider-neutral-hosting.md`: **still the active production hosting baseline**.
- Independent organization creation, exact cost confirmation and real QA deployment: **not done**.

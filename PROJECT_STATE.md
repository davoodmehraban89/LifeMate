# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Phase 2 — Product Foundation & Identity — IN PROGRESS
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
Phase 1 is complete. Phase 2 is active on `phase-2/product-foundation-identity`. A real Flutter Android/Web-PWA scaffold, provider-neutral Node API, PostgreSQL identity/family schema, auth/recovery/change-password flows, profile/family/invitation/guardian foundations and GitHub Actions CI now exist. Persistent staging infrastructure is being completed on Railway.

## Five-phase roadmap
1. **Foundation, Product Contract & UX Direction** — COMPLETE
2. **Product Foundation & Identity** — IN PROGRESS
3. **Planner, School & Family Core**
4. **AI Guides, Learning & Wellbeing**
5. **Hardening, Observability & Release**

## Accepted architecture baseline
- Client: Flutter for Android + app-centric responsive Web/PWA.
- iPhone/iPad initial distribution: Home Screen PWA; future packaged/native iOS path preserved.
- Backend: provider-neutral Node API + standard PostgreSQL. Railway is the current Phase 2 staging host; managed database/provider can be replaced without changing domain contracts.
- Identity: LifeMate-owned email/password/session adapter with Argon2id, verification/reset tokens, rotating refresh sessions and server-side authorization.
- Offline: explicit custom web service-worker/cache strategy; browser storage is non-authoritative.
- Authorization: relationship-aware and server-enforced; family admin is not blanket private-content access.

## Product/UX baseline
- Student navigation uses MyStudyLife as the primary IA benchmark: Today, Weekly Schedule, Calendar, Tasks, Exams/Grades, Focus, AI; LifeMate Family/Wellbeing extensions are additive.
- Parent/adult experiences share the platform while emphasizing Family, authorized progress/support information and guidance.
- Parent support focuses on authorized schedule/academic/support summaries, not routine private transcript surveillance.
- Visual language: warm, modern, calm, graphical, teen-friendly but non-childish; Persian RTL first-class. Default profile themes: daughter/teen girl = white + soft pink; son/teen boy = white + calm blue; parents/adults = white + calm blue.
- Figma artifact exists: `LifeMate — Product UX & Brand v1` with initial editable direction frames.
- Canva is supporting visual/illustration exploration; Figma remains UI source of truth.
- Notion Project Hub exists as management mirror; GitHub remains technical source of truth.

## Phase 1 deliverables
- `docs/ROADMAP.md`
- `docs/product/PRODUCT_SPEC_V1.md`
- `docs/product/FEATURE_PRIORITIES_V1.md`
- `docs/product/PERMISSION_MATRIX_V0.md`
- `docs/product/PHASE_1_EXECUTION.md`
- `docs/ux/IA_AND_JOURNEYS_V1.md`
- `docs/ux/BRAND_BRIEF_V1.md`
- `docs/architecture/DOMAIN_MODEL_V1.md`
- `docs/architecture/PWA_PLATFORM_CONSTRAINTS_V1.md`
- `docs/architecture/PHASE_2_BLUEPRINT.md`
- `docs/quality/PHASE_2_QUALITY_GATES.md`
- `docs/quality/ANALYTICS_POLICY_V1.md`
- `docs/safety/SAFETY_PRIVACY_RISK_V1.md`
- ADR-0001 through ADR-0006; ADR-0005 (Supabase baseline) is superseded by ADR-0006 (provider-neutral PostgreSQL).

## Phase 2 first vertical slice
Auth → verified email/recovery/change password → Profile → Family Workspace → invitation/membership → Guardian Relationship → server-side permission tests → Persian RTL Teen/Parent shells → CI → persistent staging smoke.

## Production-gate items intentionally deferred
These do not block Phase 2 engineering foundation but do block public production of wellbeing/minor-sensitive AI features: jurisdiction-specific legal/guardian consent review; safety severity taxonomy; emergency resource localization; AI provider privacy/retention review; wellbeing retention/export/deletion policy.

## Guardrail
AI/wellbeing production exposure stays disabled until its dedicated safety/legal/provider gates pass. Production deploys, destructive migrations and sensitive access changes still require explicit action-specific approval.
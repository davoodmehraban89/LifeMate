# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Phase 2 — Product Foundation & Identity — COMPLETE
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
Phase 1 and Phase 2 are complete. The implementation branch `phase-2/product-foundation-identity` now contains the real Flutter Android/Web-PWA scaffold, provider-neutral Node API, PostgreSQL identity/family schema, auth/recovery/change-password flows, profile/family/invitation/guardian foundations, Persian RTL role-aware Teen/Parent shells, security gates and CI. Railway staging is live with PostgreSQL, API and transactional-email test infrastructure. The Phase 2 CI run for head `9c8a813d4673f9f320d804c91a347a14a51d26db` passed backend, Flutter/Web/Android and security jobs.

## Five-phase roadmap
1. **Foundation, Product Contract & UX Direction** — COMPLETE
2. **Product Foundation & Identity** — COMPLETE
3. **Planner, School & Family Core** — NEXT
4. **AI Guides, Learning & Wellbeing**
5. **Hardening, Observability & Release**

## Accepted architecture baseline
- Client: Flutter for Android + app-centric responsive Web/PWA.
- iPhone/iPad initial distribution: Home Screen PWA; future packaged/native iOS path preserved.
- Backend: provider-neutral Node API + standard PostgreSQL. Railway is the current staging host; managed database/provider can be replaced without changing domain contracts.
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

## Phase 2 completed vertical slice
Auth → verified email/recovery/change password → Profile → Family Workspace → invitation/membership → Guardian Relationship → server-side permission tests → Persian RTL Teen/Parent shells → CI → persistent staging infrastructure and smoke verification.

### Verified Phase 2 gates
- PostgreSQL migrations and authorization helper tests pass.
- Backend API tests pass, including unauthenticated, teen/non-admin denial and active-member role-escalation protection.
- Backend dependency audit reports no high-severity blocking vulnerability.
- Secret/environment-file CI gates pass.
- Flutter formatting, static analysis and widget tests pass.
- Flutter Web release build passes.
- Android debug APK build passes.
- Railway staging PostgreSQL, API and Mailpit are online; API health and staging transactional-email probe passed.

## Phase 3 entry point
Implement Planner, School & Family Core on top of the completed identity/family contracts. Preserve role-aware navigation, relationship-aware permissions, Persian RTL, provider-neutral backend boundaries and the existing CI/security gates.

## Production-gate items intentionally deferred
These do not block the engineering foundation but do block public production of wellbeing/minor-sensitive AI features: jurisdiction-specific legal/guardian consent review; safety severity taxonomy; emergency resource localization; AI provider privacy/retention review; wellbeing retention/export/deletion policy.

## Guardrail
AI/wellbeing production exposure stays disabled until its dedicated safety/legal/provider gates pass. Production deploys, destructive migrations and sensitive access changes still require explicit action-specific approval.

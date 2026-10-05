# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Discovery / Foundation
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
The repository has been created and verified as private with push/admin access. Foundation documentation is being established before locking the application stack or generating production code.

## Confirmed product direction
- Personal + Family + Learning companion; not only a student planner.
- Initial primary use case includes a 13-year-old first-year lower-secondary student and her parents, while remaining generalizable to other families and ages.
- One Family Workspace with independent accounts and dynamic membership.
- Parent access to authorized planning, academic reports, and important support signals.
- Layered teen privacy with separate safety escalation rules.
- School planning benchmark includes the useful capability inventory identified from MyStudyLife.
- AI domains: planner, study coach/tutor, teen wellbeing companion, parent coach and family guidance.
- Wellbeing guidance is non-diagnostic and must include explicit safety boundaries.
- Forgot Password via verified email reset link; Change Password in settings.
- Multi-stage reminders, banners/notifications, completion-aware cancellation and rescheduling proposals.
- Android + iPhone/iPad PWA + responsive web using shared backend/data.
- Strong visual identity, app icon, entry/login experience, RTL Persian quality, teen-attractive but non-childish design.

## Operating structure
Coordinator + five specialist ownership areas:
1. Product & Research
2. UX/UI & Brand
3. Architecture/Data/Security/Safety
4. Cross-platform Development
5. QA/Release/Observability

## Tooling direction
- GitHub: technical source of truth and delivery workflow.
- Figma: primary UI/UX and design system.
- Canva: brand/illustration/educational visual assets.
- Notion: management knowledge/mirror, not technical source of truth.
- Supabase: current backend/auth/database candidate; not yet locked by ADR.
- Context7: version-aware implementation documentation.
- PostHog: intended for staging+ analytics/feature flags/observability with privacy-minimal instrumentation.
- Cloudflare/hosting providers: introduce only when architecture requires them.

## Current change ledger
### DONE
- [x] Product working name approved: LifeMate.
- [x] Private GitHub repository created.
- [x] Repository connection and write access verified.
- [x] Initial README created.
- [x] `AGENTS.md` operating rules created.

### IN PROGRESS
- [ ] Record foundational ADRs under `docs/decisions/`.
- [ ] Convert Discovery Book v1 into repository-native product documentation.
- [ ] Establish initial product/UX architecture and brand direction.
- [ ] Decide cross-platform frontend implementation after prototype/technical validation.
- [ ] Decide backend/auth stack after requirements validation.

### NOT STARTED
- [ ] Application scaffold.
- [ ] Database schema/migrations.
- [ ] CI workflows.
- [ ] Staging environment.
- [ ] AI provider selection.
- [ ] Email provider/configuration.
- [ ] Push notification provider/configuration.
- [ ] Voice STT/TTS provider selection.

## Immediate next sequence
1. Create foundational ADRs for product scope, family/privacy model, and distribution strategy.
2. Add repository-native Discovery v1 summary and requirements inventory.
3. Produce initial UX information architecture and visual/brand brief.
4. Validate frontend/backend candidates before generating the application scaffold.

## Guardrail
Do not start implementation merely to create visible code. Foundation decisions that affect identity, permissions, privacy, teen safety, offline/sync, and cross-platform distribution must be explicit first; low-risk reversible UI prototypes may proceed in parallel.

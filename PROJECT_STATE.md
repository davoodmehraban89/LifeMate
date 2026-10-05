# LifeMate — Project State

**Last updated:** 2026-10-05
**Phase:** Phase 1 — Foundation, Product Contract & UX Direction
**Repository:** `davoodmehraban89/LifeMate`
**Working product name:** LifeMate — approved

## Transfer checkpoint
LifeMate is now operating on a five-phase roadmap. Phase 1 has started. Repository foundation, product baseline, three foundational ADRs and an initial permission/visibility contract exist. No application stack has yet been irreversibly locked and no production code has been generated.

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

## Five-phase roadmap
1. **Foundation, Product Contract & UX Direction** — IN PROGRESS
2. **Product Foundation & Identity**
3. **Planner, School & Family Core**
4. **AI Guides, Learning & Wellbeing**
5. **Hardening, Observability & Release**

See `docs/ROADMAP.md` for gates and deliverables.

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
- [x] Private GitHub repository created and write access verified.
- [x] Initial README and `AGENTS.md` created.
- [x] Five-phase roadmap recorded.
- [x] Product Specification v1 baseline recorded.
- [x] Foundational ADRs: product lifecycle, family/privacy principle, distribution strategy.
- [x] Phase 1 execution board created.
- [x] Initial permission/visibility matrix created.

### IN PROGRESS — PHASE 1
- [ ] Prioritize feature inventory into Must / Should / Later.
- [ ] Define information architecture and primary user journeys.
- [ ] Produce visual/brand brief and prototype-ready screen inventory.
- [ ] Define conceptual domain model.
- [ ] Evaluate and record frontend architecture ADR.
- [ ] Evaluate and record backend/auth architecture ADR.
- [ ] Define wellbeing safety boundary and risk register.
- [ ] Validate PWA/platform constraints.
- [ ] Define CI/staging/observability readiness rules.

### NOT STARTED
- [ ] Application scaffold (Phase 2 gate).
- [ ] Database schema/migrations.
- [ ] CI workflows.
- [ ] Staging environment.
- [ ] AI provider selection.
- [ ] Email provider/configuration.
- [ ] Push notification provider/configuration.
- [ ] Voice STT/TTS provider selection.

## Immediate next sequence
1. Complete Phase 1 UX information architecture + brand brief.
2. Complete domain model and backend/frontend ADR evaluations.
3. Complete privacy/safety and platform validation.
4. Run Phase 1 exit review; only then generate the Phase 2 application scaffold.

## Guardrail
Do not start implementation merely to create visible code. Foundation decisions that affect identity, permissions, privacy, teen safety, offline/sync, and cross-platform distribution must be explicit first; low-risk reversible UI prototypes may proceed in parallel.

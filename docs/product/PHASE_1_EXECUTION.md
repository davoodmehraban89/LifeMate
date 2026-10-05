# Phase 1 — Execution Board

**Phase:** Foundation, Product Contract & UX Direction
**Status:** IN PROGRESS
**Owner:** Coordinating Project Lead

## Workstream A — Product & Research
**Primary owner:** Product & Research

- [x] Establish product definition and V1 actors.
- [x] Record five-phase roadmap.
- [x] Record Product Specification v1 baseline.
- [ ] Normalize competitor-derived feature inventory into Must / Should / Later.
- [ ] Define measurable V1 outcome and non-goals.

**Done when:** V1 scope can be tested and later-feature inventory cannot silently expand it.

## Workstream B — UX/UI & Brand
**Primary owner:** UX/UI & Brand

- [ ] Define information architecture for Teen, Parent and Adult/Family experiences.
- [ ] Define primary journeys: onboarding/join family, Today, school planning, parent review, sharing, password recovery.
- [ ] Produce brand/visual brief: mood, typography direction, color principles, icon/logo principles, illustration language, age progression.
- [ ] Define responsive/PWA constraints and RTL/accessibility baseline.
- [ ] Prepare prototype-ready screen inventory for Figma.

**Done when:** prototype work can start without inventing navigation or brand rules ad hoc.

## Workstream C — Architecture, Data, Security & Safety
**Primary owner:** Architecture/Data/Security/Safety

- [x] Record product lifecycle ADR.
- [x] Record family/privacy principle ADR.
- [x] Record distribution strategy ADR.
- [ ] Define role/permission/visibility matrix.
- [ ] Define conceptual domain model and ownership boundaries.
- [ ] Evaluate backend/auth candidate and record ADR.
- [ ] Evaluate frontend candidate and record ADR.
- [ ] Define wellbeing safety boundary and unresolved jurisdiction questions.
- [ ] Define audit requirements for sensitive policy/access changes.

**Done when:** Phase 2 can enforce identity and family authorization server-side from documented rules.

## Workstream D — Cross-platform Development Readiness
**Primary owner:** Cross-platform Development

- [ ] Validate PWA requirements/limitations relevant to notifications, storage, offline and install UX.
- [ ] Validate Android + Web/PWA candidate stack against required capabilities.
- [ ] Define environment/configuration strategy without committing secrets.
- [ ] Define proposed repository application structure after architecture ADRs.

**Done when:** application scaffold can be generated with known platform constraints rather than assumptions.

## Workstream E — QA, Release & Observability Readiness
**Primary owner:** QA/Release/Observability

- [ ] Define Phase 2 CI quality gates: format/lint/static analysis/unit tests/build smoke.
- [ ] Define staging-first release rule and minimum smoke matrix.
- [ ] Define privacy-minimal analytics event principles before PostHog instrumentation.
- [ ] Define initial risk register and verification ownership.

**Done when:** the first code is born into a testable/releasable workflow instead of adding QA later.

## Phase 1 exit review
Phase 1 cannot close with unresolved critical ambiguity in:
- identity/recovery;
- family membership and roles;
- parent visibility versus teen privacy;
- wellbeing safety boundary;
- target platform/distribution;
- V1 scope;
- frontend/backend architecture selection.

Low-risk visual prototypes may run in parallel with these decisions.

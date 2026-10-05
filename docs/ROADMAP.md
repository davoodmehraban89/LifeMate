# LifeMate — Five-Phase Roadmap

**Status:** Active
**Started:** 2026-10-05

## Phase 1 — Foundation, Product Contract & UX Direction
**Goal:** turn discovery into an executable, testable product contract before locking irreversible implementation choices.

Deliverables:
- Repository operating rules, project state and decision log.
- Product specification v1 and V1 scope.
- Role/permission/visibility matrix for Family, Parent/Guardian, Teen and Adult Member.
- Information architecture and primary user journeys.
- Brand/visual brief for teen, parent and family surfaces.
- Architecture decision package for frontend, backend/auth, notifications, email and AI boundaries.
- Initial data/domain model and safety/privacy rules.
- Acceptance criteria for Phase 2.

**Exit gate:** no critical ambiguity remains around identity, family membership, permissions, parental visibility, safety boundaries, distribution targets or V1 scope; architecture candidates are validated enough to scaffold.

## Phase 2 — Product Foundation & Identity
**Goal:** create a runnable cross-platform foundation with secure identity and family membership.

Deliverables:
- Application scaffold for selected cross-platform stack.
- Auth: sign-up/sign-in, verified email, forgot/reset password, change password, session handling.
- Profile and life-context foundation.
- Family Workspace, invitations, membership, roles and server-side authorization.
- Base design system, RTL, responsive shell and branded entry/login experience.
- CI, automated checks and staging baseline.

**Exit gate:** teen/parent/adult test accounts can securely join a family and use the authenticated application shell on Android target and iPhone/Web target with permissions enforced server-side.

## Phase 3 — Planner, School & Family Core
**Goal:** deliver the useful daily product before advanced AI.

Deliverables:
- Today, Calendar, Tasks, Routines and Goals.
- Reminder model and notification pipeline.
- School context: academic year, term, subjects, classes, homework, exams, study sessions and grades foundation.
- Family calendar and controlled sharing.
- Parent dashboard and authorized academic/planning reports.
- Offline-aware client behavior and sync strategy for critical flows.

**Exit gate:** a family can plan a real week, manage school workload, share selected items and receive correct reminders/reports without AI dependency.

## Phase 4 — AI Guides, Learning & Wellbeing
**Goal:** add context-aware intelligence without weakening privacy, safety or user control.

Deliverables:
- AI orchestration/context permission layer.
- Life Planner and Study Coach.
- Tutor with learning-oriented guardrails.
- Teen Wellbeing Companion with non-diagnostic boundaries.
- Parent Coach and family guidance.
- Safety escalation framework and auditable sensitive events.
- Voice/STT/TTS where validated for Persian quality and privacy.

**Exit gate:** AI uses only authorized context, produces useful explainable proposals, respects safety/privacy policies and passes defined adversarial/safety scenarios.

## Phase 5 — Hardening, Observability & Release
**Goal:** turn the integrated product into a reliable release candidate and controlled production launch.

Deliverables:
- End-to-end regression, accessibility, security and performance testing.
- PostHog privacy-minimal analytics/feature flags and operational observability.
- Backup/recovery and data export/deletion policies as applicable.
- PWA install polish, Android release packaging and production runbooks.
- Staging acceptance, release checklist, rollback strategy and production approval gate.

**Exit gate:** release candidate passes acceptance criteria on target platforms, unresolved risks are documented, rollback/recovery are verified and production release has explicit approval.

## Phase policy
- Phases define outcome gates, not bureaucracy. Low-risk independent work may overlap when dependencies are satisfied.
- A later phase may prototype early, but cannot be declared complete before prerequisite gates.
- Product scope can evolve through recorded decisions; architecture must not be expanded solely for hypothetical future features.

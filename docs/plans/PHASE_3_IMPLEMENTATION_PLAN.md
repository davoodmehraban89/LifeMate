# Phase 3 — Planner, School & Family Core Implementation Plan

Status: IN PROGRESS
Branch: `phase-3/planner-school-family-core`

## Acceptance contract
Phase 3 is complete only when a family can plan a real week without AI: personal/family calendar items, tasks, routines/goals, reminders, school year/term/subjects/classes/assignments/exams/study sessions/grades, controlled sharing, guardian-authorized child support summary, and offline-aware client behavior all exist and pass CI/staging verification.

## Implementation slices
1. PostgreSQL planning/school/sharing/notification schema with constraints and indexes.
2. Server authorization helpers and CRUD/query API for Today, Planner, School, Family and Parent Support.
3. Reminder outbox with idempotent due-reminder claiming and completion/reschedule semantics.
4. Flutter provider-neutral client models/API and Persian RTL core screens.
5. Offline-aware read cache + queued safe edits contract for critical planning flows.
6. Permission regression tests: owner, guardian, unrelated member, removed member, unauthenticated.
7. CI schema/API/widget/Web/Android gates.
8. Railway staging migrations + smoke verification.
9. State/docs update, PR review, merge, main CI verification.

## Scope rules
- MyStudyLife remains the benchmark for student IA, but LifeMate adds family sharing and guardian support.
- AI is not required for any Phase 3 flow.
- Parents receive authorized schedule/workload/progress summaries, not private content.
- Reminder delivery is modeled as an outbox/provider boundary; Phase 3 verifies scheduling and delivery eligibility without coupling the domain to one push vendor.
- Offline cache is non-authoritative; queued edits are limited to operations with explicit conflict semantics.

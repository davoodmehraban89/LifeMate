# ADR-0001 — Product Scope and Lifecycle

- **Status:** Accepted
- **Date:** 2026-10-05

## Context
LifeGuide begins from a teen/student use case but is intended to remain useful across school years and later life. A student-only root model would make later expansion into university, work, personal projects and adult family life structurally expensive.

## Decision
LifeGuide is a **Personal, Family & Learning Companion**. The core identity is `Person/Profile`; `Student` is a contextual role/life context. School capabilities are a major initial domain but do not define the root user model.

The product will maintain a deliberately small initial executable scope while keeping domain boundaries extensible.

## Consequences
- Academic entities attach to a profile/life context rather than replacing identity.
- Adult family members can use the same platform for personal/family planning without pretending to be students.
- UI experiences may differ substantially by age and role while using a common platform.
- Feature inventory is not automatically V1 scope; capabilities require prioritization and acceptance criteria.

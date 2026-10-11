# Aparat learning library execution

Goal: an authenticated, grade-aware Iranian learning library with in-page Aparat video, durable private progress and existing planner/timer integration.

Architecture: additive PostgreSQL catalogue/unit/progress storage, deterministic public-resource import, real Express routes; Flutter conditional web iframe/native WebView with a durable account-scoped progress queue. Reuse identity/Feature 1/planner/study APIs.

Tech: Node22/Express/PostgreSQL16; Flutter3.47.6; official Aparat iframe and metadata. [Design](../specs/2026-10-09-aparat-learning-library-design.md).

Global constraints: no video downloads/rehosting; no fake complete coverage; no automatic proof of studying; no third-party student identifiers; no live changes. Research metadata is not pedagogical or device acceptance.

- [x] Read AGENTS/PROJECT_STATE and inspect existing education, planner/offline/timer contracts; create isolated feature branch.
- [ ] Record official book/edition and provider evidence across primary, middle and upper-secondary; disclose content gaps.
- [ ] Add migration/importer/API/private progress/idempotency and lesson-to-plan linkage; real HTTP/DB tests including restart and permission negatives.
- [ ] Add Persian grade/track library, ordered lessons, explicit progress/offline/conflict states and planning/timer connection.
- [ ] Add click-to-load canonical iframe/WebView, scoped permissions and credits; test malformed hashes and no automatic completion.
- [ ] Run migration repeat, backend regressions, Flutter analysis/tests, compiled web and actual embed checks; record output and hardware UNVERIFIED gates.
- [ ] Independent security/curation review; update state/version/README/changelog/ADRs; commit small packets and open a stacked draft PR.

Review focus: edition mismatches, missing free sequences, auth/cache boundary, false acknowledgement, provider URL injection, unintended external requests, private-progress leakage, catalogue import privilege separation.

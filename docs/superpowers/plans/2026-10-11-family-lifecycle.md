# Family lifecycle implementation plan

1. Inspect existing invite/accept/remove locks and sharing policies.
2. RED validation/HTTP tests; add migration0018 membership/invitation revisions
   and metadata-only stable mutation ledger.
3. Implement dedicated administrator-only lifecycle router, scoped read and
   current-state retry after transfer; root mounts it and adjusts expiry checks.
4. Run real local HTTP/PostgreSQL race, restart and privacy tests; root integrates
   runtime-role policy/complete suite/client acceptance.
5. Document exact outputs and remaining hardware/live/age-assurance limits.

One backend owner; root exclusively owns shared server and DB role integration.

Execution on2026-10-11 (local synthetic PostgreSQL16, Node22.23.3):

- RED: the genuinely lock-blocked JWT-expiry request incorrectly returned200
  instead of401; reciprocal writes across two families returned500/200 instead
  of200/200 with actor-first account locks.
- GREEN: ordered account/profile/membership locks and final locked-session plus
  fresh-time JWT check passed both regressions,2/2.
- Final focused command, `node --test tests/family_lifecycle.test.js
  tests/family_lifecycle_validation.test.js`, passed **21/21**, zero failures,
  cancellations or skips,3690.98ms. This includes root-owned creation, legacy
  helper and acceptance final-session guards; API restart, current-state/hash
  retry, CAS, privacy, one-admin races, removal/rejoin, birth-date edits, and
  expiry/revocation while actual database locks are held.
- The project command `node scripts/test.js` also ran:215 tests,214 passed,
  one failed,44818.13ms. The named failure was
  `profile_category.test.js:148`, learning-goal malformed-subject compatibility:
  expected `invalid_subject_id`, received `invalid_input`. The separate goal
  owner and root received the complete result; this is not a green whole-suite
  claim. This aggregate preceded the final two focused family regressions.
- Migration0018 was applied through the real migration runner. That runner also
  saw and applied draft0019 in the shared synthetic fixture; no stored checksum
  was edited. A fresh integrated database with all final frozen migrations is
  required for final handover. No live database or canonical role credential was
  changed.

This agent did not run an APK/web build, runtime-role restore drill, physical
Android/Safari acceptance, or live migration/deploy. Those are **UNVERIFIED** for
this packet until root records independent execution.

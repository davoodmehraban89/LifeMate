# Rollback Runbook

Rollback is preferred over improvising a risky live fix when a release causes authentication, authorization, data-integrity or availability regression.

1. Stop further rollout and record the affected release/commit and first observed symptom.
2. If schema is backward-compatible, redeploy the last known-good application build.
3. Verify `/live`, `/ready`, `/health` and critical login/family/planner flows.
4. If a data rollback is required, do not run destructive SQL ad hoc. Preserve the current database first, identify the exact backup, and obtain explicit approval before destructive restore/migration actions.
5. Confirm recovery in telemetry and record the incident timeline and follow-up test that prevents recurrence.

A rollback is complete only when service health and critical user flows are verified, not merely when a previous build reports deployed.

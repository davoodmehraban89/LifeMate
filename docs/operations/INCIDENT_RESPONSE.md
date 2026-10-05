# Incident Response

Priorities are user safety, containment, data integrity, recovery and evidence-preserving follow-up.

## Triage
Classify incidents as availability, authentication/authorization, privacy/data exposure, data integrity, abuse/rate-limit, or minor-sensitive AI/wellbeing safety. Record time, affected environment, release and observable impact without copying private conversation content into tickets or logs.

## Containment
For authorization/privacy incidents, disable the affected surface or provider before optimizing availability. For minor-sensitive AI or wellbeing incidents, keep raw notes and transcripts private; use only the existing safety signal path and approved aggregate information. External AI/voice can be disabled independently.

## Recovery
Use the rollback runbook for application regressions and the backup/restore runbook for data recovery. Verify `/live`, `/ready`, `/health` plus the affected user journey.

## Follow-up
Document root cause, detection gap, corrective test and operational action. Rotate credentials through secret management if compromise is suspected; never paste secrets into issue comments or repository files.

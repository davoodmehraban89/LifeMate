# Deployment Runbook

LifeMate uses staging before production. Normal engineering changes deploy to staging first and are verified there before any production decision.

## Staging
1. Confirm branch CI is green: security, backend, backup/restore and Flutter jobs.
2. Apply migrations using the migration runner before the API change that depends on them.
3. Deploy the API to the staging environment only.
4. Verify `/live`, `/ready` and `/health`; `/ready` must report database ready.
5. Review structured logs for startup, 5xx responses and unexpected 429 spikes without inspecting sensitive user content.
6. Run the documented smoke flows for authentication, family, planner and Phase 4 guidance.

## Production gate
Production deployment requires explicit approval from the product owner for that deployment. Before approval, confirm the production checklist, current backup, rollback target, environment variables and release version. Minor-sensitive external AI and voice integrations remain disabled until their separate safety/privacy/legal gates are approved.

Never place secrets in source control or deployment notes. Use the hosting platform's secret/environment management.

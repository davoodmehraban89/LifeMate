# Backup & Restore Runbook

Use PostgreSQL-native custom-format backups. A backup is not considered reliable until a restore drill succeeds.

## Backup
Set `DATABASE_URL` through secret management, then run:

`backend/scripts/backup.sh /secure/location/lifemate-YYYYMMDD.dump`

The script uses `pg_dump --format=custom --no-owner --no-privileges`. Store backups encrypted with access limited to authorized operators and apply the retention policy approved for the deployment jurisdiction.

## Restore drill
Create an isolated empty PostgreSQL database. Point `DATABASE_URL` at that database and run:

`backend/scripts/restore.sh /secure/location/lifemate-YYYYMMDD.dump`

The restore uses `pg_restore --clean --if-exists --no-owner --no-privileges --exit-on-error`. Verify expected schema objects and representative rows. CI performs an ephemeral data round-trip on every change.

## Production restore
A production restore is destructive and requires explicit action-specific approval. Preserve the current database before replacement, record the selected recovery point, and verify authentication, family authorization and planner data after recovery.

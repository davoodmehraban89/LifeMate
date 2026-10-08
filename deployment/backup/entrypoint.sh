#!/usr/bin/env bash
set -euo pipefail
umask 077
mkdir -p /backups
schedule="${BACKUP_SCHEDULE:-0 2 * * *}"
if [[ ! "$schedule" =~ ^[0-9*/,-]+[[:space:]][0-9*/,-]+[[:space:]][0-9*/,-]+[[:space:]][0-9*/,-]+[[:space:]][0-9*/,-]+$ ]]; then
  echo 'Invalid BACKUP_SCHEDULE: expected five numeric cron fields' >&2
  exit 1
fi
printf '%s /opt/lifeguide/run-backup.sh\n' "$schedule" >/etc/crontabs/root
/opt/lifeguide/run-backup.sh
exec crond -f -l 8

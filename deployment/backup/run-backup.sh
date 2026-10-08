#!/usr/bin/env bash
set -euo pipefail
umask 077
keep_days="${BACKUP_KEEP_DAYS:-14}"
[[ "$keep_days" =~ ^[0-9]+$ && "$keep_days" -ge 1 ]] || { echo 'Invalid backup retention' >&2; exit 1; }
output="$(mktemp "/backups/.LifeGuide-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
trap 'rm -f "$output"' EXIT
/opt/lifeguide/backup.sh "$output"
pg_restore --list "$output" >/dev/null
completed="/backups/LifeGuide-${output##*/.LifeGuide-}.dump"
mv -n "$output" "$completed"
[[ ! -e "$output" ]] || { echo 'Refusing to replace an existing backup' >&2; exit 1; }
date -u +%Y-%m-%dT%H:%M:%SZ >/backups/last-success
find /backups -maxdepth 1 -type f -name 'LifeGuide-*.dump' -mtime +"$keep_days" -delete

#!/usr/bin/env bash
# Explicit operator-only adoption. Never SSHs or restores/drops application data.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "${1:-}" == '--local-existing' && "${2:-}" == '--expected-owner' && "${4:-}" == '--backup-file' && "$#" -eq 5 ]] || { echo 'Usage: --local-existing --expected-owner ROLE --backup-file /backups/LifeGuide-....dump' >&2; exit 1; }
expected_owner="$3"
backup_file="$5"
[[ "$expected_owner" =~ ^[a-z_][a-z0-9_]{0,62}$ && "$backup_file" =~ ^/backups/LifeGuide-[A-Za-z0-9._-]+\.dump$ ]] || { echo 'Use an explicit safe expected owner and archive within the backup volume' >&2; exit 1; }
if [[ -n "${DOCKER_CONTEXT:-}" ]]; then endpoint="$(docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}')"; else endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"; fi
case "$endpoint" in unix://*|npipe://*) ;; *) echo 'Refusing remote Docker' >&2; exit 1;; esac
docker compose config --quiet
# Stop writers deliberately before invoking this helper; it refuses an active API.
if [[ -n "$(docker compose ps --status running -q api)" ]]; then echo 'Stop the local API/gateway writers and take a fresh verified backup before adoption' >&2; exit 1; fi
database="$(sed -n 's/^POSTGRES_DB=//p' .env)"
[[ "$database" =~ ^[a-z_][a-z0-9_]{0,62}$ ]] || { echo 'Invalid configured app database name' >&2; exit 1; }
toc_file="$(mktemp "${TMPDIR:-/tmp}/lifeguide-adoption-toc.XXXXXX")"
trap 'rm -f "$toc_file"' EXIT
docker compose run --rm --no-deps --entrypoint pg_restore -e TZ=UTC backup --list "$backup_file" >"$toc_file"
archive_db="$(sed -n 's/^;[[:space:]]*dbname: //p' "$toc_file")"
[[ "$archive_db" == "$database" ]] || { echo 'Backup is for another database; refusing adoption' >&2; exit 1; }
digest="$(docker compose run --rm --no-deps --entrypoint sha256sum backup "$backup_file" | cut -d' ' -f1)"
[[ "$digest" =~ ^[a-f0-9]{64}$ ]] || { echo 'Cannot hash verified archive' >&2; exit 1; }
node --input-type=module -e 'console.log(JSON.stringify({format:"LifeGuide-adoption-backup-v1",database:process.argv[1],sha256:process.argv[2],pgRestoreList:true,validatedAt:new Date().toISOString()}))' "$database" "$digest" | \
  docker compose run --rm --no-deps --entrypoint sh backup -c 'umask 077; cat > "$1.validated.json"' sh "$backup_file"
docker compose run --rm --no-deps db-provision node scripts/provision-db-roles.js --prepare --adopt-existing --expected-owner "$expected_owner" --backup-file "$backup_file"
echo 'PASS explicit local ownership adoption. Run migrations/grants/start and synthetic acceptance before admitting users.'

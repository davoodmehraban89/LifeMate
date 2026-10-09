#!/usr/bin/env bash
# Fresh synthetic databases only; never targets the application DB for restore.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "${1:-}" == '--synthetic-only' ]] || { echo 'Use --synthetic-only explicitly' >&2; exit 1; }
if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
  endpoint="$(docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}')"
else
  endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
fi
case "$endpoint" in unix://*|npipe://*) ;; *) echo 'Refusing remote Docker' >&2; exit 1;; esac
docker compose config --quiet
state_dir="$(mktemp -d "${TMPDIR:-/tmp}/lifeguide-role-test.XXXXXX")"
chmod 700 "$state_dir"
tool_args=(compose run --rm --no-deps --user "$(id -u):$(id -g)" -v "$state_dir:/role-test-state" -e ROLE_TEST_STATE_FILE=/role-test-state/state.json db-role-test)
dump_file=''
cleanup() {
  cleanup_ok=yes
  if [[ -f "$state_dir/state.json" ]]; then
    if ! docker "${tool_args[@]}" node scripts/test-db-roles.js --cleanup; then
      cleanup_ok=no
      echo "UNVERIFIED: test database cleanup needs operator review; state preserved in $state_dir" >&2
    fi
  fi
  if [[ -n "$dump_file" ]]; then
    docker compose run --rm --no-deps --entrypoint rm backup -f "$dump_file" >/dev/null 2>&1 || true
  fi
  if [[ "$cleanup_ok" == yes ]]; then rm -rf "$state_dir"; fi
}
trap cleanup EXIT
docker "${tool_args[@]}"
source_db="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).source_db' "$state_dir/state.json")"
target_db="$(node -p 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).target_db' "$state_dir/state.json")"
[[ "$source_db" =~ ^lifeguide_roles_source_[a-f0-9]{16}$ && "$target_db" =~ ^lifeguide_roles_target_[a-f0-9]{16}$ ]] || { echo 'Invalid synthetic database names' >&2; exit 1; }
dump_file="/backups/LifeGuide-role-test-${source_db#lifeguide_roles_source_}.dump"
docker compose run --rm --no-deps --entrypoint /opt/lifeguide/backup.sh \
  -e "DATABASE_URL=postgresql://lifeguide_backup@postgres:5432/$source_db" backup "$dump_file"
docker compose run --rm --no-deps --entrypoint pg_restore backup --list "$dump_file" >/dev/null
docker compose run --rm --no-deps -e "DATABASE_URL=postgresql://lifeguide_migrator@postgres:5432/$target_db" restore "$dump_file"
docker "${tool_args[@]}" node scripts/test-db-roles.js --verify-restored
echo 'PASS local least-privilege SQL + runtime HTTP scenario + read-only dump/migrator restore with12 migrations'

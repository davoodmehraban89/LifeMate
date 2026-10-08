#!/usr/bin/env bash
# Only two newly-created local databases are restored/deleted, never the app DB.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "${1:-}" == '--synthetic-only' ]] || { echo 'Usage: scripts/restore-drill.sh --synthetic-only' >&2; exit 1; }
if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
  endpoint="$(docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}')"
else
  endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
fi
case "$endpoint" in unix://*|npipe://*) ;; *) echo 'Refusing remote Docker' >&2; exit 1;; esac
suffix="$(date -u +%Y%m%d%H%M%S)_${RANDOM}${RANDOM}${RANDOM}"
source_db="lifeguide_drill_source_$suffix"
target_db="lifeguide_drill_target_$suffix"
source_created=no
target_created=no
cleanup() {
  if [[ "$target_created" == yes ]]; then
    docker compose exec -T postgres sh -c 'dropdb --if-exists --username "$POSTGRES_USER" "$1"' sh "$target_db" >/dev/null 2>&1 || true
  fi
  if [[ "$source_created" == yes ]]; then
    docker compose exec -T postgres sh -c 'dropdb --if-exists --username "$POSTGRES_USER" "$1"; rm -f "/tmp/$1.dump"' sh "$source_db" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
docker compose exec -T postgres sh -c 'createdb --username "$POSTGRES_USER" "$1"' sh "$source_db"
source_created=yes
docker compose exec -T postgres sh -c 'createdb --username "$POSTGRES_USER" "$1"' sh "$target_db"
target_created=yes
docker compose run --rm -e "PGDATABASE=$source_db" migrate
docker compose exec -T postgres sh -c 'psql --username "$POSTGRES_USER" --dbname "$1" --set ON_ERROR_STOP=1' sh "$source_db" <backend/scripts/restore-smoke.sql
docker compose exec -T postgres sh -c 'psql --username "$POSTGRES_USER" --dbname "$1" --set ON_ERROR_STOP=1' sh "$source_db" <deployment/restore-fixture.sql
# Copy the already-existing repository backup/restore programs into this
# disposable container, then run them against only the generated drill DBs.
container_id="$(docker compose ps -q postgres)"
docker cp backend/scripts/backup.sh "$container_id:/tmp/lifeguide-backup.sh"
docker cp backend/scripts/restore.sh "$container_id:/tmp/lifeguide-restore.sh"
docker compose exec -T postgres bash -c 'export DATABASE_URL="postgresql:///$1?user=$POSTGRES_USER"; bash /tmp/lifeguide-backup.sh "/tmp/$1.dump"' bash "$source_db"
docker compose exec -T postgres bash -c 'export DATABASE_URL="postgresql:///$2?user=$POSTGRES_USER"; bash /tmp/lifeguide-restore.sh "/tmp/$1.dump"' bash "$source_db" "$target_db"
docker compose exec -T postgres sh -c 'psql --username "$POSTGRES_USER" --dbname "$1" --set ON_ERROR_STOP=1' sh "$target_db" <<'SQL'
do $$
begin
  if (select count(*) from app_user where identity_subject='restore-smoke') <> 1 then
    raise exception 'Synthetic restore row missing';
  end if;
  if (select count(*) from profile where display_name='Restore Smoke') <> 1 then
    raise exception 'Synthetic profile missing';
  end if;
  if not can_view_plan_item('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000005') then
    raise exception 'Restored guardian cannot read permitted homework';
  end if;
  if can_view_plan_item('00000000-0000-4000-8000-000000000005','00000000-0000-4000-8000-000000000006') then
    raise exception 'Restored private task exposed to guardian';
  end if;
  if can_view_plan_item('00000000-0000-4000-8000-000000000007','00000000-0000-4000-8000-000000000005') then
    raise exception 'Restored homework exposed to unrelated parent';
  end if;
  if (select recorded_duration_seconds from study_session where id='00000000-0000-4000-8000-000000000005') <> 600
     or (select sum(extract(epoch from ends_at-starts_at)) from study_interval where session_id='00000000-0000-4000-8000-000000000005') <> 600 then
    raise exception 'Restored paused study intervals/duration changed';
  end if;
end $$;
SQL
expected_migrations=0
for migration_file in backend/migrations/[0-9][0-9][0-9][0-9]_*.sql; do
  [[ -f "$migration_file" ]] && expected_migrations=$((expected_migrations+1))
done
restored_migrations="$(docker compose exec -T postgres sh -c 'psql --username "$POSTGRES_USER" --dbname "$1" --tuples-only --no-align --command "select count(*) from schema_migration"' sh "$target_db")"
[[ "$restored_migrations" -eq "$expected_migrations" ]] || { echo 'Migration ledger count differs from source version' >&2; exit 1; }
echo "PASS synthetic PostgreSQL dump/restore: identity, family permissions, private task, paused study intervals and $restored_migrations migrations preserved."

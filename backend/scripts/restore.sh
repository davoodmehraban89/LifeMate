#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"
dump="${1:?dump file is required}"
pg_restore --dbname="$DATABASE_URL" --clean --if-exists --no-owner --no-privileges --exit-on-error "$dump"

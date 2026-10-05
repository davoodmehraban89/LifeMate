#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_URL:?DATABASE_URL is required}"
output="${1:-lifemate-$(date -u +%Y%m%dT%H%M%SZ).dump}"
pg_dump --dbname="$DATABASE_URL" --format=custom --no-owner --no-privileges --file="$output"
echo "$output"

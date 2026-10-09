#!/usr/bin/env bash
# Fresh synthetic databases only: read-only dump, migrator restore, runtime
# authentication/family scenario and denied privileges are checked together.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
[[ "${1:-}" == '--synthetic-only' ]] || { echo 'Usage: scripts/restore-drill.sh --synthetic-only' >&2; exit 1; }
exec bash scripts/test-db-roles.sh --synthetic-only

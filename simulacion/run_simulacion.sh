#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/simulacion_$(date +%Y%m%d_%H%M%S).log"
LOG_REL="simulacion/logs/$(basename "$LOG_FILE")"

mkdir -p "$LOG_DIR"

cd "$ROOT_DIR"

docker compose run --rm -T \
  -e PGPASSWORD=password \
  -v "$ROOT_DIR:/work" \
  -w /work \
  postgres \
  psql -q -h postgres -U postgres -d smart_city -v ON_ERROR_STOP=1 \
  -v sim_log="$LOG_REL" \
  -f simulacion/00_run_resumen.sql

printf '\nLog detallado: %s\n' "$LOG_FILE"

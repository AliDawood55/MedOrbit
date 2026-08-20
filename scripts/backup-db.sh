#!/usr/bin/env bash
# Back up the staging Postgres database to a timestamped local file.
# Run from the project root on the VM: ./scripts/backup-db.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env.staging ]; then
  echo "Error: .env.staging not found." >&2
  exit 1
fi

# shellcheck disable=SC1091
set -a
source .env.staging
set +a

mkdir -p backups
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUT_FILE="backups/medorbit_staging_${TIMESTAMP}.backup"

echo "==> Dumping database ${DB_NAME} to ${OUT_FILE}"
docker compose -f docker-compose.staging.yml exec -T postgres \
  pg_dump -U "${DB_USER}" -d "${DB_NAME}" -F c > "${OUT_FILE}"

echo "==> Done: ${OUT_FILE}"

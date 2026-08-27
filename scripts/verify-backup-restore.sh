#!/usr/bin/env bash
# Verify a PostgreSQL custom-format backup by restoring it to a disposable DB.
#
# Example (staging VM):
#   VERIFY_DB_NAME=medorbit_restore_verify_20260825 ./scripts/verify-backup-restore.sh
#
# It never targets DB_NAME. The disposable database is intentionally kept by
# default for inspection; set KEEP_RESTORE_DATABASE=false to remove it after a
# successful verification.
set -euo pipefail

cd "$(dirname "$0")/.."

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.staging.yml}"
ENV_FILE="${ENV_FILE:-.env.staging}"
VERIFY_DB_NAME="${VERIFY_DB_NAME:-}"
KEEP_RESTORE_DATABASE="${KEEP_RESTORE_DATABASE:-true}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: environment file '$ENV_FILE' was not found." >&2
  exit 1
fi
if [[ -z "$VERIFY_DB_NAME" ]]; then
  echo "Error: set VERIFY_DB_NAME to a unique disposable database name." >&2
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

if [[ "$VERIFY_DB_NAME" == "$DB_NAME" ]]; then
  echo "Error: VERIFY_DB_NAME must not equal DB_NAME." >&2
  exit 1
fi
if [[ ! "$VERIFY_DB_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Error: VERIFY_DB_NAME contains unsupported characters." >&2
  exit 1
fi
if [[ "$VERIFY_DB_NAME" != *restore_verify* ]]; then
  echo "Error: VERIFY_DB_NAME must contain 'restore_verify' as a safety guard." >&2
  exit 1
fi

compose=(docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE")
backup_file="/tmp/${DB_NAME}_restore_verify_$(date +%Y%m%d_%H%M%S).backup"

echo "==> Creating a custom-format backup of ${DB_NAME} inside postgres"
"${compose[@]}" exec -T postgres \
  pg_dump -U "$DB_USER" -d "$DB_NAME" --format=custom --file="$backup_file"

echo "==> Recreating disposable database ${VERIFY_DB_NAME}"
"${compose[@]}" exec -T postgres dropdb -U "$DB_USER" --if-exists "$VERIFY_DB_NAME"
"${compose[@]}" exec -T postgres createdb -U "$DB_USER" "$VERIFY_DB_NAME"

echo "==> Restoring backup into ${VERIFY_DB_NAME}"
"${compose[@]}" exec -T postgres \
  pg_restore -U "$DB_USER" -d "$VERIFY_DB_NAME" --no-owner --no-privileges "$backup_file"

echo "==> Verifying PostGIS, migration ledger, and core schema"
"${compose[@]}" exec -T postgres psql -U "$DB_USER" -d "$VERIFY_DB_NAME" --no-psqlrc \
  --set ON_ERROR_STOP=1 \
  --command "SELECT extversion AS postgis_version FROM pg_extension WHERE extname='postgis';" \
  --command "SELECT count(*) AS applied_migrations, max(version) AS latest_migration FROM medorbit.schema_migrations;" \
  --command "SELECT to_regclass('medorbit.users') AS users_table, to_regclass('medorbit.outbox_events') AS outbox_table, to_regclass('medorbit.subscriptions') AS subscriptions_table;" \
  --command "SELECT count(*) AS user_rows FROM medorbit.users;"

"${compose[@]}" exec -T postgres rm -f "$backup_file"

if [[ "$KEEP_RESTORE_DATABASE" == "false" ]]; then
  echo "==> Removing verified disposable database ${VERIFY_DB_NAME}"
  "${compose[@]}" exec -T postgres dropdb -U "$DB_USER" "$VERIFY_DB_NAME"
else
  echo "==> Verification succeeded; retained ${VERIFY_DB_NAME} for inspection."
fi

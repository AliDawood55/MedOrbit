#!/usr/bin/env bash
# Bootstrap the immutable pre-migration MedOrbit schema on a brand-new
# PostgreSQL database. This is intentionally separate from the numbered
# migration history: migrations 001+ alter tables that existed before the
# repository began tracking migrations.
set -euo pipefail

: "${PGHOST:?PGHOST is required}"
: "${PGPORT:?PGPORT is required}"
: "${PGUSER:?PGUSER is required}"
: "${PGDATABASE:?PGDATABASE is required}"

BASELINE_SQL="${BASELINE_SQL:-/bootstrap/base-schema.sql}"

if [[ ! -r "$BASELINE_SQL" ]]; then
  echo "Database bootstrap failed: baseline SQL is not readable at $BASELINE_SQL" >&2
  exit 1
fi

schema_exists="$(psql --no-psqlrc --tuples-only --no-align \
  --command "SELECT to_regnamespace('medorbit') IS NOT NULL")"

if [[ "$schema_exists" == "t" ]]; then
  users_exists="$(psql --no-psqlrc --tuples-only --no-align \
    --command "SELECT to_regclass('medorbit.users') IS NOT NULL")"

  if [[ "$users_exists" == "t" ]]; then
    echo "Database bootstrap skipped: medorbit baseline already exists in $PGDATABASE"
    exit 0
  fi

  echo "Database bootstrap refused: schema medorbit exists but medorbit.users is missing." >&2
  echo "Refusing to guess whether this is a partial or damaged database." >&2
  exit 1
fi

echo "Applying tracked MedOrbit baseline schema to empty database $PGDATABASE"
psql --no-psqlrc --set ON_ERROR_STOP=1 --file "$BASELINE_SQL"
echo "Database baseline applied successfully"

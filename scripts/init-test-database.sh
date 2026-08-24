#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DB_NAME="${SOURCE_DB_NAME:-}"
TEST_DB_NAME="${TEST_DB_NAME:-}"
SCHEMA_DUMP="/tmp/medorbit-test-schema.sql"
CREATED_TEST_DB=0

case "$TEST_DB_NAME" in
    *[!a-zA-Z0-9_]*)
        echo "Refusing unsafe TEST_DB_NAME: only letters, numbers, and underscores are allowed" >&2
        exit 1
        ;;
    *_test) ;;
    *)
        echo "Refusing unsafe TEST_DB_NAME: name must end in _test" >&2
        exit 1
        ;;
esac

if [[ -z "$SOURCE_DB_NAME" || "$SOURCE_DB_NAME" == "$TEST_DB_NAME" ]]; then
    echo "SOURCE_DB_NAME must be set and must differ from TEST_DB_NAME" >&2
    exit 1
fi

cleanup_failed_create() {
    if [[ "$CREATED_TEST_DB" -eq 1 ]]; then
        echo "Initialization failed; removing only the newly created test database" >&2
        dropdb --if-exists "$TEST_DB_NAME"
    fi
}
trap cleanup_failed_create EXIT

SYSTEM_IDENTIFIER="$(psql --dbname="$SOURCE_DB_NAME" --no-psqlrc --tuples-only --no-align --command="SELECT (pg_control_system()).system_identifier")"
SOURCE_TABLE_COUNT="$(psql --dbname="$SOURCE_DB_NAME" --no-psqlrc --tuples-only --no-align --command="SELECT COUNT(*) FROM pg_tables WHERE schemaname='medorbit'")"

echo "Docker PostgreSQL system identifier: $SYSTEM_IDENTIFIER"
echo "Source database: $SOURCE_DB_NAME (medorbit tables: $SOURCE_TABLE_COUNT)"
echo "Test database plan: $TEST_DB_NAME, schema-only, no seed or application rows"

DATABASE_EXISTS="$(psql --dbname=postgres --no-psqlrc --tuples-only --no-align --command="SELECT 1 FROM pg_database WHERE datname='$TEST_DB_NAME'")"
if [[ "$DATABASE_EXISTS" == "1" ]]; then
    TEST_TABLE_COUNT="$(psql --dbname="$TEST_DB_NAME" --no-psqlrc --tuples-only --no-align --command="SELECT COUNT(*) FROM pg_tables WHERE schemaname='medorbit'")"
    if [[ "$TEST_TABLE_COUNT" -eq 0 ]]; then
        echo "Existing $TEST_DB_NAME has no medorbit schema; refusing to modify it automatically" >&2
        exit 1
    fi
    echo "$TEST_DB_NAME already exists (medorbit tables: $TEST_TABLE_COUNT); no changes applied"
    exit 0
fi

pg_dump \
    --dbname="$SOURCE_DB_NAME" \
    --schema-only \
    --no-owner \
    --no-privileges \
    --file="$SCHEMA_DUMP"

createdb --owner="$PGUSER" "$TEST_DB_NAME"
CREATED_TEST_DB=1

psql \
    --dbname="$TEST_DB_NAME" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --file="$SCHEMA_DUMP"

if psql --dbname="$SOURCE_DB_NAME" --no-psqlrc --tuples-only --no-align \
    --command="SELECT to_regclass('medorbit.schema_migrations') IS NOT NULL" | grep -qx 't'; then
    pg_dump \
        --dbname="$SOURCE_DB_NAME" \
        --data-only \
        --no-owner \
        --no-privileges \
        --table=medorbit.schema_migrations \
        --file=/tmp/medorbit-test-migration-ledger.sql
    psql \
        --dbname="$TEST_DB_NAME" \
        --no-psqlrc \
        --set=ON_ERROR_STOP=1 \
        --file=/tmp/medorbit-test-migration-ledger.sql
fi

# The billing plan catalogue is immutable reference data, not application or
# user seed data. Billing integration tests must start with the same three
# canonical plans while the rest of the disposable database stays empty.
psql \
    --dbname="$TEST_DB_NAME" \
    --no-psqlrc \
    --set=ON_ERROR_STOP=1 \
    --command="INSERT INTO medorbit.subscription_plans
      (plan_code,name_en,name_ar,price_cents,currency,billing_interval,interval_count,grants_pro,sort_order)
      VALUES
        ('free','Free','مجاني',0,'USD','none',1,false,0),
        ('pro_monthly','MedOrbit Pro','مدأوربت برو',2000,'USD','month',1,true,1),
        ('pro_annual','MedOrbit Pro','مدأوربت برو',20000,'USD','year',1,true,2)
      ON CONFLICT (plan_code) DO NOTHING"

TEST_TABLE_COUNT="$(psql --dbname="$TEST_DB_NAME" --no-psqlrc --tuples-only --no-align --command="SELECT COUNT(*) FROM pg_tables WHERE schemaname='medorbit'")"
TEST_USER_COUNT="$(psql --dbname="$TEST_DB_NAME" --no-psqlrc --tuples-only --no-align --command="SELECT COUNT(*) FROM medorbit.users")"

if [[ "$TEST_TABLE_COUNT" -eq 0 || "$TEST_USER_COUNT" -ne 0 ]]; then
    echo "Test database validation failed" >&2
    exit 1
fi

CREATED_TEST_DB=0
echo "$TEST_DB_NAME initialized (medorbit tables: $TEST_TABLE_COUNT; users: $TEST_USER_COUNT)"

-- What CI asserts about the database it just built from scratch.
--
-- Three separate claims, because they fail for different reasons: the
-- pre-migration baseline is complete, every migration in the repository ran,
-- and nothing seeded application data along the way.

\set ON_ERROR_STOP on

DO $$
DECLARE
  latest_version TEXT;
  expected_count INTEGER;
  missing_versions TEXT;
  missing_tables TEXT;
  application_rows INTEGER;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'postgis') THEN
    RAISE EXCEPTION 'PostGIS extension is missing from the bootstrap database';
  END IF;

  -- 1. Baseline tables that no migration creates.
  --
  -- These come from the gitignored db/ SQL on a developer machine and from
  -- scripts/ci/base-schema.sql here.  Migration 014 indexes
  -- virtual_doctor_sessions and fails with "relation does not exist" if the
  -- baseline is incomplete, which is the failure this check exists to catch
  -- before it is buried in a migration error.
  SELECT string_agg(t, ', ' ORDER BY t) INTO missing_tables
  FROM unnest(ARRAY[
    'users', 'user_sessions', 'email_queue', 'specialties', 'clinics',
    'user_profiles', 'patients', 'doctors', 'doctor_availability',
    'appointments', 'doctor_posts',
    'virtual_doctor_sessions', 'virtual_doctor_messages', 'virtual_doctor_reports'
  ]) AS t
  WHERE to_regclass('medorbit.' || t) IS NULL;

  IF missing_tables IS NOT NULL THEN
    RAISE EXCEPTION 'baseline tables missing from the CI database: %', missing_tables;
  END IF;

  -- 2. Tables created by migrations, spot-checked at both ends of the history.
  IF to_regclass('medorbit.outbox_events') IS NULL THEN
    RAISE EXCEPTION 'medorbit.outbox_events is missing';
  END IF;

  IF to_regclass('medorbit.subscriptions') IS NULL THEN
    RAISE EXCEPTION 'medorbit.subscriptions is missing';
  END IF;

  IF to_regclass('medorbit.billing_checkout_sessions') IS NULL THEN
    RAISE EXCEPTION 'medorbit.billing_checkout_sessions is missing';
  END IF;

  -- 3. Every migration from 001 to the newest one recorded, with no gaps.
  --
  -- Derived from what is in the ledger rather than a number written down
  -- here, so adding migration 016 does not require also remembering to edit
  -- this file -- but a migration that silently did not run still fails,
  -- because the gap between 001 and the newest version is what is checked.
  SELECT max(version) INTO latest_version FROM medorbit.schema_migrations;
  IF latest_version IS NULL THEN
    RAISE EXCEPTION 'no migrations were applied at all';
  END IF;

  expected_count := latest_version::INTEGER;

  SELECT string_agg(v, ', ' ORDER BY v) INTO missing_versions
  FROM (
    SELECT lpad(g::TEXT, 3, '0') AS v
    FROM generate_series(1, expected_count) AS g
  ) AS expected
  WHERE NOT EXISTS (
    SELECT 1 FROM medorbit.schema_migrations m WHERE m.version = expected.v
  );

  IF missing_versions IS NOT NULL THEN
    RAISE EXCEPTION 'migrations recorded up to % but these are missing: %',
      latest_version, missing_versions;
  END IF;

  IF latest_version < '015' THEN
    RAISE EXCEPTION 'expected migrations through 015, newest applied is %', latest_version;
  END IF;

  -- 4. No application data. A CI database that has users has been seeded by
  --    something, and whatever seeded it does not belong in the pipeline.
  SELECT count(*) INTO application_rows FROM medorbit.users;
  IF application_rows <> 0 THEN
    RAISE EXCEPTION 'CI bootstrap must not contain user rows, found %', application_rows;
  END IF;
END
$$;

SELECT
  to_regclass('medorbit.virtual_doctor_sessions') AS vd_sessions,
  to_regclass('medorbit.virtual_doctor_messages') AS vd_messages,
  to_regclass('medorbit.virtual_doctor_reports')  AS vd_reports,
  to_regclass('medorbit.outbox_events')           AS outbox_events,
  to_regclass('medorbit.email_queue')             AS email_queue,
  to_regclass('medorbit.subscriptions')           AS subscriptions,
  to_regclass('medorbit.billing_checkout_sessions') AS billing_checkout_sessions,
  (SELECT count(*) FROM medorbit.schema_migrations) AS applied_migrations,
  (SELECT max(version) FROM medorbit.schema_migrations) AS latest_migration,
  (SELECT count(*) FROM medorbit.users) AS user_rows;

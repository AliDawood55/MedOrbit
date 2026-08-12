\set ON_ERROR_STOP on

DO $$
DECLARE
  applied_migrations INTEGER;
  application_rows INTEGER;
BEGIN
  IF to_regclass('medorbit.outbox_events') IS NULL THEN
    RAISE EXCEPTION 'medorbit.outbox_events is missing';
  END IF;

  IF to_regclass('medorbit.email_queue') IS NULL THEN
    RAISE EXCEPTION 'medorbit.email_queue is missing';
  END IF;

  SELECT count(*) INTO applied_migrations
  FROM medorbit.schema_migrations
  WHERE version BETWEEN '001' AND '013';

  IF applied_migrations <> 13 THEN
    RAISE EXCEPTION 'expected 13 applied migrations, found %', applied_migrations;
  END IF;

  SELECT count(*) INTO application_rows FROM medorbit.users;
  IF application_rows <> 0 THEN
    RAISE EXCEPTION 'CI bootstrap must not contain user rows';
  END IF;
END
$$;

SELECT
  to_regclass('medorbit.outbox_events') AS outbox_events,
  to_regclass('medorbit.email_queue') AS email_queue,
  (SELECT count(*) FROM medorbit.schema_migrations) AS applied_migrations,
  (SELECT count(*) FROM medorbit.users) AS user_rows;

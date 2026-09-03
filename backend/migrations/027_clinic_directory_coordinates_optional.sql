-- A clinic application is intentionally reviewed before it is added to the
-- public directory. Its exact map pin can be completed later by the approved
-- clinic owner, so approval must not fail merely because coordinates have not
-- been collected during the application flow.
ALTER TABLE medorbit.clinics
  ALTER COLUMN latitude DROP NOT NULL,
  ALTER COLUMN longitude DROP NOT NULL;

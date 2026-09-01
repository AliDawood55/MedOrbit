-- Public contact links are account-level data shared by patient, doctor, and
-- clinic-owner profiles. JSONB keeps the optional platforms extensible without
-- adding a schema column for every new social network.
ALTER TABLE medorbit.users
  ADD COLUMN IF NOT EXISTS preferences jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN medorbit.users.preferences IS
  'Optional account preferences, including public social_links.';

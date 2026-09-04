-- A clinic account may exist before approval, but only an approved clinic
-- organisation may be shown in the directory or operate a workspace.
-- Application status remains the source of truth while the account is pending.

ALTER TABLE medorbit.clinics
  ADD CONSTRAINT clinics_approval_status_check
  CHECK (approval_status IN ('pending', 'approved', 'rejected', 'suspended'));

CREATE INDEX IF NOT EXISTS clinics_public_directory_idx
  ON medorbit.clinics (city, type, name_en)
  WHERE is_active = true AND approval_status = 'approved';

-- Clinic accounts and a filterable public directory.
-- Clinics remain separately moderated organisations: a verified personal
-- account applies first, then an administrator approves a clinic owner.

DO $$
DECLARE constraint_name text;
BEGIN
  SELECT conname INTO constraint_name
  FROM pg_constraint
  WHERE conrelid = 'medorbit.users'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%role%';
  IF constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE medorbit.users DROP CONSTRAINT %I', constraint_name);
  END IF;
END $$;

ALTER TABLE medorbit.users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('patient', 'doctor', 'clinic', 'admin', 'super_admin'));

ALTER TABLE medorbit.clinics
  ADD COLUMN IF NOT EXISTS owner_user_id uuid REFERENCES medorbit.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approval_status varchar(20) NOT NULL DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS approved_at timestamptz,
  ADD COLUMN IF NOT EXISTS approved_by_user_id uuid REFERENCES medorbit.users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS clinics_owner_user_id_unique
  ON medorbit.clinics(owner_user_id) WHERE owner_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS clinics_city_idx ON medorbit.clinics(city);
CREATE INDEX IF NOT EXISTS clinics_services_gin_idx ON medorbit.clinics USING gin(services);

CREATE TABLE IF NOT EXISTS medorbit.clinic_applications (
  id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  user_id uuid NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  name_ar varchar(200) NOT NULL,
  name_en varchar(200) NOT NULL,
  address_ar text NOT NULL,
  address_en text NOT NULL,
  city varchar(100) NOT NULL,
  region varchar(100),
  phone varchar(30) NOT NULL,
  email varchar(255),
  website varchar(255),
  type varchar(50) NOT NULL DEFAULT 'clinic',
  services text[] NOT NULL DEFAULT '{}',
  registration_number varchar(120) NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'pending',
  submitted_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reviewed_at timestamptz,
  reviewed_by_user_id uuid REFERENCES medorbit.users(id) ON DELETE SET NULL,
  rejection_reason text,
  approved_clinic_id uuid REFERENCES medorbit.clinics(id) ON DELETE SET NULL,
  withdrawn_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT clinic_applications_status_check
    CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
  CONSTRAINT clinic_applications_type_check
    CHECK (type IN ('clinic', 'dental', 'hospital', 'laboratory', 'radiology'))
);

CREATE INDEX IF NOT EXISTS clinic_applications_status_idx
  ON medorbit.clinic_applications(status, submitted_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS clinic_applications_pending_per_user
  ON medorbit.clinic_applications(user_id) WHERE status = 'pending';

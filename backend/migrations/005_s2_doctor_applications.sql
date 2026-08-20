ALTER TABLE medorbit.doctors
  ADD COLUMN IF NOT EXISTS approval_status VARCHAR(16) NOT NULL DEFAULT 'approved',
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_by_user_id UUID REFERENCES medorbit.users(id),
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS suspended_by_user_id UUID REFERENCES medorbit.users(id),
  ADD COLUMN IF NOT EXISTS suspension_reason TEXT;
ALTER TABLE medorbit.doctors DROP CONSTRAINT IF EXISTS doctors_approval_status_check;
ALTER TABLE medorbit.doctors ADD CONSTRAINT doctors_approval_status_check CHECK (approval_status IN ('approved','suspended'));
UPDATE medorbit.doctors SET approval_status='approved', approved_at=COALESCE(approved_at, created_at, NOW()) WHERE approval_status IS NULL OR approved_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS doctors_license_number_unique_nonempty ON medorbit.doctors (lower(trim(medical_license_number))) WHERE medical_license_number IS NOT NULL AND trim(medical_license_number) <> '';

CREATE TABLE medorbit.doctor_applications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES medorbit.users(id),
  specialty_id UUID NOT NULL REFERENCES medorbit.specialties(id),
  medical_license_number VARCHAR(255) NOT NULL,
  sub_specialty VARCHAR(255), years_of_experience INTEGER,
  education TEXT[], certifications TEXT[], bio_ar TEXT, bio_en TEXT,
  consultation_fee NUMERIC(10,2), consultation_duration INTEGER,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  reviewed_by_user_id UUID REFERENCES medorbit.users(id), reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT, withdrawn_at TIMESTAMPTZ,
  approved_doctor_id UUID UNIQUE REFERENCES medorbit.doctors(id),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT doctor_applications_status_check CHECK (status IN ('pending','approved','rejected','withdrawn')),
  CONSTRAINT doctor_applications_license_nonempty CHECK (length(trim(medical_license_number)) > 0)
);
CREATE UNIQUE INDEX doctor_applications_one_pending_user ON medorbit.doctor_applications(user_id) WHERE status='pending';
CREATE UNIQUE INDEX doctor_applications_license_approved ON medorbit.doctor_applications(lower(trim(medical_license_number))) WHERE status='approved';
CREATE INDEX doctor_applications_status_submitted ON medorbit.doctor_applications(status, submitted_at DESC);

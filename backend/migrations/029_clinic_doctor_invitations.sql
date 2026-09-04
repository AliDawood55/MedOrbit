-- Clinics may propose a workplace relationship, but only the doctor can
-- accept it. Assignment history remains intact after a relationship ends.
ALTER TABLE medorbit.doctor_clinic_assignments
  ADD COLUMN IF NOT EXISTS joined_at timestamptz,
  ADD COLUMN IF NOT EXISTS ended_at timestamptz,
  ADD COLUMN IF NOT EXISTS source varchar(40) NOT NULL DEFAULT 'legacy';

UPDATE medorbit.doctor_clinic_assignments
SET joined_at=COALESCE(joined_at, created_at), source=CASE WHEN source='legacy' THEN 'legacy' ELSE source END;

CREATE TABLE IF NOT EXISTS medorbit.clinic_doctor_invitations (
  id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  clinic_id uuid NOT NULL REFERENCES medorbit.clinics(id) ON DELETE CASCADE,
  doctor_id uuid NOT NULL REFERENCES medorbit.doctors(id) ON DELETE CASCADE,
  invited_by_user_id uuid NOT NULL REFERENCES medorbit.users(id) ON DELETE RESTRICT,
  message text,
  status varchar(20) NOT NULL DEFAULT 'pending',
  responded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT clinic_doctor_invitation_status_check CHECK (status IN ('pending','accepted','declined','cancelled'))
);

CREATE UNIQUE INDEX IF NOT EXISTS clinic_doctor_invitation_pending_unique
  ON medorbit.clinic_doctor_invitations(clinic_id, doctor_id) WHERE status='pending';
CREATE INDEX IF NOT EXISTS clinic_doctor_invitation_doctor_idx
  ON medorbit.clinic_doctor_invitations(doctor_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS clinic_doctor_invitation_clinic_idx
  ON medorbit.clinic_doctor_invitations(clinic_id, status, created_at DESC);

ALTER TABLE medorbit.doctor_clinic_assignments
  ADD COLUMN IF NOT EXISTS invitation_id uuid REFERENCES medorbit.clinic_doctor_invitations(id) ON DELETE SET NULL;

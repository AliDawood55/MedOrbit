-- Approved clinic owners may manage operational contacts, but never silently
-- replace a credential that administrators verified during approval.
ALTER TABLE medorbit.clinics
  ADD COLUMN IF NOT EXISTS registration_number varchar(120);

UPDATE medorbit.clinics c
SET registration_number = a.registration_number
FROM medorbit.clinic_applications a
WHERE a.approved_clinic_id = c.id
  AND c.registration_number IS NULL;

CREATE TABLE IF NOT EXISTS medorbit.clinic_contact_emails (
  id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  clinic_id uuid NOT NULL REFERENCES medorbit.clinics(id) ON DELETE CASCADE,
  email varchar(255) NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'pending',
  verification_token_hash varchar(64),
  verification_expires_at timestamptz,
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT clinic_contact_emails_status_check CHECK (status IN ('pending','verified')),
  CONSTRAINT clinic_contact_emails_email_check CHECK (email = lower(email))
);

CREATE UNIQUE INDEX IF NOT EXISTS clinic_contact_emails_clinic_email_unique
  ON medorbit.clinic_contact_emails(clinic_id, email);
CREATE UNIQUE INDEX IF NOT EXISTS clinic_contact_emails_verified_email_unique
  ON medorbit.clinic_contact_emails(lower(email)) WHERE status='verified';
CREATE INDEX IF NOT EXISTS clinic_contact_emails_clinic_status_idx
  ON medorbit.clinic_contact_emails(clinic_id, status);
CREATE UNIQUE INDEX IF NOT EXISTS clinic_contact_email_token_unique
  ON medorbit.clinic_contact_emails(verification_token_hash)
  WHERE verification_token_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS medorbit.clinic_credential_change_requests (
  id uuid PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  clinic_id uuid NOT NULL REFERENCES medorbit.clinics(id) ON DELETE CASCADE,
  requested_by_user_id uuid NOT NULL REFERENCES medorbit.users(id) ON DELETE RESTRICT,
  current_registration_number varchar(120),
  requested_registration_number varchar(120) NOT NULL,
  reason text NOT NULL,
  status varchar(20) NOT NULL DEFAULT 'pending',
  reviewed_by_user_id uuid REFERENCES medorbit.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  decision_note text,
  created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT clinic_credential_change_status_check CHECK (status IN ('pending','approved','rejected'))
);

CREATE UNIQUE INDEX IF NOT EXISTS clinic_credential_change_one_pending_per_clinic
  ON medorbit.clinic_credential_change_requests(clinic_id) WHERE status='pending';
CREATE INDEX IF NOT EXISTS clinic_credential_change_review_idx
  ON medorbit.clinic_credential_change_requests(status, created_at DESC);

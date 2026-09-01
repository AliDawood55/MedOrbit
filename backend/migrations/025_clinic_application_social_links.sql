-- Clinic applicants may prepare public links before approval. They become
-- account links only when the applicant is promoted to the clinic role.
ALTER TABLE medorbit.clinic_applications
  ADD COLUMN IF NOT EXISTS social_links jsonb NOT NULL DEFAULT '{}'::jsonb;

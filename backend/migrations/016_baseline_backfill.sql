-- Canonical-schema backfill, slice 1: doctor reviews.
--
-- Extracted from the protected canonical PostgreSQL schema on 2026-08-24.
-- This is additive: it is a no-op on the canonical database and supplies the
-- missing table, constraints, and read indexes on a fresh tracked bootstrap.

CREATE TABLE IF NOT EXISTS medorbit.doctor_reviews (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  appointment_id uuid NOT NULL,
  patient_id uuid NOT NULL,
  doctor_id uuid NOT NULL,
  rating integer NOT NULL,
  review_text_ar text,
  review_text_en text,
  professionalism_rating integer,
  treatment_rating integer,
  communication_rating integer,
  is_visible boolean DEFAULT true,
  is_approved boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT doctor_reviews_pkey PRIMARY KEY (id),
  CONSTRAINT doctor_reviews_rating_check CHECK (rating >= 1 AND rating <= 5),
  CONSTRAINT doctor_reviews_professionalism_rating_check CHECK (professionalism_rating >= 1 AND professionalism_rating <= 5),
  CONSTRAINT doctor_reviews_treatment_rating_check CHECK (treatment_rating >= 1 AND treatment_rating <= 5),
  CONSTRAINT doctor_reviews_communication_rating_check CHECK (communication_rating >= 1 AND communication_rating <= 5),
  CONSTRAINT doctor_reviews_appointment_id_key UNIQUE (appointment_id),
  CONSTRAINT doctor_reviews_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES medorbit.appointments(id) ON DELETE CASCADE,
  CONSTRAINT doctor_reviews_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES medorbit.patients(id),
  CONSTRAINT doctor_reviews_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES medorbit.doctors(id)
);

CREATE INDEX IF NOT EXISTS idx_reviews_doctor
  ON medorbit.doctor_reviews (doctor_id);
CREATE INDEX IF NOT EXISTS idx_reviews_doctor_visible
  ON medorbit.doctor_reviews (doctor_id, is_visible, created_at DESC)
  WHERE is_visible = true;
CREATE INDEX IF NOT EXISTS idx_reviews_rating
  ON medorbit.doctor_reviews (rating);

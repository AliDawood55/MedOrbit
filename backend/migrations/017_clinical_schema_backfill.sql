-- Canonical-schema backfill, slice 2: clinical records and prescriptions.
-- Extracted from the protected canonical PostgreSQL schema on 2026-08-24.

CREATE SEQUENCE IF NOT EXISTS medorbit.record_seq;
CREATE SEQUENCE IF NOT EXISTS medorbit.prescription_seq;

CREATE TABLE IF NOT EXISTS medorbit.medical_records (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  record_number character varying(20) NOT NULL,
  patient_id uuid NOT NULL,
  doctor_id uuid NOT NULL,
  appointment_id uuid,
  record_type character varying(50) DEFAULT 'consultation'::character varying,
  chief_complaint text,
  symptoms text[],
  diagnosis text,
  diagnosis_codes jsonb,
  treatment_plan text,
  prognosis text,
  vitals jsonb DEFAULT '{}'::jsonb,
  clinical_notes text,
  doctor_notes text,
  is_draft boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  visible_to_patient boolean DEFAULT false NOT NULL,
  CONSTRAINT medical_records_pkey PRIMARY KEY (id),
  CONSTRAINT medical_records_record_number_key UNIQUE (record_number),
  CONSTRAINT medical_records_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES medorbit.appointments(id),
  CONSTRAINT medical_records_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES medorbit.doctors(id),
  CONSTRAINT medical_records_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES medorbit.patients(id)
);

CREATE TABLE IF NOT EXISTS medorbit.medical_record_attachments (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  record_id uuid NOT NULL,
  file_name character varying(255) NOT NULL,
  file_type character varying(50),
  file_path character varying(500) NOT NULL,
  file_size_bytes integer,
  mime_type character varying(100),
  uploaded_by uuid,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT medical_record_attachments_pkey PRIMARY KEY (id),
  CONSTRAINT medical_record_attachments_record_id_fkey FOREIGN KEY (record_id) REFERENCES medorbit.medical_records(id) ON DELETE CASCADE,
  CONSTRAINT medical_record_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES medorbit.users(id)
);

CREATE TABLE IF NOT EXISTS medorbit.prescriptions (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  prescription_number character varying(20) NOT NULL,
  patient_id uuid NOT NULL,
  doctor_id uuid NOT NULL,
  appointment_id uuid,
  prescription_date date NOT NULL,
  valid_until date,
  status character varying(20) DEFAULT 'active'::character varying,
  diagnosis text,
  instructions text,
  doctor_notes text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT prescriptions_pkey PRIMARY KEY (id),
  CONSTRAINT prescriptions_prescription_number_key UNIQUE (prescription_number),
  CONSTRAINT chk_prescription_status CHECK ((status)::text = ANY (ARRAY['active'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])),
  CONSTRAINT prescriptions_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES medorbit.appointments(id),
  CONSTRAINT prescriptions_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES medorbit.doctors(id),
  CONSTRAINT prescriptions_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES medorbit.patients(id)
);

CREATE TABLE IF NOT EXISTS medorbit.prescription_items (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  prescription_id uuid NOT NULL,
  medication_name_ar character varying(200) NOT NULL,
  medication_name_en character varying(200) NOT NULL,
  dosage character varying(100) NOT NULL,
  frequency character varying(100) NOT NULL,
  duration character varying(100),
  quantity integer NOT NULL,
  instructions text,
  refills_allowed integer DEFAULT 0,
  refills_used integer DEFAULT 0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT prescription_items_pkey PRIMARY KEY (id),
  CONSTRAINT prescription_items_prescription_id_fkey FOREIGN KEY (prescription_id) REFERENCES medorbit.prescriptions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_prescriptions_doctor ON medorbit.prescriptions (doctor_id);
CREATE INDEX IF NOT EXISTS idx_prescriptions_patient ON medorbit.prescriptions (patient_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'update_prescriptions_updated_at'
      AND tgrelid = 'medorbit.prescriptions'::regclass
  ) THEN
    CREATE TRIGGER update_prescriptions_updated_at
      BEFORE UPDATE ON medorbit.prescriptions
      FOR EACH ROW EXECUTE FUNCTION medorbit.update_updated_at_column();
  END IF;
END
$$;

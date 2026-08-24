-- Canonical-schema backfill, final inventory slice.
-- Extracted from the protected canonical PostgreSQL schema on 2026-08-24.

CREATE TABLE IF NOT EXISTS medorbit.appointment_status_history (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  appointment_id uuid NOT NULL,
  old_status character varying(50),
  new_status character varying(50) NOT NULL,
  changed_by uuid,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT appointment_status_history_pkey PRIMARY KEY (id),
  CONSTRAINT fk_status_history_appointment FOREIGN KEY (appointment_id) REFERENCES medorbit.appointments(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.audit_logs (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid,
  user_role character varying(20),
  action character varying(50) NOT NULL,
  entity_type character varying(50),
  entity_id uuid,
  old_values jsonb,
  new_values jsonb,
  ip_address character varying(50),
  user_agent text,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT audit_logs_pkey PRIMARY KEY (id),
  CONSTRAINT audit_logs_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id)
);

CREATE TABLE IF NOT EXISTS medorbit.clinics_backup_20260721 (
  id uuid,
  name_ar character varying(200),
  name_en character varying(200),
  address_ar text,
  address_en text,
  city character varying(100),
  region character varying(100),
  latitude numeric(10,8),
  longitude numeric(11,8),
  phone character varying(20),
  email character varying(255),
  website character varying(255),
  operating_hours jsonb,
  services text[],
  insurance_accepted text[],
  images jsonb[],
  logo_url character varying(500),
  is_active boolean,
  verification_status character varying(20),
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  location public.geography(Point,4326),
  type character varying(50)
);

CREATE TABLE IF NOT EXISTS medorbit.conversation_titles (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  conversation_id uuid NOT NULL,
  title character varying(300) NOT NULL,
  is_auto_generated boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT conversation_titles_pkey PRIMARY KEY (id),
  CONSTRAINT conversation_titles_conversation_id_key UNIQUE (conversation_id),
  CONSTRAINT conversation_titles_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES medorbit.chatbot_conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.doctor_clinic_assignments (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  doctor_id uuid NOT NULL,
  clinic_id uuid NOT NULL,
  consultation_fee_override numeric(10,2),
  schedule jsonb,
  is_primary boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT doctor_clinic_assignments_pkey PRIMARY KEY (id),
  CONSTRAINT doctor_clinic_assignments_doctor_id_clinic_id_key UNIQUE (doctor_id, clinic_id),
  CONSTRAINT doctor_clinic_assignments_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES medorbit.clinics(id) ON DELETE CASCADE,
  CONSTRAINT doctor_clinic_assignments_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES medorbit.doctors(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.generated_reports (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  template_id uuid,
  generated_by uuid,
  report_title character varying(200),
  report_type character varying(50),
  report_data jsonb,
  format character varying(20) DEFAULT 'json'::character varying,
  file_path character varying(500),
  generated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  expires_at timestamp with time zone,
  CONSTRAINT generated_reports_pkey PRIMARY KEY (id),
  CONSTRAINT generated_reports_generated_by_fkey FOREIGN KEY (generated_by) REFERENCES medorbit.users(id)
);

CREATE SEQUENCE IF NOT EXISTS medorbit.medical_knowledge_id_seq START WITH 1 INCREMENT BY 1 NO MINVALUE NO MAXVALUE CACHE 1;

CREATE TABLE IF NOT EXISTS medorbit.medical_knowledge (
  id bigint DEFAULT nextval('medorbit.medical_knowledge_id_seq'::regclass) NOT NULL,
  source text NOT NULL,
  chunk_index integer NOT NULL,
  chunk_text text NOT NULL,
  embedding real[] NOT NULL,
  embedding_dim integer NOT NULL,
  embedding_model text NOT NULL,
  page_start integer,
  page_end integer,
  content_hash character(64) NOT NULL,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT medical_knowledge_pkey PRIMARY KEY (id),
  CONSTRAINT ck_medical_knowledge_dim CHECK (embedding_dim = array_length(embedding, 1)),
  CONSTRAINT uq_medical_knowledge_source_chunk UNIQUE (source, chunk_index)
);
ALTER SEQUENCE medorbit.medical_knowledge_id_seq OWNED BY medorbit.medical_knowledge.id;

CREATE TABLE IF NOT EXISTS medorbit.medications (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  name_ar character varying(200) NOT NULL,
  name_en character varying(200) NOT NULL,
  generic_name character varying(200),
  brand_names text[],
  drug_class character varying(100),
  active_ingredients text[],
  contraindications text[],
  side_effects text[],
  known_interactions jsonb,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT medications_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS medorbit.nablus_regions (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  name_ar character varying(100) NOT NULL,
  name_en character varying(100) NOT NULL,
  boundary_geojson text,
  is_active boolean DEFAULT true,
  CONSTRAINT nablus_regions_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS medorbit.symptom_specialty_mappings (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  symptom_keyword character varying(200) NOT NULL,
  symptom_keyword_ar character varying(200),
  specialty_id uuid NOT NULL,
  weight numeric(4,2) DEFAULT 1.00,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT symptom_specialty_mappings_pkey PRIMARY KEY (id),
  CONSTRAINT symptom_specialty_mappings_specialty_id_fkey FOREIGN KEY (specialty_id) REFERENCES medorbit.specialties(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.symptom_triage_sessions (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid,
  session_id character varying(100),
  reported_symptoms jsonb NOT NULL,
  triage_level character varying(20),
  recommended_specialty_id uuid,
  recommended_specialty_name_ar character varying(100),
  recommended_specialty_name_en character varying(100),
  confidence_score numeric(5,4),
  recommendations text,
  follow_up_action character varying(50),
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT symptom_triage_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT symptom_triage_sessions_recommended_specialty_id_fkey FOREIGN KEY (recommended_specialty_id) REFERENCES medorbit.specialties(id),
  CONSTRAINT symptom_triage_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id)
);

CREATE TABLE IF NOT EXISTS medorbit.user_chat_preferences (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid NOT NULL,
  preferred_language character varying(5) DEFAULT 'auto'::character varying,
  response_style character varying(20) DEFAULT 'balanced'::character varying,
  theme character varying(10) DEFAULT 'light'::character varying,
  model_preference character varying(50) DEFAULT 'qwen2:7b'::character varying,
  streaming_enabled boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT user_chat_preferences_pkey PRIMARY KEY (id),
  CONSTRAINT user_chat_preferences_user_id_key UNIQUE (user_id),
  CONSTRAINT user_chat_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE CASCADE
);

COMMENT ON TABLE medorbit.audit_logs IS 'System audit trail';
COMMENT ON TABLE medorbit.generated_reports IS 'Generated analytics reports';
COMMENT ON TABLE medorbit.medical_knowledge IS 'RAG chunk store. embedding is REAL[] because the postgis image has no pgvector; see migration 20 header for the swap-in path.';
COMMENT ON TABLE medorbit.medications IS 'Drug/medication database';
COMMENT ON TABLE medorbit.nablus_regions IS 'Geographic regions in Nablus for map clustering';
COMMENT ON TABLE medorbit.doctor_clinic_assignments IS 'Many-to-many doctor-clinic relationships';
COMMENT ON TABLE medorbit.symptom_triage_sessions IS 'AI symptom analysis sessions';

CREATE OR REPLACE FUNCTION medorbit.update_titles_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_appointment_status_history_appointment ON medorbit.appointment_status_history (appointment_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON medorbit.audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON medorbit.audit_logs (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_user ON medorbit.audit_logs (user_id);
CREATE INDEX IF NOT EXISTS idx_conv_titles_conversation ON medorbit.conversation_titles (conversation_id);
CREATE INDEX IF NOT EXISTS idx_dca_clinic ON medorbit.doctor_clinic_assignments (clinic_id);
CREATE INDEX IF NOT EXISTS idx_dca_doctor ON medorbit.doctor_clinic_assignments (doctor_id);
CREATE INDEX IF NOT EXISTS idx_reports_generated_by ON medorbit.generated_reports (generated_by);
CREATE INDEX IF NOT EXISTS idx_medical_knowledge_hash ON medorbit.medical_knowledge (content_hash);
CREATE INDEX IF NOT EXISTS idx_medical_knowledge_source ON medorbit.medical_knowledge (source);
CREATE INDEX IF NOT EXISTS idx_medications_name ON medorbit.medications (name_en);
CREATE INDEX IF NOT EXISTS idx_ssm_specialty ON medorbit.symptom_specialty_mappings (specialty_id);
CREATE INDEX IF NOT EXISTS idx_ssm_symptom ON medorbit.symptom_specialty_mappings (symptom_keyword);
CREATE INDEX IF NOT EXISTS idx_ssm_symptom_ar ON medorbit.symptom_specialty_mappings (symptom_keyword_ar);
CREATE INDEX IF NOT EXISTS idx_triage_user ON medorbit.symptom_triage_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_user_prefs_user ON medorbit.user_chat_preferences (user_id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_conv_titles_updated_at' AND tgrelid = 'medorbit.conversation_titles'::regclass) THEN
    CREATE TRIGGER update_conv_titles_updated_at BEFORE UPDATE ON medorbit.conversation_titles FOR EACH ROW EXECUTE FUNCTION medorbit.update_titles_updated_at();
  END IF;
END
$$;

-- MedOrbit migration prerequisite baseline for disposable CI databases.
--
-- This is deliberately schema-only: no users, patients, seed rows, or
-- environment-specific data belong in CI.  The numbered migrations are the
-- incremental history after this baseline and are applied separately by the
-- existing migration runner.
--
-- WHAT BELONGS HERE
-- Every table that existed BEFORE migration 001 and is still referenced by a
-- migration.  A developer machine gets those tables from the SQL under db/,
-- which is gitignored (see .gitignore) and therefore does not exist on a CI
-- runner -- so anything a migration expects to already be there has to be
-- restated in this file or CI is bootstrapping a different database from
-- everybody else's.  When a migration starts referencing a pre-existing
-- table for the first time, check it is here.

\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS medorbit;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- Clinic/discovery queries rely on PostGIS. The postgis/postgis image makes
-- this available, but the extension must be enabled in each fresh database.
CREATE EXTENSION IF NOT EXISTS postgis;

SET search_path TO medorbit, public;

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = CURRENT_TIMESTAMP;
  RETURN NEW;
END;
$$;

-- Authentication foundation present before migration 001.
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255),
  role VARCHAR(20) NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  email_verified BOOLEAN DEFAULT FALSE,
  preferred_language VARCHAR(5) DEFAULT 'ar',
  failed_login_attempts INTEGER DEFAULT 0,
  locked_until TIMESTAMP,
  preferences JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  deleted_at TIMESTAMPTZ,
  google_id VARCHAR(255) UNIQUE,
  CONSTRAINT users_role_check CHECK (role IN ('patient', 'doctor', 'admin'))
);

CREATE TABLE user_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token VARCHAR(500) NOT NULL,
  device_info JSONB,
  ip_address VARCHAR(50),
  user_agent TEXT,
  device_name VARCHAR(100),
  platform VARCHAR(20),
  revoked_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_token ON user_sessions(refresh_token);
CREATE INDEX idx_sessions_user ON user_sessions(user_id);

CREATE TABLE email_queue (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  recipient_email VARCHAR(255) NOT NULL,
  recipient_name VARCHAR(200),
  subject VARCHAR(500) NOT NULL,
  body_html TEXT NOT NULL,
  body_text TEXT,
  status VARCHAR(20) DEFAULT 'pending',
  attempts INTEGER DEFAULT 0,
  last_attempt_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ,
  error_message TEXT,
  scheduled_for TIMESTAMPTZ,
  priority INTEGER DEFAULT 5,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_email_queue_status
  ON email_queue(status) WHERE status = 'pending';

-- Base clinical tables referenced by migrations 005-013.
CREATE TABLE specialties (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name_ar VARCHAR(100) NOT NULL,
  name_en VARCHAR(100) NOT NULL,
  description_ar TEXT,
  description_en TEXT,
  icon VARCHAR(50),
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE clinics (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name_ar VARCHAR(200) NOT NULL,
  name_en VARCHAR(200) NOT NULL,
  address_ar TEXT NOT NULL,
  address_en TEXT NOT NULL,
  city VARCHAR(100) DEFAULT 'Nablus',
  region VARCHAR(100),
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  phone VARCHAR(20),
  email VARCHAR(255),
  website VARCHAR(255),
  type VARCHAR(50),
  operating_hours JSONB DEFAULT '{}'::jsonb,
  services TEXT[],
  insurance_accepted TEXT[],
  images JSONB[] DEFAULT '{}',
  logo_url VARCHAR(500),
  is_active BOOLEAN DEFAULT TRUE,
  verification_status VARCHAR(20) DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_profiles (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  first_name_ar VARCHAR(100) NOT NULL,
  last_name_ar VARCHAR(100) NOT NULL,
  first_name_en VARCHAR(100) NOT NULL,
  last_name_en VARCHAR(100) NOT NULL,
  phone VARCHAR(20),
  date_of_birth DATE,
  gender VARCHAR(10),
  profile_image_url VARCHAR(500),
  avatar_url TEXT,
  address TEXT,
  city VARCHAR(100) DEFAULT 'Nablus',
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE patients (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blood_type VARCHAR(5),
  allergies TEXT[],
  chronic_conditions TEXT[],
  emergency_contact_name VARCHAR(200),
  emergency_contact_phone VARCHAR(20),
  insurance_provider VARCHAR(100),
  insurance_policy_number VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE doctors (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  medical_license_number VARCHAR(100) UNIQUE,
  specialty_id UUID REFERENCES specialties(id),
  sub_specialty VARCHAR(100),
  years_of_experience INTEGER DEFAULT 0,
  consultation_fee DECIMAL(10, 2) DEFAULT 0.00,
  consultation_duration INTEGER DEFAULT 30,
  education TEXT[],
  certifications TEXT[],
  professional_bio_ar TEXT,
  professional_bio_en TEXT,
  is_accepting_patients BOOLEAN DEFAULT TRUE,
  average_rating DECIMAL(3, 2) DEFAULT 0.00,
  total_ratings INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE doctor_availability (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
  clinic_id UUID REFERENCES clinics(id),
  day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
  specific_date DATE,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  slot_duration INTEGER DEFAULT 30,
  is_telemedicine BOOLEAN DEFAULT FALSE,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE appointments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  appointment_number VARCHAR(20) UNIQUE NOT NULL,
  patient_id UUID NOT NULL REFERENCES patients(id),
  doctor_id UUID NOT NULL REFERENCES doctors(id),
  clinic_id UUID REFERENCES clinics(id),
  scheduled_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  duration_minutes INTEGER NOT NULL,
  appointment_type VARCHAR(20) DEFAULT 'in_person',
  status VARCHAR(20) DEFAULT 'scheduled',
  reason_for_visit TEXT,
  notes TEXT,
  meeting_link VARCHAR(500),
  cancelled_at TIMESTAMPTZ,
  cancelled_by UUID REFERENCES users(id),
  cancellation_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_appointment_status
    CHECK (status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
  CONSTRAINT chk_appointment_type
    CHECK (appointment_type IN ('in_person', 'telemedicine'))
);

CREATE TABLE doctor_posts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
  title_ar VARCHAR(150),
  title_en VARCHAR(150),
  category VARCHAR(30) NOT NULL DEFAULT 'health_tip',
  body TEXT NOT NULL,
  is_published BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chk_doctor_posts_title
    CHECK (title_ar IS NOT NULL OR title_en IS NOT NULL)
);

-- AI Virtual Doctor tables, created before migration 001 by
-- db/16_virtual_doctor_tables.sql.  Reproduced here column for column from
-- the live schema (pg_dump of medorbit.virtual_doctor_*), because db/ is
-- gitignored and never reaches a CI runner.  Migration 014 adds an ownership
-- index to virtual_doctor_sessions and fails outright without this.
--
-- All three are included rather than only the one migration 014 names.  The
-- messages and reports tables are the same baseline, they are what the
-- Virtual Doctor code reads and writes, and a CI database that has the parent
-- but not the children is a shape that exists nowhere else -- which is the
-- class of difference this whole file is meant to remove, not create.
CREATE TABLE virtual_doctor_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  session_id VARCHAR(64) NOT NULL UNIQUE,
  language VARCHAR(5) NOT NULL DEFAULT 'en',
  chief_complaint VARCHAR(100),
  -- greeting | interviewing | reasoning | complete
  phase VARCHAR(30) NOT NULL DEFAULT 'greeting',
  patient_profile JSONB NOT NULL DEFAULT '{}',
  -- emergency | urgent | routine
  urgency_level VARCHAR(20),
  recommended_specialty_id UUID REFERENCES specialties(id),
  differential JSONB,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE virtual_doctor_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID NOT NULL REFERENCES virtual_doctor_sessions(id) ON DELETE CASCADE,
  -- patient | doctor
  role VARCHAR(10) NOT NULL,
  message_text TEXT NOT NULL,
  audio_url TEXT,
  extracted_entities JSONB,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE virtual_doctor_reports (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id UUID NOT NULL REFERENCES virtual_doctor_sessions(id) ON DELETE CASCADE,
  pdf_path TEXT,
  report_json JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_virtual_doctor_messages_session ON virtual_doctor_messages(session_id);
CREATE INDEX idx_virtual_doctor_reports_session ON virtual_doctor_reports(session_id);

-- Deliberately NOT created here: virtual_doctor_sessions_owner_lookup.  That
-- index is migration 014's, and leaving it out is what makes CI actually run
-- the statement this failure was about instead of skipping it.

CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_doctor_posts_updated_at
  BEFORE UPDATE ON doctor_posts
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

COMMIT;

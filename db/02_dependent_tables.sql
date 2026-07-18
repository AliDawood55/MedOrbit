-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Dependent Tables (FK references to base tables)
-- Ordered by dependency depth
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- Table 1: User Profiles (FK -> users)
-- =====================================================
CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    first_name_ar VARCHAR(100) NOT NULL,
    last_name_ar VARCHAR(100) NOT NULL,
    first_name_en VARCHAR(100) NOT NULL,
    last_name_en VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    date_of_birth DATE,
    gender VARCHAR(10) CHECK (gender IN ('male', 'female', 'other')),
    profile_image_url VARCHAR(500),
    avatar_url TEXT,
    address TEXT,
    city VARCHAR(100) DEFAULT 'Nablus',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 2: User Sessions (FK -> users)
-- Migrations 003 merged: revoked_at, last_used_at, device_name, platform, updated_at
-- =====================================================
CREATE TABLE IF NOT EXISTS user_sessions (
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
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 3: Patients (FK -> users)
-- =====================================================
CREATE TABLE IF NOT EXISTS patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blood_type VARCHAR(5),
    allergies TEXT[],
    chronic_conditions TEXT[],
    emergency_contact_name VARCHAR(200),
    emergency_contact_phone VARCHAR(20),
    insurance_provider VARCHAR(100),
    insurance_policy_number VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 4: Doctors (FK -> users, FK -> specialties)
-- =====================================================
CREATE TABLE IF NOT EXISTS doctors (
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
    is_accepting_patients BOOLEAN DEFAULT true,
    average_rating DECIMAL(3, 2) DEFAULT 0.00,
    total_ratings INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 5: Doctor-Clinic Assignments (FK -> doctors, FK -> clinics)
-- =====================================================
CREATE TABLE IF NOT EXISTS doctor_clinic_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    clinic_id UUID NOT NULL REFERENCES clinics(id) ON DELETE CASCADE,
    consultation_fee_override DECIMAL(10, 2),
    schedule JSONB,
    is_primary BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(doctor_id, clinic_id)
);

-- =====================================================
-- Table 6: Doctor Availability (FK -> doctors, FK -> clinics)
-- =====================================================
CREATE TABLE IF NOT EXISTS doctor_availability (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    clinic_id UUID REFERENCES clinics(id),
    day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
    specific_date DATE,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    slot_duration INTEGER DEFAULT 30,
    is_telemedicine BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 7: Appointments (FK -> patients, FK -> doctors, FK -> clinics, FK -> users)
-- =====================================================
CREATE TABLE IF NOT EXISTS appointments (
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
    cancelled_at TIMESTAMP WITH TIME ZONE,
    cancelled_by UUID REFERENCES users(id),
    cancellation_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_appointment_status CHECK (status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show')),
    CONSTRAINT chk_appointment_type CHECK (appointment_type IN ('in_person', 'telemedicine'))
);

-- =====================================================
-- Table 8: Medical Records (FK -> patients, FK -> doctors, FK -> appointments)
-- =====================================================
CREATE TABLE IF NOT EXISTS medical_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    record_number VARCHAR(20) UNIQUE NOT NULL,
    patient_id UUID NOT NULL REFERENCES patients(id),
    doctor_id UUID NOT NULL REFERENCES doctors(id),
    appointment_id UUID REFERENCES appointments(id),
    record_type VARCHAR(50) DEFAULT 'consultation',
    chief_complaint TEXT,
    symptoms TEXT[],
    diagnosis TEXT,
    diagnosis_codes JSONB,
    treatment_plan TEXT,
    prognosis TEXT,
    vitals JSONB DEFAULT '{}',
    clinical_notes TEXT,
    doctor_notes TEXT,
    is_draft BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 9: Medical Record Attachments (FK -> medical_records, FK -> users)
-- =====================================================
CREATE TABLE IF NOT EXISTS medical_record_attachments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    record_id UUID NOT NULL REFERENCES medical_records(id) ON DELETE CASCADE,
    file_name VARCHAR(255) NOT NULL,
    file_type VARCHAR(50),
    file_path VARCHAR(500) NOT NULL,
    file_size_bytes INTEGER,
    mime_type VARCHAR(100),
    uploaded_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 10: Prescriptions (FK -> patients, FK -> doctors, FK -> appointments)
-- =====================================================
CREATE TABLE IF NOT EXISTS prescriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    prescription_number VARCHAR(20) UNIQUE NOT NULL,
    patient_id UUID NOT NULL REFERENCES patients(id),
    doctor_id UUID NOT NULL REFERENCES doctors(id),
    appointment_id UUID REFERENCES appointments(id),
    prescription_date DATE NOT NULL,
    valid_until DATE,
    status VARCHAR(20) DEFAULT 'active',
    diagnosis TEXT,
    instructions TEXT,
    doctor_notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_prescription_status CHECK (status IN ('active', 'completed', 'cancelled'))
);

-- =====================================================
-- Table 11: Prescription Items (FK -> prescriptions)
-- =====================================================
CREATE TABLE IF NOT EXISTS prescription_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    prescription_id UUID NOT NULL REFERENCES prescriptions(id) ON DELETE CASCADE,
    medication_name_ar VARCHAR(200) NOT NULL,
    medication_name_en VARCHAR(200) NOT NULL,
    dosage VARCHAR(100) NOT NULL,
    frequency VARCHAR(100) NOT NULL,
    duration VARCHAR(100),
    quantity INTEGER NOT NULL,
    instructions TEXT,
    refills_allowed INTEGER DEFAULT 0,
    refills_used INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 12: Notifications (FK -> users)
-- =====================================================
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title_ar VARCHAR(200) NOT NULL,
    title_en VARCHAR(200) NOT NULL,
    message_ar TEXT NOT NULL,
    message_en TEXT NOT NULL,
    notification_type VARCHAR(50) NOT NULL,
    reference_id UUID,
    reference_type VARCHAR(50),
    channel VARCHAR(20) DEFAULT 'in_app',
    is_read BOOLEAN DEFAULT false,
    read_at TIMESTAMP WITH TIME ZONE,
    email_sent_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 13: Email Queue
-- =====================================================
CREATE TABLE IF NOT EXISTS email_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipient_email VARCHAR(255) NOT NULL,
    recipient_name VARCHAR(200),
    subject VARCHAR(500) NOT NULL,
    body_html TEXT NOT NULL,
    body_text TEXT,
    status VARCHAR(20) DEFAULT 'pending',
    attempts INTEGER DEFAULT 0,
    last_attempt_at TIMESTAMP WITH TIME ZONE,
    sent_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    scheduled_for TIMESTAMP WITH TIME ZONE,
    priority INTEGER DEFAULT 5,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 14: Password Reset Tokens (FK -> users)
-- Migration 004 + 006 merged: token renamed to token_hash
-- =====================================================
CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 15: Email Verification Tokens (FK -> users)
-- =====================================================
CREATE TABLE IF NOT EXISTS email_verification_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL UNIQUE,
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 16: Doctor Reviews (FK -> appointments, FK -> patients, FK -> doctors)
-- =====================================================
CREATE TABLE IF NOT EXISTS doctor_reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_id UUID UNIQUE NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES patients(id),
    doctor_id UUID NOT NULL REFERENCES doctors(id),
    rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
    review_text_ar TEXT,
    review_text_en TEXT,
    professionalism_rating INTEGER CHECK (professionalism_rating BETWEEN 1 AND 5),
    treatment_rating INTEGER CHECK (treatment_rating BETWEEN 1 AND 5),
    communication_rating INTEGER CHECK (communication_rating BETWEEN 1 AND 5),
    is_visible BOOLEAN DEFAULT true,
    is_approved BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 17: Chatbot Conversations (FK -> users)
-- =====================================================
CREATE TABLE IF NOT EXISTS chatbot_conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id VARCHAR(100) NOT NULL,
    user_id UUID REFERENCES users(id),
    language VARCHAR(5) DEFAULT 'ar',
    platform VARCHAR(20) DEFAULT 'web',
    is_active BOOLEAN DEFAULT true,
    last_message_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE
);

-- =====================================================
-- Table 18: Chatbot Context (FK -> chatbot_conversations)
-- =====================================================
CREATE TABLE IF NOT EXISTS chatbot_context (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID UNIQUE NOT NULL REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    last_intent VARCHAR(100),
    current_topic VARCHAR(100),
    entities_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    summary TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 19: Chatbot Messages (FK -> chatbot_conversations)
-- =====================================================
CREATE TABLE IF NOT EXISTS chatbot_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    message_text TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'user',
    intent VARCHAR(100),
    confidence_score DECIMAL(5, 4),
    response_text TEXT,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 20: Conversation Titles (FK -> chatbot_conversations)
-- Migration 002
-- =====================================================
CREATE TABLE IF NOT EXISTS conversation_titles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID UNIQUE NOT NULL REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    title VARCHAR(300) NOT NULL,
    is_auto_generated BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 21: Saved Places (FK -> chatbot_conversations, FK -> users)
-- Migration 002
-- =====================================================
CREATE TABLE IF NOT EXISTS saved_places (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    place_name VARCHAR(300) NOT NULL,
    place_type VARCHAR(50) NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    address TEXT,
    phone VARCHAR(50),
    distance_km DECIMAL(10, 2),
    rating DECIMAL(3, 2),
    reference_type VARCHAR(50),
    reference_id UUID,
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 22: User Chat Preferences (FK -> users)
-- Migration 002
-- =====================================================
CREATE TABLE IF NOT EXISTS user_chat_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    preferred_language VARCHAR(5) DEFAULT 'auto',
    response_style VARCHAR(20) DEFAULT 'balanced',
    theme VARCHAR(10) DEFAULT 'light',
    model_preference VARCHAR(50) DEFAULT 'qwen2:7b',
    streaming_enabled BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 23: Symptom Triage Sessions (FK -> users, FK -> specialties)
-- =====================================================
CREATE TABLE IF NOT EXISTS symptom_triage_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    session_id VARCHAR(100),
    reported_symptoms JSONB NOT NULL,
    triage_level VARCHAR(20),
    recommended_specialty_id UUID REFERENCES specialties(id),
    recommended_specialty_name_ar VARCHAR(100),
    recommended_specialty_name_en VARCHAR(100),
    confidence_score DECIMAL(5, 4),
    recommendations TEXT,
    follow_up_action VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 24: Symptom-Specialty Mappings (FK -> specialties)
-- Migration 008 (T-044/T-046)
-- =====================================================
CREATE TABLE IF NOT EXISTS symptom_specialty_mappings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    symptom_keyword VARCHAR(200) NOT NULL,
    symptom_keyword_ar VARCHAR(200),
    specialty_id UUID NOT NULL REFERENCES specialties(id) ON DELETE CASCADE,
    weight DECIMAL(4,2) DEFAULT 1.00,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 25: Report Summarizations (FK -> medical_records, FK -> users)
-- Migration 008 (T-051)
-- =====================================================
CREATE TABLE IF NOT EXISTS report_summarizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    record_id UUID REFERENCES medical_records(id) ON DELETE SET NULL,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    source_file_name VARCHAR(500),
    source_file_type VARCHAR(50),
    extracted_text TEXT,
    summary_ar TEXT NOT NULL,
    summary_en TEXT NOT NULL,
    processing_time_ms INTEGER,
    model_used VARCHAR(100) DEFAULT 'qwen2:7b',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
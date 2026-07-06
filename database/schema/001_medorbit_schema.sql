-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- PostgreSQL Database Schema
-- Version: 1.0
-- Date: 2026-01
-- Total Tables: 25
-- =====================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Set default schema
SET search_path TO medorbit, public;

-- =====================================================
-- PART 1: USERS, AUTH & MEDICAL SETUP (7 tables)
-- =====================================================

-- Table 1: Users (base authentication table)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('patient', 'doctor', 'admin')),
    is_active BOOLEAN DEFAULT true,
    email_verified BOOLEAN DEFAULT false,
    preferred_language VARCHAR(5) DEFAULT 'ar',
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);

-- Table 2: User Profiles (shared profile data)
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Multilingual names
    first_name_ar VARCHAR(100) NOT NULL,
    last_name_ar VARCHAR(100) NOT NULL,
    first_name_en VARCHAR(100) NOT NULL,
    last_name_en VARCHAR(100) NOT NULL,
    
    -- Contact
    phone VARCHAR(20),
    
    -- Personal
    date_of_birth DATE,
    gender VARCHAR(10) CHECK (gender IN ('male', 'female', 'other')),
    profile_image_url VARCHAR(500),
    address TEXT,
    city VARCHAR(100) DEFAULT 'Nablus',
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_profiles_user ON user_profiles(user_id);

-- Table 3: Patients (patient-specific data)
CREATE TABLE patients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Medical info
    blood_type VARCHAR(5),
    allergies TEXT[],
    chronic_conditions TEXT[],
    
    -- Emergency
    emergency_contact_name VARCHAR(200),
    emergency_contact_phone VARCHAR(20),
    
    -- Insurance
    insurance_provider VARCHAR(100),
    insurance_policy_number VARCHAR(100),
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_patients_user ON patients(user_id);

-- Table 6: Specialties
CREATE TABLE specialties (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_ar VARCHAR(100) NOT NULL,
    name_en VARCHAR(100) NOT NULL,
    description_ar TEXT,
    description_en TEXT,
    icon VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Table 7: Medications (drug database)
CREATE TABLE medications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_ar VARCHAR(200) NOT NULL,
    name_en VARCHAR(200) NOT NULL,
    generic_name VARCHAR(200),
    brand_names TEXT[],
    drug_class VARCHAR(100),
    active_ingredients TEXT[],
    contraindications TEXT[],
    side_effects TEXT[],
    known_interactions JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_medications_name ON medications(name_en);


-- Table 6: Doctors (doctor-specific data)
CREATE TABLE doctors (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Professional
    medical_license_number VARCHAR(100) UNIQUE,
    specialty_id UUID REFERENCES specialties(id),
    sub_specialty VARCHAR(100),
    years_of_experience INTEGER DEFAULT 0,
    consultation_fee DECIMAL(10, 2) DEFAULT 0.00,
    consultation_duration INTEGER DEFAULT 30,
    
    -- Bio (multilingual)
    education TEXT[],
    certifications TEXT[],
    professional_bio_ar TEXT,
    professional_bio_en TEXT,
    
    -- Practice
    is_accepting_patients BOOLEAN DEFAULT true,
    average_rating DECIMAL(3, 2) DEFAULT 0.00,
    total_ratings INTEGER DEFAULT 0,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_doctors_user ON doctors(user_id);
CREATE INDEX idx_doctors_specialty ON doctors(specialty_id);

-- Table 7: User Sessions (refresh tokens)
CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token VARCHAR(500) NOT NULL,
    device_info JSONB,
    ip_address VARCHAR(50),
    user_agent TEXT,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(refresh_token);

-- =====================================================
-- PART 2: CLINICS & LOCATIONS (3 tables)
-- =====================================================

-- Table 4: Clinics
CREATE TABLE clinics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_ar VARCHAR(200) NOT NULL,
    name_en VARCHAR(200) NOT NULL,
    address_ar TEXT NOT NULL,
    address_en TEXT NOT NULL,
    city VARCHAR(100) DEFAULT 'Nablus',
    region VARCHAR(100),
    
    -- Coordinates
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    
    -- Contact
    phone VARCHAR(20),
    email VARCHAR(255),
    website VARCHAR(255),
    
    -- Hours (JSONB for flexibility)
    operating_hours JSONB DEFAULT '{
        "sun": {"open": "08:00", "close": "17:00", "is_off": false},
        "mon": {"open": "08:00", "close": "17:00", "is_off": false},
        "tue": {"open": "08:00", "close": "17:00", "is_off": false},
        "wed": {"open": "08:00", "close": "17:00", "is_off": false},
        "thu": {"open": "08:00", "close": "17:00", "is_off": false},
        "fri": {"open": "08:00", "close": "12:00", "is_off": false},
        "sat": {"open": "00:00", "close": "00:00", "is_off": true}
    }',
    
    -- Details
    services TEXT[],
    insurance_accepted TEXT[],
    images JSONB[] DEFAULT '{}',
    logo_url VARCHAR(500),
    
    -- Status
    is_active BOOLEAN DEFAULT true,
    verification_status VARCHAR(20) DEFAULT 'pending',
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_clinics_location ON clinics(latitude, longitude);
CREATE INDEX idx_clinics_region ON clinics(region);
CREATE INDEX idx_clinics_status ON clinics(is_active);

-- Table 5: Doctor-Clinic Assignments
CREATE TABLE doctor_clinic_assignments (
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

CREATE INDEX idx_dca_doctor ON doctor_clinic_assignments(doctor_id);
CREATE INDEX idx_dca_clinic ON doctor_clinic_assignments(clinic_id);

-- Table 6: Nablus Regions
CREATE TABLE nablus_regions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_ar VARCHAR(100) NOT NULL,
    name_en VARCHAR(100) NOT NULL,
    boundary_geojson TEXT,
    is_active BOOLEAN DEFAULT true
);

-- =====================================================
-- PART 3: APPOINTMENTS (2 tables)
-- =====================================================

-- Table 7: Doctor Availability
CREATE TABLE doctor_availability (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    doctor_id UUID NOT NULL REFERENCES doctors(id) ON DELETE CASCADE,
    clinic_id UUID REFERENCES clinics(id),
    
    -- Recurring or specific
    day_of_week INTEGER CHECK (day_of_week BETWEEN 0 AND 6),
    specific_date DATE,
    
    -- Time
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    slot_duration INTEGER DEFAULT 30,
    
    is_telemedicine BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_availability_doctor ON doctor_availability(doctor_id);
CREATE INDEX idx_availability_day ON doctor_availability(day_of_week);

-- Table 8: Appointments
CREATE TABLE appointments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_number VARCHAR(20) UNIQUE NOT NULL,
    
    patient_id UUID NOT NULL REFERENCES patients(id),
    doctor_id UUID NOT NULL REFERENCES doctors(id),
    clinic_id UUID REFERENCES clinics(id),
    
    -- Schedule
    scheduled_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    duration_minutes INTEGER NOT NULL,
    
    -- Type
    appointment_type VARCHAR(20) DEFAULT 'in_person',
    
    -- Status
    status VARCHAR(20) DEFAULT 'scheduled',
    
    -- Details
    reason_for_visit TEXT,
    notes TEXT,
    meeting_link VARCHAR(500),
    
    -- Cancellation
    cancelled_at TIMESTAMP WITH TIME ZONE,
    cancelled_by UUID REFERENCES users(id),
    cancellation_reason TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_appointments_patient ON appointments(patient_id);
CREATE INDEX idx_appointments_doctor ON appointments(doctor_id);
CREATE INDEX idx_appointments_date ON appointments(scheduled_date);
CREATE INDEX idx_appointments_status ON appointments(status);
CREATE INDEX idx_appointments_doctor_date ON appointments(doctor_id, scheduled_date);

-- =====================================================
-- PART 4: MEDICAL RECORDS (2 tables)
-- =====================================================

-- Table 9: Medical Records
CREATE TABLE medical_records (
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

CREATE INDEX idx_records_patient ON medical_records(patient_id);
CREATE INDEX idx_records_doctor ON medical_records(doctor_id);
CREATE INDEX idx_records_date ON medical_records(created_at);

-- Table 10: Medical Record Attachments
CREATE TABLE medical_record_attachments (
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

CREATE INDEX idx_attachments_record ON medical_record_attachments(record_id);

-- =====================================================
-- PART 5: PRESCRIPTIONS (2 tables)
-- =====================================================

-- Table 11: Prescriptions
CREATE TABLE prescriptions (
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
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_prescriptions_patient ON prescriptions(patient_id);
CREATE INDEX idx_prescriptions_doctor ON prescriptions(doctor_id);

-- Table 12: Prescription Items
CREATE TABLE prescription_items (
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

CREATE INDEX idx_items_prescription ON prescription_items(prescription_id);

-- =====================================================
-- PART 6: NOTIFICATIONS (2 tables)
-- =====================================================

-- Table 13: Notifications
CREATE TABLE notifications (
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

CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read);

-- Table 14: Email Queue
CREATE TABLE email_queue (
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

CREATE INDEX idx_email_queue_status ON email_queue(status) WHERE status = 'pending';

-- =====================================================
-- PART 7: AI & CHATBOT (3 tables)
-- =====================================================

-- Table 15: Chatbot Conversations
CREATE TABLE chatbot_conversations (
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

CREATE INDEX idx_conversations_session ON chatbot_conversations(session_id);
CREATE INDEX idx_conversations_user ON chatbot_conversations(user_id);

-- Table 16: Chatbot Messages
CREATE TABLE chatbot_messages (
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

CREATE INDEX idx_messages_conversation ON chatbot_messages(conversation_id);

-- Table 17: Symptom Triage
CREATE TABLE symptom_triage_sessions (
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

CREATE INDEX idx_triage_user ON symptom_triage_sessions(user_id);

-- =====================================================
-- PART 8: REVIEWS (1 table)
-- =====================================================

-- Table 18: Doctor Reviews
CREATE TABLE doctor_reviews (
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

CREATE INDEX idx_reviews_doctor ON doctor_reviews(doctor_id);
CREATE INDEX idx_reviews_rating ON doctor_reviews(rating);

-- =====================================================
-- PART 9: SYSTEM & AUDIT (2 tables)
-- =====================================================

-- Table 19: System Settings
CREATE TABLE system_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value JSONB NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT false,
    requires_restart BOOLEAN DEFAULT false,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(id)
);

-- Table 20: Audit Logs
CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    user_id UUID REFERENCES users(id),
    user_role VARCHAR(20),
    action VARCHAR(50) NOT NULL,
    entity_type VARCHAR(50),
    entity_id UUID,
    
    old_values JSONB,
    new_values JSONB,
    ip_address VARCHAR(50),
    user_agent TEXT,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- =====================================================
-- PART 10: REPORTS (1 table)
-- =====================================================

-- Table 21: Generated Reports
CREATE TABLE generated_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    template_id UUID,
    generated_by UUID REFERENCES users(id),
    
    report_title VARCHAR(200),
    report_type VARCHAR(50),
    report_data JSONB,
    format VARCHAR(20) DEFAULT 'json',
    file_path VARCHAR(500),
    
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_reports_generated_by ON generated_reports(generated_by);

-- =====================================================
-- FUNCTIONS & TRIGGERS
-- =====================================================

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to all tables with updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_patients_updated_at BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_doctors_updated_at BEFORE UPDATE ON doctors
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_clinics_updated_at BEFORE UPDATE ON clinics
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_appointments_updated_at BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_records_updated_at BEFORE UPDATE ON medical_records
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_prescriptions_updated_at BEFORE UPDATE ON prescriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function: Generate appointment number
CREATE OR REPLACE FUNCTION generate_appointment_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.appointment_number IS NULL THEN
        NEW.appointment_number = 'APT-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' || 
            LPAD(NEXTVAL('appointment_seq')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Sequence for appointment numbers
CREATE SEQUENCE appointment_seq START 1;

CREATE TRIGGER generate_appointment_number_trigger
    BEFORE INSERT ON appointments
    FOR EACH ROW
    EXECUTE FUNCTION generate_appointment_number();

-- Function: Generate record number
CREATE OR REPLACE FUNCTION generate_record_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.record_number IS NULL THEN
        NEW.record_number = 'MR-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' || 
            LPAD(NEXTVAL('record_seq')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE SEQUENCE record_seq START 1;

CREATE TRIGGER generate_record_number_trigger
    BEFORE INSERT ON medical_records
    FOR EACH ROW
    EXECUTE FUNCTION generate_record_number();

-- Function: Generate prescription number
CREATE OR REPLACE FUNCTION generate_prescription_number()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.prescription_number IS NULL THEN
        NEW.prescription_number = 'RX-' || TO_CHAR(CURRENT_DATE, 'YYYY') || '-' || 
            LPAD(NEXTVAL('prescription_seq')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE SEQUENCE prescription_seq START 1;

CREATE TRIGGER generate_prescription_number_trigger
    BEFORE INSERT ON prescriptions
    FOR EACH ROW
    EXECUTE FUNCTION generate_prescription_number();

-- =====================================================
-- SEED DATA: Specialties
-- =====================================================

INSERT INTO specialties (name_ar, name_en, description_ar, description_en, icon) VALUES
('طب عام', 'General Practice', 'طب الأسرة والطب العام', 'Family and general medicine', 'stethoscope'),
('طب القلب', 'Cardiology', 'أمراض القلب والأوعية الدموية', 'Heart and cardiovascular diseases', 'heart-pulse'),
('طب الأطفال', 'Pediatrics', 'طب الأطفال وحديثي الولادة', 'Pediatrics and neonatology', 'baby'),
('طب النساء والتوليد', 'Obstetrics & Gynecology', 'صحة المرأة والحمل والولادة', 'Women health, pregnancy and childbirth', 'person-pregnant'),
('جراحة العظام', 'Orthopedics', 'جراحة العظام والمفاصل', 'Orthopedic and joint surgery', 'bone'),
('طب العيون', 'Ophthalmology', 'أمراض العيون وجراحتها', 'Eye diseases and surgery', 'eye'),
('طب الأنف والأذن والحنجرة', 'ENT', 'أمراض الأنف والأذن والحنجرة', 'Ear, nose and throat diseases', 'ear'),
('طب الجلدية', 'Dermatology', 'أمراض الجلد والشعر والأظافر', 'Skin, hair and nail diseases', 'hand-sparkles'),
('طب الأسنان', 'Dentistry', 'طب الأسنان العام', 'General dentistry', 'tooth'),
('طب الأعصاب', 'Neurology', 'أمراض الجهاز العصبي', 'Nervous system diseases', 'brain'),
('طب نفسي', 'Psychiatry', 'الصحة النفسية والأمراض النفسية', 'Mental health and psychiatric disorders', 'brain'),
('طب الجهاز الهضمي', 'Gastroenterology', 'أمراض الجهاز الهضمي', 'Digestive system diseases', 'stomach'),
('طب الغدد الصماء', 'Endocrinology', 'أمراض الغدد والتمثيل الغذائي', 'Endocrine and metabolic diseases', 'chart-line'),
('طب الكلى', 'Nephrology', 'أمراض الكلى والمسالك البولية', 'Kidney and urinary tract diseases', 'droplet'),
('طب الدم', 'Hematology', 'أمراض الدم', 'Blood diseases', 'tint'),
('طب الأورام', 'Oncology', 'علاج الأورام والسرطان', 'Tumor and cancer treatment', 'ribbon'),
('طب الرئة', 'Pulmonology', 'أمراض الجهاز التنفسي', 'Respiratory system diseases', 'lungs'),
('طب الروماتيزم', 'Rheumatology', 'أمراض المفاصل والروماتيزم', 'Joint and rheumatism diseases', 'hands-bubbles'),
('جراحة عامة', 'General Surgery', 'الجراحة العامة', 'General surgery', 'scissors'),
('جراحة المسالك البولية', 'Urology', 'جراحة المسالك البولية', 'Urology surgery', 'kidney'),
('طب الشيخوخة', 'Geriatrics', 'طب كبار السن', 'Elderly medicine', 'person-cane'),
('طب الطوارئ', 'Emergency Medicine', 'طب الطوارئ والإسعافات', 'Emergency and first aid', 'truck-medical'),
('التخدير', 'Anesthesiology', 'التخدير والعناية المركزة', 'Anesthesia and ICU', 'syringe'),
('الأشعة', 'Radiology', 'الأشعة التشخيصية والعلاجية', 'Diagnostic and therapeutic radiology', 'radio'),
('طب إعادة التأهيل', 'Physiotherapy', 'العلاج الطبيعي والتأهيلي', 'Physical therapy and rehabilitation', 'person-walking');

-- =====================================================
-- SEED DATA: Nablus Regions
-- =====================================================

INSERT INTO nablus_regions (name_ar, name_en, boundary_geojson) VALUES
('المدينة القديمة', 'Old City', '{"type": "Polygon", "coordinates": [[[35.26, 32.22], [35.27, 32.22], [35.27, 32.21], [35.26, 32.21], [35.26, 32.22]]]}'),
('رفيديا', 'Rafidia', '{"type": "Polygon", "coordinates": [[[35.25, 32.23], [35.26, 32.23], [35.26, 32.22], [35.25, 32.22], [35.25, 32.23]]]}'),
('عين بيت الماء', 'Ein Beit El Ma', '{"type": "Polygon", "coordinates": [[[35.24, 32.22], [35.25, 32.22], [35.25, 32.21], [35.24, 32.21], [35.24, 32.22]]]}'),
('الباذنجان', 'Al-Batin', '{"type": "Polygon", "coordinates": [[[35.23, 32.21], [35.24, 32.21], [35.24, 32.20], [35.23, 32.20], [35.23, 32.21]]]}'),
('الخالدية', 'Al-Khalidiyah', '{"type": "Polygon", "coordinates": [[[35.27, 32.23], [35.28, 32.23], [35.28, 32.22], [35.27, 32.22], [35.27, 32.23]]]}'),
('النزهة', 'Al-Nazha', '{"type": "Polygon", "coordinates": [[[35.26, 32.24], [35.27, 32.24], [35.27, 32.23], [35.26, 32.23], [35.26, 32.24]]]}'),
('الإسكان', 'Al-Iskan', '{"type": "Polygon", "coordinates": [[[35.25, 32.24], [35.26, 32.24], [35.26, 32.23], [35.25, 32.23], [35.25, 32.24]]]}'),
('شارع رقم 60', '60 Street', '{"type": "Polygon", "coordinates": [[[35.28, 32.21], [35.29, 32.21], [35.29, 32.20], [35.28, 32.20], [35.28, 32.21]]]}');

-- =====================================================
-- SEED DATA: System Settings
-- =====================================================

INSERT INTO system_settings (setting_key, setting_value, description, is_public) VALUES
('app_name', '"MedOrbit"', 'Application name', true),
('app_version', '"1.0.0"', 'Current version', true),
('support_email', '"support@medorbit.ps"', 'Support email address', true),
('clinic_default_lat', '32.2211', 'Default latitude for Nablus', true),
('clinic_default_lng', '35.2544', 'Default longitude for Nablus', true),
('appointment_default_duration', '30', 'Default appointment duration in minutes', true),
('max_login_attempts', '5', 'Maximum failed login attempts before lockout', false),
('token_expiry_minutes', '15', 'Access token expiry in minutes', false),
('refresh_token_expiry_days', '7', 'Refresh token expiry in days', false);

-- =====================================================
-- PERMISSIONS CHECK CONSTRAINTS
-- =====================================================

ALTER TABLE appointments ADD CONSTRAINT chk_appointment_status 
    CHECK (status IN ('scheduled', 'confirmed', 'in_progress', 'completed', 'cancelled', 'no_show'));

ALTER TABLE appointments ADD CONSTRAINT chk_appointment_type 
    CHECK (appointment_type IN ('in_person', 'telemedicine'));

ALTER TABLE clinics ADD CONSTRAINT chk_clinic_verification 
    CHECK (verification_status IN ('pending', 'verified', 'rejected'));

ALTER TABLE prescriptions ADD CONSTRAINT chk_prescription_status 
    CHECK (status IN ('active', 'completed', 'cancelled'));

-- =====================================================
-- COMPLETE
-- =====================================================

COMMENT ON TABLE users IS 'Base authentication table for all user types';
COMMENT ON TABLE user_profiles IS 'Shared profile data for all users';
COMMENT ON TABLE patients IS 'Patient-specific data and medical info';
COMMENT ON TABLE doctors IS 'Doctor-specific professional data';
COMMENT ON TABLE specialties IS 'Medical specialties lookup';
COMMENT ON TABLE medications IS 'Drug/medication database';
COMMENT ON TABLE clinics IS 'Healthcare facilities in Nablus';
COMMENT ON TABLE doctor_clinic_assignments IS 'Many-to-many doctor-clinic relationships';
COMMENT ON TABLE nablus_regions IS 'Geographic regions in Nablus for map clustering';
COMMENT ON TABLE doctor_availability IS 'Doctor weekly/specific availability slots';
COMMENT ON TABLE appointments IS 'Booked appointments between patients and doctors';
COMMENT ON TABLE medical_records IS 'Electronic medical records';
COMMENT ON TABLE medical_record_attachments IS 'Files attached to medical records';
COMMENT ON TABLE prescriptions IS 'Digital prescriptions';
COMMENT ON TABLE prescription_items IS 'Individual items in prescriptions';
COMMENT ON TABLE notifications IS 'In-app and email notifications';
COMMENT ON TABLE email_queue IS 'Email sending queue';
COMMENT ON TABLE chatbot_conversations IS 'Chatbot conversation sessions';
COMMENT ON TABLE chatbot_messages IS 'Individual chatbot messages';
COMMENT ON TABLE symptom_triage_sessions IS 'AI symptom analysis sessions';
COMMENT ON TABLE doctor_reviews IS 'Patient reviews for doctors';
COMMENT ON TABLE system_settings IS 'Application configuration';
COMMENT ON TABLE audit_logs IS 'System audit trail';
COMMENT ON TABLE generated_reports IS 'Generated analytics reports';

-- Grant permissions (adjust as needed)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA medorbit TO medorbit_app;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA medorbit TO medorbit_app;
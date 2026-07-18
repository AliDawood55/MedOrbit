-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Sequences, Functions & Triggers
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- SEQUENCES
-- =====================================================
CREATE SEQUENCE IF NOT EXISTS appointment_seq START 1;
CREATE SEQUENCE IF NOT EXISTS record_seq START 1;
CREATE SEQUENCE IF NOT EXISTS prescription_seq START 1;

-- =====================================================
-- FUNCTION: update_updated_at_column
-- =====================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: update_titles_updated_at
-- =====================================================
CREATE OR REPLACE FUNCTION update_titles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- FUNCTION: generate_appointment_number
-- =====================================================
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

-- =====================================================
-- FUNCTION: generate_record_number
-- =====================================================
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

-- =====================================================
-- FUNCTION: generate_prescription_number
-- =====================================================
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

-- =====================================================
-- TRIGGERS: updated_at
-- =====================================================
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_profiles_updated_at ON user_profiles;
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_patients_updated_at ON patients;
CREATE TRIGGER update_patients_updated_at BEFORE UPDATE ON patients
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_doctors_updated_at ON doctors;
CREATE TRIGGER update_doctors_updated_at BEFORE UPDATE ON doctors
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_clinics_updated_at ON clinics;
CREATE TRIGGER update_clinics_updated_at BEFORE UPDATE ON clinics
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_appointments_updated_at ON appointments;
CREATE TRIGGER update_appointments_updated_at BEFORE UPDATE ON appointments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_records_updated_at ON medical_records;
CREATE TRIGGER update_records_updated_at BEFORE UPDATE ON medical_records
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_prescriptions_updated_at ON prescriptions;
CREATE TRIGGER update_prescriptions_updated_at BEFORE UPDATE ON prescriptions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- TRIGGERS: Auto-number generation
-- =====================================================
DROP TRIGGER IF EXISTS generate_appointment_number_trigger ON appointments;
CREATE TRIGGER generate_appointment_number_trigger
    BEFORE INSERT ON appointments
    FOR EACH ROW
    EXECUTE FUNCTION generate_appointment_number();

DROP TRIGGER IF EXISTS generate_record_number_trigger ON medical_records;
CREATE TRIGGER generate_record_number_trigger
    BEFORE INSERT ON medical_records
    FOR EACH ROW
    EXECUTE FUNCTION generate_record_number();

DROP TRIGGER IF EXISTS generate_prescription_number_trigger ON prescriptions;
CREATE TRIGGER generate_prescription_number_trigger
    BEFORE INSERT ON prescriptions
    FOR EACH ROW
    EXECUTE FUNCTION generate_prescription_number();

-- =====================================================
-- TRIGGER: conversation_titles updated_at (Migration 002)
-- =====================================================
DROP TRIGGER IF EXISTS update_conv_titles_updated_at ON conversation_titles;
CREATE TRIGGER update_conv_titles_updated_at 
    BEFORE UPDATE ON conversation_titles
    FOR EACH ROW EXECUTE FUNCTION update_titles_updated_at();
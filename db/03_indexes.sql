-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- All CREATE INDEX statements consolidated
-- =====================================================

SET search_path TO medorbit, public;

-- ========================
-- Users & Auth
-- ========================
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

CREATE INDEX IF NOT EXISTS idx_profiles_user ON user_profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_patients_user ON patients(user_id);

CREATE INDEX IF NOT EXISTS idx_doctors_user ON doctors(user_id);
CREATE INDEX IF NOT EXISTS idx_doctors_specialty ON doctors(specialty_id);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON user_sessions(refresh_token);
CREATE INDEX IF NOT EXISTS idx_user_sessions_refresh_token ON user_sessions(refresh_token);
CREATE INDEX IF NOT EXISTS idx_user_sessions_active ON user_sessions(user_id, revoked_at);

CREATE INDEX IF NOT EXISTS idx_password_reset_user ON password_reset_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_password_reset_token ON password_reset_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_password_reset_expiry ON password_reset_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_password_reset_expires ON password_reset_tokens(expires_at);

CREATE INDEX IF NOT EXISTS idx_email_verification_user ON email_verification_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_email_verification_token ON email_verification_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_email_verification_expiry ON email_verification_tokens(expires_at);
CREATE INDEX IF NOT EXISTS idx_email_verification_expire ON email_verification_tokens(expires_at);

-- ========================
-- Clinics & Locations
-- ========================
CREATE INDEX IF NOT EXISTS idx_clinics_location ON clinics(latitude, longitude);
CREATE INDEX IF NOT EXISTS idx_clinics_region ON clinics(region);
CREATE INDEX IF NOT EXISTS idx_clinics_status ON clinics(is_active);
CREATE INDEX IF NOT EXISTS idx_clinics_type ON clinics(type);
CREATE INDEX IF NOT EXISTS idx_clinics_type_coordinates ON clinics(type, latitude, longitude) WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_clinics_name_search ON clinics USING gin (name_ar gin_trgm_ops, name_en gin_trgm_ops);

-- ========================
-- Appointments
-- ========================
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON appointments(patient_id);
CREATE INDEX IF NOT EXISTS idx_appointments_doctor ON appointments(doctor_id);
CREATE INDEX IF NOT EXISTS idx_appointments_date ON appointments(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_appointments_status ON appointments(status);
CREATE INDEX IF NOT EXISTS idx_appointments_doctor_date ON appointments(doctor_id, scheduled_date);

-- ========================
-- Medical Records
-- ========================
CREATE INDEX IF NOT EXISTS idx_records_patient ON medical_records(patient_id);
CREATE INDEX IF NOT EXISTS idx_records_doctor ON medical_records(doctor_id);
CREATE INDEX IF NOT EXISTS idx_records_date ON medical_records(created_at);
CREATE INDEX IF NOT EXISTS idx_attachments_record ON medical_record_attachments(record_id);

-- ========================
-- Prescriptions
-- ========================
CREATE INDEX IF NOT EXISTS idx_prescriptions_patient ON prescriptions(patient_id);
CREATE INDEX IF NOT EXISTS idx_prescriptions_doctor ON prescriptions(doctor_id);
CREATE INDEX IF NOT EXISTS idx_items_prescription ON prescription_items(prescription_id);

-- ========================
-- Notifications & Email
-- ========================
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_email_queue_status ON email_queue(status) WHERE status = 'pending';

-- ========================
-- Medications
-- ========================
CREATE INDEX IF NOT EXISTS idx_medications_name ON medications(name_en);

-- ========================
-- Chatbot
-- ========================
CREATE INDEX IF NOT EXISTS idx_conversations_session ON chatbot_conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user ON chatbot_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_chatbot_conv_user_active ON chatbot_conversations(user_id, is_active, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON chatbot_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_chatbot_messages_conv_created ON chatbot_messages(conversation_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_chatbot_messages_metadata_places ON chatbot_messages USING gin (metadata) WHERE message_type = 'bot';
CREATE INDEX IF NOT EXISTS idx_chatbot_context_conversation ON chatbot_context(conversation_id);
CREATE INDEX IF NOT EXISTS idx_chatbot_context_last_intent ON chatbot_context(last_intent);
CREATE INDEX IF NOT EXISTS idx_chatbot_context_current_topic ON chatbot_context(current_topic);
CREATE INDEX IF NOT EXISTS idx_chatbot_context_entities_json ON chatbot_context USING GIN (entities_json);
CREATE INDEX IF NOT EXISTS idx_conv_titles_conversation ON conversation_titles(conversation_id);
CREATE INDEX IF NOT EXISTS idx_saved_places_conversation ON saved_places(conversation_id);
CREATE INDEX IF NOT EXISTS idx_saved_places_user ON saved_places(user_id);
CREATE INDEX IF NOT EXISTS idx_user_prefs_user ON user_chat_preferences(user_id);

-- ========================
-- Doctor relationships
-- ========================
CREATE INDEX IF NOT EXISTS idx_dca_doctor ON doctor_clinic_assignments(doctor_id);
CREATE INDEX IF NOT EXISTS idx_dca_clinic ON doctor_clinic_assignments(clinic_id);
CREATE INDEX IF NOT EXISTS idx_availability_doctor ON doctor_availability(doctor_id);
CREATE INDEX IF NOT EXISTS idx_availability_day ON doctor_availability(day_of_week);

-- ========================
-- Reviews
-- ========================
CREATE INDEX IF NOT EXISTS idx_reviews_doctor ON doctor_reviews(doctor_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON doctor_reviews(rating);

-- ========================
-- Triage & Reports (T-044 / T-051)
-- ========================
CREATE INDEX IF NOT EXISTS idx_ssm_symptom ON symptom_specialty_mappings(symptom_keyword);
CREATE INDEX IF NOT EXISTS idx_ssm_symptom_ar ON symptom_specialty_mappings(symptom_keyword_ar);
CREATE INDEX IF NOT EXISTS idx_ssm_specialty ON symptom_specialty_mappings(specialty_id);
CREATE INDEX IF NOT EXISTS idx_rsum_record ON report_summarizations(record_id);
CREATE INDEX IF NOT EXISTS idx_rsum_user ON report_summarizations(user_id);

-- ========================
-- Audit
-- ========================
CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at DESC);

-- ========================
-- Reports
-- ========================
CREATE INDEX IF NOT EXISTS idx_reports_generated_by ON generated_reports(generated_by);

-- ========================
-- Triage sessions
-- ========================
CREATE INDEX IF NOT EXISTS idx_triage_user ON symptom_triage_sessions(user_id);
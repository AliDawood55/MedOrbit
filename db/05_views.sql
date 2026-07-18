-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Views (T-005)
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- View: v_doctor_ratings
-- Doctor summary with average rating and review count
-- =====================================================
CREATE OR REPLACE VIEW v_doctor_ratings AS
SELECT
    d.id AS doctor_id,
    u.id AS user_id,
    up.first_name_en || ' ' || up.last_name_en AS doctor_name_en,
    up.first_name_ar || ' ' || up.last_name_ar AS doctor_name_ar,
    s.name_en AS specialty_en,
    s.name_ar AS specialty_ar,
    d.average_rating,
    d.total_ratings,
    d.years_of_experience,
    d.consultation_fee,
    d.is_accepting_patients,
    COUNT(dr.id) AS review_count,
    COALESCE(AVG(dr.rating) FILTER (WHERE dr.is_visible AND dr.is_approved), 0) AS computed_avg_rating
FROM doctors d
JOIN users u ON u.id = d.user_id
JOIN user_profiles up ON up.user_id = u.id
LEFT JOIN specialties s ON s.id = d.specialty_id
LEFT JOIN doctor_reviews dr ON dr.doctor_id = d.id AND dr.is_visible AND dr.is_approved
GROUP BY d.id, u.id, up.first_name_en, up.last_name_en, up.first_name_ar, up.last_name_ar,
         s.name_en, s.name_ar, d.average_rating, d.total_ratings,
         d.years_of_experience, d.consultation_fee, d.is_accepting_patients;

COMMENT ON VIEW v_doctor_ratings IS 'Doctor profiles with aggregated rating data';

-- =====================================================
-- View: v_upcoming_appointments
-- Upcoming confirmed/scheduled appointments with patient & doctor info
-- =====================================================
CREATE OR REPLACE VIEW v_upcoming_appointments AS
SELECT
    a.id AS appointment_id,
    a.appointment_number,
    a.scheduled_date,
    a.start_time,
    a.end_time,
    a.duration_minutes,
    a.appointment_type,
    a.status,
    a.reason_for_visit,
    a.meeting_link,
    -- Patient info
    p.id AS patient_id,
    pup.first_name_en || ' ' || pup.last_name_en AS patient_name_en,
    pup.first_name_ar || ' ' || pup.last_name_ar AS patient_name_ar,
    pup.phone AS patient_phone,
    -- Doctor info
    d.id AS doctor_id,
    dup.first_name_en || ' ' || dup.last_name_en AS doctor_name_en,
    dup.first_name_ar || ' ' || dup.last_name_ar AS doctor_name_ar,
    s.name_en AS specialty_en,
    s.name_ar AS specialty_ar,
    -- Clinic info
    c.id AS clinic_id,
    c.name_en AS clinic_name_en,
    c.name_ar AS clinic_name_ar,
    c.address_en AS clinic_address_en,
    c.address_ar AS clinic_address_ar,
    c.latitude,
    c.longitude,
    c.phone AS clinic_phone
FROM appointments a
JOIN patients p ON p.id = a.patient_id
JOIN user_profiles pup ON pup.user_id = p.user_id
JOIN doctors d ON d.id = a.doctor_id
JOIN user_profiles dup ON dup.user_id = d.user_id
LEFT JOIN specialties s ON s.id = d.specialty_id
LEFT JOIN clinics c ON c.id = a.clinic_id
WHERE a.status IN ('scheduled', 'confirmed')
  AND a.scheduled_date >= CURRENT_DATE;

COMMENT ON VIEW v_upcoming_appointments IS 'Upcoming scheduled/confirmed appointments with full patient, doctor, and clinic details';

-- =====================================================
-- View: v_patient_summary
-- Patient medical summary with recent records & prescriptions
-- =====================================================
CREATE OR REPLACE VIEW v_patient_summary AS
SELECT
    p.id AS patient_id,
    u.id AS user_id,
    up.first_name_en || ' ' || up.last_name_en AS patient_name_en,
    up.first_name_ar || ' ' || up.last_name_ar AS patient_name_ar,
    up.date_of_birth,
    up.gender,
    up.phone,
    p.blood_type,
    p.allergies,
    p.chronic_conditions,
    p.insurance_provider,
    p.insurance_policy_number,
    -- Latest medical record
    (SELECT jsonb_build_object(
        'record_id', mr.id,
        'diagnosis', mr.diagnosis,
        'symptoms', mr.symptoms,
        'treatment_plan', mr.treatment_plan,
        'created_at', mr.created_at
     ) FROM medical_records mr
     WHERE mr.patient_id = p.id
     ORDER BY mr.created_at DESC LIMIT 1) AS latest_record,
    -- Active prescriptions count
    (SELECT COUNT(*) FROM prescriptions rx
     WHERE rx.patient_id = p.id AND rx.status = 'active') AS active_prescriptions,
    -- Upcoming appointments
    (SELECT COUNT(*) FROM appointments apt
     WHERE apt.patient_id = p.id
       AND apt.status IN ('scheduled', 'confirmed')
       AND apt.scheduled_date >= CURRENT_DATE) AS upcoming_appointments,
    -- Total visits
    (SELECT COUNT(*) FROM appointments apt
     WHERE apt.patient_id = p.id AND apt.status = 'completed') AS total_visits,
    u.created_at AS registered_since
FROM patients p
JOIN users u ON u.id = p.user_id
JOIN user_profiles up ON up.user_id = u.id;

COMMENT ON VIEW v_patient_summary IS 'Patient medical summary with latest record, prescription count, and appointment stats';
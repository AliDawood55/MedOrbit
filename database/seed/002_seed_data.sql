-- =====================================================
-- MEDORBIT SEED DATA
-- Sample data for development and testing
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- SAMPLE USERS (Password for all: Password123!)
-- Hash: $2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa
-- =====================================================

-- Admin User
INSERT INTO users (id, email, password_hash, role, is_active, email_verified, preferred_language)
VALUES (
    'a1111111-1111-1111-1111-111111111111',
    'admin@medorbit.ps',
    '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa',
    'admin',
    true,
    true,
    'ar'
);

INSERT INTO user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, date_of_birth, gender, address, city)
VALUES (
    'a1111111-1111-1111-1111-111111111111',
    'أحمد',
    'الأministrator',
    'Ahmad',
    'Administrator',
    '+970-9-2345678',
    '1985-05-15',
    'male',
    'شارع الرئيسي، نابلس',
    'Nablus'
);

-- Sample Doctors
INSERT INTO users (id, email, password_hash, role, is_active, email_verified, preferred_language)
VALUES 
    ('d2222222-2222-2222-2222-222222222221', 'dr.smith@medorbit.ps', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'doctor', true, true, 'en'),
    ('d2222222-2222-2222-2222-222222222222', 'dr.johnson@medorbit.ps', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'doctor', true, true, 'ar'),
    ('d2222222-2222-2222-2222-222222222223', 'dr.williams@medorbit.ps', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'doctor', true, true, 'en');

INSERT INTO user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, date_of_birth, gender, address, city)
VALUES
    ('d2222222-2222-2222-2222-222222222221', 'محمد', 'أحمد', 'Mohammad', 'Smith', '+970-9-2345671', '1980-03-20', 'male', 'رفيديا، نابلس', 'Nablus'),
    ('d2222222-2222-2222-2222-222222222222', 'أحمد', 'عبدالله', 'Ahmad', 'Johnson', '+970-9-2345672', '1978-07-15', 'male', 'المدينة القديمة، نابلس', 'Nablus'),
    ('d2222222-2222-2222-2222-222222222223', 'سارة', 'يونيس', 'Sarah', 'Williams', '+970-9-2345673', '1985-11-25', 'female', 'عين بيت الماء، نابلس', 'Nablus');

-- Doctor Profiles
INSERT INTO doctors (user_id, medical_license_number, specialty_id, years_of_experience, consultation_fee, consultation_duration, education, certifications, professional_bio_ar, professional_bio_en, is_accepting_patients, average_rating, total_ratings)
SELECT 
    'd2222222-2222-2222-2222-222222222221',
    'ML-2020-001',
    id,
    15,
    100.00,
    30,
    ARRAY['MD - University of Jordan', 'Fellowship - Cleveland Clinic'],
    ARRAY['Jordan Medical Board Certified', 'American Board Eligible'],
    'دكتور محمد أحمد هو طبيب قلب معتمد بخبرة 15 عاماً في تشخيص وعلاج أمراض القلب. متخصص في علاج ارتفاع ضغط الدم وأمراض الشرايين.',
    'Dr. Mohammad Smith is a certified cardiologist with 15 years of experience in diagnosing and treating heart diseases. Specialized in hypertension and arterial disease treatment.',
    true,
    4.8,
    45
FROM specialties WHERE name_en = 'Cardiology';

INSERT INTO doctors (user_id, medical_license_number, specialty_id, years_of_experience, consultation_fee, consultation_duration, education, certifications, professional_bio_ar, professional_bio_en, is_accepting_patients, average_rating, total_ratings)
SELECT 
    'd2222222-2222-2222-2222-222222222222',
    'ML-2020-002',
    id,
    20,
    80.00,
    30,
    ARRAY['MD - An-Najah National University', 'Specialty - Damascus University'],
    ARRAY['Palestinian Medical Board'],
    'دكتور أحمد عبدالله هو طبيب عام متمرس يقدم خدمات الرعاية الصحية الأولية لجميع أفراد العائلة.',
    'Dr. Ahmad Abdullah is an experienced general practitioner providing primary healthcare services for all family members.',
    true,
    4.5,
    120
FROM specialties WHERE name_en = 'General Practice';

INSERT INTO doctors (user_id, medical_license_number, specialty_id, years_of_experience, consultation_fee, consultation_duration, education, certifications, professional_bio_ar, professional_bio_en, is_accepting_patients, average_rating, total_ratings)
SELECT 
    'd2222222-2222-2222-2222-222222222223',
    'ML-2020-003',
    id,
    12,
    150.00,
    45,
    ARRAY['MD - Harvard Medical School', 'Fellowship - Boston Children Hospital'],
    ARRAY['American Board of Pediatrics', 'Neonatal Resuscitation Program'],
    'دكتورة سارة ويليامز هي طبيبة أطفال متخصصة في رعاية المواليد والأطفال. تقدم خدمات التطعيم والفحوصات الدورية.',
    'Dr. Sarah Williams is a pediatrician specialized in neonatal and child care. Provides vaccination and regular checkup services.',
    true,
    4.9,
    78
FROM specialties WHERE name_en = 'Pediatrics';

-- Sample Patients
INSERT INTO users (id, email, password_hash, role, is_active, email_verified, preferred_language)
VALUES 
    ('a3333333-3333-3333-3333-333333333331', 'mahmoud@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'patient', true, true, 'ar'),
    ('a3333333-3333-3333-3333-333333333332', 'fatima@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'patient', true, true, 'ar'),
    ('a3333333-3333-3333-3333-333333333333', 'john@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'patient', true, true, 'en');

INSERT INTO user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, date_of_birth, gender, address, city)
VALUES
    ('a3333333-3333-3333-3333-333333333331', 'محمود', 'الخالدي', 'Mahmoud', 'Al-Khalidi', '+970-59-1234567', '1990-08-10', 'male', 'شارع رقم 60، نابلس', 'Nablus'),
    ('a3333333-3333-3333-3333-333333333332', 'فاطمة', 'الزيود', 'Fatima', 'Al-Zioud', '+970-59-2345678', '1985-12-20', 'female', 'الخالدية، نابلس', 'Nablus'),
    ('a3333333-3333-3333-3333-333333333333', 'جون', 'سميث', 'John', 'Smith', '+970-59-3456789', '1995-04-15', 'male', 'الإسكان، نابلس', 'Nablus');

INSERT INTO patients (user_id, blood_type, allergies, chronic_conditions, emergency_contact_name, emergency_contact_phone, insurance_provider, insurance_policy_number)
VALUES
    ('a3333333-3333-3333-3333-333333333331', 'O+', ARRAY['البنسلين'], ARRAY['لا يوجد'], 'خالد الخالدي', '+970-59-9876543', 'الأردنية للتأمين', 'INS-001234'),
    ('a3333333-3333-3333-3333-333333333332', 'A+', ARRAY[]::TEXT[], ARRAY['السكري'], 'عبدالله الزيود', '+970-59-8765432', 'التأمين الصحي الحكومي', 'GOV-005678'),
    ('a3333333-3333-3333-3333-333333333333', 'B+', ARRAY[]::TEXT[], ARRAY[]::TEXT[], 'ماريا سميث', '+970-59-7654321', NULL, NULL);

-- =====================================================
-- SAMPLE CLINICS
-- =====================================================

INSERT INTO clinics (name_ar, name_en, address_ar, address_en, city, region, latitude, longitude, phone, email, services, insurance_accepted, is_active, verification_status)
VALUES
    ('مستشفى نابلس الطبي', 'Nablus Medical Hospital', 'شارع رقم 60، نابلس', '60 Street, Nablus', 'Nablus', 'شارع رقم 60', 32.2234, 35.2578, '+970-9-2381000', 'info@nablusmed.ps', ARRAY['طوارئ', 'عناية مركزة', 'عمليات', 'أشعة', 'مختبر'], ARRAY['الأردنية للتأمين', 'التأمين الصحي الحكومي', 'التأمين الصحي الخاص'], true, 'verified'),
    
    ('عيادة القلب المتميزة', 'Elite Cardiac Clinic', 'رفيديا، شارع المستشفى القديم', 'Rafidia, Old Hospital Street', 'Nablus', 'رفيديا', 32.2256, 35.2523, '+970-9-2345671', 'cardio@eliteclinic.ps', ARRAY['تخطيط القلب', 'إيكو', 'اختبار الإجهاد'], ARRAY['الأردنية للتأمين', 'التأمين الصحي الخاص'], true, 'verified'),
    
    ('مركز الرعاية الصحية الأولية', 'Primary Healthcare Center', 'المدينة القديمة، قرب السوق', 'Old City, Near the Market', 'Nablus', 'المدينة القديمة', 32.2198, 35.2512, '+970-9-2381234', 'phc@nablus.ps', ARRAY['طب عام', 'تطعيمات', 'رعاية الأم والطفل'], ARRAY['التأمين الصحي الحكومي'], true, 'verified'),
    
    ('عيادة الأطفال السعيدة', 'Happy Kids Clinic', 'عين بيت الماء، قرب مدرسة بنات', 'Ein Beit El Ma, Near Girls School', 'Nablus', 'عين بيت الماء', 32.2215, 35.2489, '+970-9-2345673', 'kids@happyclinic.ps', ARRAY['طب أطفال', 'تطعيمات', 'فحص نمو'], ARRAY['الأردنية للتأمين', 'التأمين الصحي الحكومي', 'التأمين الصحي الخاص'], true, 'verified'),
    
    ('مركز المستقبل للأشعة', 'Future Radiology Center', 'الخالدية، بجوار البنك الإسلامي', 'Al-Khalidiyah, Next to Islamic Bank', 'Nablus', 'الخالدية', 32.2278, 35.2590, '+970-9-2345674', 'radio@future.ps', ARRAY['أشعة عادية', 'سونار', 'رنين مغناطيسي', 'أشعة مقطعية'], ARRAY['الأردنية للتأمين', 'التأمين الصحي الخاص'], true, 'verified');

-- =====================================================
-- DOCTOR-CLINIC ASSIGNMENTS
-- =====================================================

-- Dr. Mohammad (Cardiologist) works at hospital and cardiac clinic
INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-001'),
    (SELECT id FROM clinics WHERE name_en = 'Nablus Medical Hospital'),
    150.00,
    true
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-001')
AND EXISTS (SELECT 1 FROM clinics WHERE name_en = 'Nablus Medical Hospital');

INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-001'),
    (SELECT id FROM clinics WHERE name_en = 'Elite Cardiac Clinic'),
    100.00,
    false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-001')
AND EXISTS (SELECT 1 FROM clinics WHERE name_en = 'Elite Cardiac Clinic');

-- Dr. Ahmad (GP) works at primary healthcare center
INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-002'),
    (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'),
    50.00,
    true
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-002')
AND EXISTS (SELECT 1 FROM clinics WHERE name_en = 'Primary Healthcare Center');

-- Dr. Sarah (Pediatrician) works at hospital and kids clinic
INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-003'),
    (SELECT id FROM clinics WHERE name_en = 'Nablus Medical Hospital'),
    180.00,
    true
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-003')
AND EXISTS (SELECT 1 FROM clinics WHERE name_en = 'Nablus Medical Hospital');

INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-003'),
    (SELECT id FROM clinics WHERE name_en = 'Happy Kids Clinic'),
    120.00,
    false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-003')
AND EXISTS (SELECT 1 FROM clinics WHERE name_en = 'Happy Kids Clinic');

-- =====================================================
-- DOCTOR AVAILABILITY
-- =====================================================

-- Dr. Mohammad availability (Sun, Tue, Thu mornings)
INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-001'),
    (SELECT id FROM clinics WHERE name_en = 'Elite Cardiac Clinic'),
    0, '08:00', '12:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-001');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-001'),
    (SELECT id FROM clinics WHERE name_en = 'Elite Cardiac Clinic'),
    2, '08:00', '12:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-001');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-001'),
    (SELECT id FROM clinics WHERE name_en = 'Elite Cardiac Clinic'),
    4, '08:00', '12:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-001');

-- Telemedicine availability for Dr. Mohammad
INSERT INTO doctor_availability (doctor_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-001'),
    6, '09:00', '13:00', 30, true
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-001');

-- Dr. Ahmad availability (Sat-Thu)
INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-002'),
    (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'),
    1, '08:00', '15:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-002');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-002'),
    (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'),
    2, '08:00', '15:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-002');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-002'),
    (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'),
    3, '08:00', '15:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-002');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-002'),
    (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'),
    4, '08:00', '15:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-002');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-002'),
    (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'),
    5, '08:00', '12:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-002');

-- Dr. Sarah availability
INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-003'),
    (SELECT id FROM clinics WHERE name_en = 'Happy Kids Clinic'),
    0, '09:00', '17:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-003');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-003'),
    (SELECT id FROM clinics WHERE name_en = 'Happy Kids Clinic'),
    1, '09:00', '17:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-003');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-003'),
    (SELECT id FROM clinics WHERE name_en = 'Happy Kids Clinic'),
    3, '09:00', '17:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-003');

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT 
    (SELECT id FROM doctors WHERE medical_license_number = 'ML-2020-003'),
    (SELECT id FROM clinics WHERE name_en = 'Happy Kids Clinic'),
    5, '09:00', '13:00', 30, false
WHERE EXISTS (SELECT 1 FROM doctors WHERE medical_license_number = 'ML-2020-003');

-- =====================================================
-- SAMPLE MEDICATIONS
-- =====================================================

INSERT INTO medications (name_ar, name_en, generic_name, drug_class, active_ingredients, contraindications, side_effects) VALUES
('باراسيتامول', 'Paracetamol', 'Acetaminophen', 'Analgesic', ARRAY['Acetaminophen'], ARRAY['Liver disease', 'Alcohol use'], ARRAY['Nausea', 'Allergic reactions']),
('أوميبرازول', 'Omeprazole', 'Omeprazole', 'Proton Pump Inhibitor', ARRAY['Omeprazole'], ARRAY['Hypersensitivity'], ARRAY['Headache', 'Nausea']),
('أملوديبين', 'Amlodipine', 'Amlodipine Besylate', 'Calcium Channel Blocker', ARRAY['Amlodipine'], ARRAY['Cardiogenic shock', 'Severe hypotension'], ARRAY['Edema', 'Fatigue', 'Dizziness']),
('ميتفورمين', 'Metformin', 'Metformin Hydrochloride', 'Biguanide', ARRAY['Metformin'], ARRAY['Kidney disease', 'Liver disease'], ARRAY['Nausea', 'Diarrhea', 'Stomach pain']),
('لورنوكسيكام', 'Lornoxicam', 'Lornoxicam', 'NSAID', ARRAY['Lornoxicam'], ARRAY['Peptic ulcer', 'Asthma'], ARRAY['Nausea', 'Stomach pain', 'Dizziness']),
('أزيثرومايسين', 'Azithromycin', 'Azithromycin Dihydrate', 'Macrolide Antibiotic', ARRAY['Azithromycin'], ARRAY['Liver problems'], ARRAY['Nausea', 'Diarrhea', 'Abdominal pain']),
('ديكلوفيناك', 'Diclofenac', 'Diclofenac Sodium', 'NSAID', ARRAY['Diclofenac'], ARRAY['Active peptic ulcer', 'Asthma'], ARRAY['Stomach pain', 'Nausea', 'Headache']),
('كانديسارتان', 'Candesartan', 'Candesartan Cilexetil', 'ARB', ARRAY['Candesartan'], ARRAY['Pregnancy', 'Biliary obstruction'], ARRAY['Dizziness', 'Headache', 'Back pain']),
('أسبرين', 'Aspirin', 'Acetylsalicylic Acid', 'NSAID', ARRAY['Aspirin'], ARRAY['Peptic ulcer', 'Bleeding disorders'], ARRAY['Stomach irritation', 'Nausea']),
('وارفارين', 'Warfarin', 'Warfarin Sodium', 'Anticoagulant', ARRAY['Warfarin'], ARRAY['Active bleeding', 'Pregnancy'], ARRAY['Bleeding', 'Bruising']);

-- =====================================================
-- SAMPLE APPOINTMENTS
-- =====================================================

-- Get doctor IDs
DO $$
DECLARE
    dr_cardio_id UUID;
    dr_gp_id UUID;
    dr_pedia_id UUID;
    pt_mahmoud UUID;
    pt_fatima UUID;
    pt_john UUID;
    clinic_hospital UUID;
    clinic_clinic1 UUID;
    clinic_pedia UUID;
BEGIN
    SELECT id INTO dr_cardio_id FROM doctors WHERE medical_license_number = 'ML-2020-001';
    SELECT id INTO dr_gp_id FROM doctors WHERE medical_license_number = 'ML-2020-002';
    SELECT id INTO dr_pedia_id FROM doctors WHERE medical_license_number = 'ML-2020-003';
    SELECT id INTO pt_mahmoud FROM patients WHERE user_id = 'a3333333-3333-3333-3333-333333333331';
    SELECT id INTO pt_fatima FROM patients WHERE user_id = 'a3333333-3333-3333-3333-333333333332';
    SELECT id INTO pt_john FROM patients WHERE user_id = 'a3333333-3333-3333-3333-333333333333';
    SELECT id INTO clinic_hospital FROM clinics WHERE name_en = 'Nablus Medical Hospital';
    SELECT id INTO clinic_clinic1 FROM clinics WHERE name_en = 'Elite Cardiac Clinic';
    SELECT id INTO clinic_pedia FROM clinics WHERE name_en = 'Happy Kids Clinic';
    
    -- Mahmoud has appointment with cardiologist (completed)
    INSERT INTO appointments (patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
    VALUES (pt_mahmoud, dr_cardio_id, clinic_clinic1, CURRENT_DATE - INTERVAL '7 days', '09:00', '09:30', 30, 'in_person', 'completed', 'فحص دوري للقلب');
    
    -- Mahmoud has upcoming appointment with GP
    INSERT INTO appointments (patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
    VALUES (pt_mahmoud, dr_gp_id, (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'), CURRENT_DATE + INTERVAL '3 days', '10:00', '10:30', 30, 'in_person', 'confirmed', 'صداع مستمر');
    
    -- Fatima has appointment with GP
    INSERT INTO appointments (patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
    VALUES (pt_fatima, dr_gp_id, (SELECT id FROM clinics WHERE name_en = 'Primary Healthcare Center'), CURRENT_DATE + INTERVAL '1 day', '11:00', '11:30', 30, 'in_person', 'scheduled', 'متابعة السكري');
    
    -- John has telemedicine appointment with pediatrician
    INSERT INTO appointments (patient_id, doctor_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
    VALUES (pt_john, dr_pedia_id, CURRENT_DATE + INTERVAL '5 days', '14:00', '14:45', 45, 'telemedicine', 'confirmed', 'استشارة حول تطعيمات الطفل');
    
END $$;

-- =====================================================
-- SAMPLE MEDICAL RECORDS
-- =====================================================

DO $$
DECLARE
    dr_cardio_id UUID;
    dr_gp_id UUID;
    pt_mahmoud UUID;
BEGIN
    SELECT id INTO dr_cardio_id FROM doctors WHERE medical_license_number = 'ML-2020-001';
    SELECT id INTO dr_gp_id FROM doctors WHERE medical_license_number = 'ML-2020-002';
    SELECT id INTO pt_mahmoud FROM patients WHERE user_id = 'a3333333-3333-3333-3333-333333333331';
    
    -- Medical record for Mahmoud's cardiac checkup
    INSERT INTO medical_records (patient_id, doctor_id, record_type, chief_complaint, symptoms, diagnosis, treatment_plan, vitals)
    VALUES (
        pt_mahmoud,
        dr_cardio_id,
        'consultation',
        'فحص دوري للقلب',
        ARRAY['ألم خفيف في الصدر', 'ضيق تنفس عند المجهود'],
        'ارتفاع طفيف في ضغط الدم مع معدل ضربات قلب طبيعي',
        'استمرار الأدوية الحالية مع متابعة ضغط الدم يومياً. تقليل الملح في الطعام.',
        '{"blood_pressure": "130/85", "heart_rate": 72, "weight": 85, "temperature": 36.8}'
    );
    
    -- Medical record for Mahmoud's GP visit
    INSERT INTO medical_records (patient_id, doctor_id, record_type, chief_complaint, symptoms, diagnosis, treatment_plan, vitals)
    VALUES (
        pt_mahmoud,
        dr_gp_id,
        'consultation',
        'صداع مستمر',
        ARRAY['صداع في مقدمة الرأس', 'دوخة', 'أرق'],
        'توتر وصداع توتري',
        'راحة وتجنب التوتر. مسكن للصداع عند الحاجة. متابعة في حال استمرار الأعراض.',
        '{"blood_pressure": "125/80", "heart_rate": 75}'
    );
    
END $$;

-- =====================================================
-- SAMPLE PRESCRIPTIONS
-- =====================================================

DO $$
DECLARE
    dr_cardio_id UUID;
    pt_mahmoud UUID;
BEGIN
    SELECT id INTO dr_cardio_id FROM doctors WHERE medical_license_number = 'ML-2020-001';
    SELECT id INTO pt_mahmoud FROM patients WHERE user_id = 'a3333333-3333-3333-3333-333333333331';
    
    -- Prescription for cardiac patient
    INSERT INTO prescriptions (patient_id, doctor_id, prescription_date, diagnosis, instructions)
    VALUES (
        pt_mahmoud,
        dr_cardio_id,
        CURRENT_DATE,
        'ارتفاع ضغط الدم الخفيف',
        'اتباع نظام غذائي صحي وتقليل الملح'
    );
    
END $$;

-- Get prescription ID and add items
DO $$
DECLARE
    rx_id UUID;
    med_paracetamol UUID;
    med_amlodipine UUID;
BEGIN
    SELECT id INTO rx_id FROM prescriptions ORDER BY created_at DESC LIMIT 1;
    SELECT id INTO med_paracetamol FROM medications WHERE name_en = 'Paracetamol';
    SELECT id INTO med_amlodipine FROM medications WHERE name_en = 'Amlodipine';
    
    INSERT INTO prescription_items (prescription_id, medication_name_ar, medication_name_en, dosage, frequency, duration, quantity, instructions)
    VALUES (rx_id, 'أملوديبين', 'Amlodipine', '5mg', 'مرة واحدة يومياً', '30 يوم', 30, 'يُؤخذ في الصباح مع الطعام');
    
END $$;

-- =====================================================
-- SAMPLE REVIEWS
-- =====================================================

DO $$
DECLARE
    dr_cardio_id UUID;
    pt_mahmoud UUID;
    apt_id UUID;
BEGIN
    SELECT id INTO dr_cardio_id FROM doctors WHERE medical_license_number = 'ML-2020-001';
    SELECT id INTO pt_mahmoud FROM patients WHERE user_id = 'a3333333-3333-3333-3333-333333333331';
    SELECT id INTO apt_id FROM appointments WHERE patient_id = pt_mahmoud AND doctor_id = dr_cardio_id AND status = 'completed' LIMIT 1;
    
    IF apt_id IS NOT NULL THEN
        INSERT INTO doctor_reviews (appointment_id, patient_id, doctor_id, rating, review_text_ar, review_text_en, professionalism_rating, treatment_rating, communication_rating)
        VALUES (apt_id, pt_mahmoud, dr_cardio_id, 5, 'دكتور ممتاز وفريق العمل جداً محترفين. شرح لي الحالة بوضوح.', 'Excellent doctor and very professional staff. Explained my condition clearly.', 5, 5, 5);
    END IF;
    
END $$;

-- =====================================================
-- SAMPLE NOTIFICATIONS
-- =====================================================

DO $$
DECLARE
    user_mahmoud UUID;
    user_admin UUID;
BEGIN
    SELECT user_id INTO user_mahmoud FROM patients WHERE user_id = 'a3333333-3333-3333-3333-333333333331';
    SELECT id INTO user_admin FROM users WHERE role = 'admin' LIMIT 1;
    
    -- Notifications for Mahmoud
    INSERT INTO notifications (user_id, title_ar, title_en, message_ar, message_en, notification_type, reference_type, is_read)
    VALUES 
        (user_mahmoud, 'تأكيد الموعد', 'Appointment Confirmed', 'تم تأكيد موعدك مع دكتور أحمد عبدالله يوم غد الساعة 10:00 صباحاً', 'Your appointment with Dr. Ahmad Abdullah has been confirmed for tomorrow at 10:00 AM', 'appointment', 'appointments', true),
        (user_mahmoud, 'تذكير', 'Reminder', 'لا تنسَ موعدك غداً الساعة 10:00 صباحاً مع دكتور أحمد عبدالله', 'Don''t forget your appointment tomorrow at 10:00 AM with Dr. Ahmad Abdullah', 'reminder', 'appointments', false);
    
    -- Notification for admin
    IF user_admin IS NOT NULL THEN
        INSERT INTO notifications (user_id, title_ar, title_en, message_ar, message_en, notification_type, reference_type)
        VALUES 
            (user_admin, 'مستخدم جديد', 'New User', 'تم تسجيل مستخدم جديد: محمود الخالدي', 'New user registered: Mahmoud Al-Khalidi', 'system', 'users');
    END IF;
    
END $$;

-- =====================================================
-- COMPLETE
-- =====================================================

-- Reset sequences to continue from proper numbers
SELECT setval('appointment_seq', (SELECT COALESCE(MAX(CAST(SUBSTRING(appointment_number FROM 10) AS INTEGER)), 0) + 1 FROM appointments));
SELECT setval('record_seq', (SELECT COALESCE(MAX(CAST(SUBSTRING(record_number FROM 9) AS INTEGER)), 0) + 1 FROM medical_records));
SELECT setval('prescription_seq', (SELECT COALESCE(MAX(CAST(SUBSTRING(prescription_number FROM 9) AS INTEGER)), 0) + 1 FROM prescriptions));

-- Output summary
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'MedOrbit Seed Data Loaded Successfully!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Sample Users:';
    RAISE NOTICE '  Admin:    admin@medorbit.ps';
    RAISE NOTICE '  Doctor:   dr.smith@medorbit.ps';
    RAISE NOTICE '  Doctor:   dr.johnson@medorbit.ps';
    RAISE NOTICE '  Doctor:   dr.williams@medorbit.ps';
    RAISE NOTICE '  Patient:  mahmoud@example.com';
    RAISE NOTICE '  Patient:  fatima@example.com';
    RAISE NOTICE '  Patient:  john@example.com';
    RAISE NOTICE '';
    RAISE NOTICE 'Password for all users: Password123!';
    RAISE NOTICE '';
    RAISE NOTICE 'Tables created and seeded:';
    RAISE NOTICE '  - 25 database tables';
    RAISE NOTICE '  - 25 medical specialties';
    RAISE NOTICE '  - 8 Nablus regions';
    RAISE NOTICE '  - 5 sample clinics';
    RAISE NOTICE '  - 3 doctors with availability';
    RAISE NOTICE '  - 3 patients';
    RAISE NOTICE '  - Sample appointments, records, prescriptions';
    RAISE NOTICE '========================================';
END $$;
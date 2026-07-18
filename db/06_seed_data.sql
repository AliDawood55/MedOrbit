-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Seed Data
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- Specialties (25 medical specialties)
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
('طب إعادة التأهيل', 'Physiotherapy', 'العلاج الطبيعي والتأهيلي', 'Physical therapy and rehabilitation', 'person-walking')
ON CONFLICT DO NOTHING;

-- =====================================================
-- Nablus Regions
-- =====================================================
INSERT INTO nablus_regions (name_ar, name_en, boundary_geojson) VALUES
('المدينة القديمة', 'Old City', '{"type": "Polygon", "coordinates": [[[35.26, 32.22], [35.27, 32.22], [35.27, 32.21], [35.26, 32.21], [35.26, 32.22]]]}'),
('رفيديا', 'Rafidia', '{"type": "Polygon", "coordinates": [[[35.25, 32.23], [35.26, 32.23], [35.26, 32.22], [35.25, 32.22], [35.25, 32.23]]]}'),
('عين بيت الماء', 'Ein Beit El Ma', '{"type": "Polygon", "coordinates": [[[35.24, 32.22], [35.25, 32.22], [35.25, 32.21], [35.24, 32.21], [35.24, 32.22]]]}'),
('الباذنجان', 'Al-Batin', '{"type": "Polygon", "coordinates": [[[35.23, 32.21], [35.24, 32.21], [35.24, 32.20], [35.23, 32.20], [35.23, 32.21]]]}'),
('الخالدية', 'Al-Khalidiyah', '{"type": "Polygon", "coordinates": [[[35.27, 32.23], [35.28, 32.23], [35.28, 32.22], [35.27, 32.22], [35.27, 32.23]]]}'),
('النزهة', 'Al-Nazha', '{"type": "Polygon", "coordinates": [[[35.26, 32.24], [35.27, 32.24], [35.27, 32.23], [35.26, 32.23], [35.26, 32.24]]]}'),
('الإسكان', 'Al-Iskan', '{"type": "Polygon", "coordinates": [[[35.25, 32.24], [35.26, 32.24], [35.26, 32.23], [35.25, 32.23], [35.25, 32.24]]]}'),
('شارع رقم 60', '60 Street', '{"type": "Polygon", "coordinates": [[[35.28, 32.21], [35.29, 32.21], [35.29, 32.20], [35.28, 32.20], [35.28, 32.21]]]}')
ON CONFLICT DO NOTHING;

-- =====================================================
-- System Settings
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
('refresh_token_expiry_days', '7', 'Refresh token expiry in days', false)
ON CONFLICT DO NOTHING;

-- =====================================================
-- Medications (10 common drugs)
-- =====================================================
INSERT INTO medications (name_ar, name_en, generic_name, drug_class, active_ingredients, contraindications, side_effects, known_interactions) VALUES
('باراسيتامول', 'Paracetamol', 'Acetaminophen', 'Analgesic', '{Acetaminophen}', '{"Liver disease","Alcohol use"}', '{Nausea,"Allergic reactions"}', '{}'),
('أوميبرازول', 'Omeprazole', 'Omeprazole', 'Proton Pump Inhibitor', '{Omeprazole}', '{Hypersensitivity}', '{Headache,Nausea}', '{}'),
('أملوديبين', 'Amlodipine', 'Amlodipine Besylate', 'Calcium Channel Blocker', '{Amlodipine}', '{"Cardiogenic shock","Severe hypotension"}', '{Edema,Fatigue,Dizziness}', '{}'),
('ميتفورمين', 'Metformin', 'Metformin Hydrochloride', 'Biguanide', '{Metformin}', '{"Kidney disease","Liver disease"}', '{Nausea,Diarrhea,"Stomach pain"}', '{}'),
('لورنوكسيكام', 'Lornoxicam', 'Lornoxicam', 'NSAID', '{Lornoxicam}', '{"Peptic ulcer",Asthma}', '{Nausea,"Stomach pain",Dizziness}', '{}'),
('أزيثرومايسين', 'Azithromycin', 'Azithromycin Dihydrate', 'Macrolide Antibiotic', '{Azithromycin}', '{"Liver problems"}', '{Nausea,Diarrhea,"Abdominal pain"}', '{}'),
('ديكلوفيناك', 'Diclofenac', 'Diclofenac Sodium', 'NSAID', '{Diclofenac}', '{"Active peptic ulcer",Asthma}', '{"Stomach pain",Nausea,Headache}', '{}'),
('كانديسارتان', 'Candesartan', 'Candesartan Cilexetil', 'ARB', '{Candesartan}', '{Pregnancy,"Biliary obstruction"}', '{Dizziness,Headache,"Back pain"}', '{}'),
('أسبرين', 'Aspirin', 'Acetylsalicylic Acid', 'NSAID', '{Aspirin}', '{"Peptic ulcer","Bleeding disorders"}', '{"Stomach irritation",Nausea}', '{"Warfarin": "Moderate - increases bleeding risk", "Ibuprofen": "Moderate - increases bleeding risk"}'),
('وارفارين', 'Warfarin', 'Warfarin Sodium', 'Anticoagulant', '{Warfarin}', '{"Active bleeding",Pregnancy}', '{Bleeding,Bruising}', '{"Aspirin": "Moderate - increases bleeding risk"}')
ON CONFLICT DO NOTHING;

-- =====================================================
-- Test Users (password: all use $2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa)
-- =====================================================
INSERT INTO users (id, email, password_hash, role, is_active, email_verified, preferred_language) VALUES
('a1111111-1111-1111-1111-111111111111', 'admin@medorbit.ps', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'admin', true, true, 'ar'),
('d2222222-2222-2222-2222-222222222221', 'dr.smith@medorbit.ps', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'doctor', true, true, 'en'),
('d2222222-2222-2222-2222-222222222222', 'dr.johnson@medorbit.ps', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'doctor', true, true, 'ar'),
('d2222222-2222-2222-2222-222222222223', 'dr.williams@medorbit.ps', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'doctor', true, true, 'en'),
('a3333333-3333-3333-3333-333333333331', 'mahmoud@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'patient', true, true, 'ar'),
('a3333333-3333-3333-3333-333333333332', 'fatima@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'patient', true, true, 'ar'),
('a3333333-3333-3333-3333-333333333333', 'john@example.com', '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/X4.QW7sR6yQxJz8Oa', 'patient', true, true, 'en')
ON CONFLICT DO NOTHING;

-- =====================================================
-- User Profiles
-- =====================================================
INSERT INTO user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en, phone, date_of_birth, gender, address, city) VALUES
('a1111111-1111-1111-1111-111111111111', 'أحمد', 'المدير', 'Ahmad', 'Administrator', '+970-9-2345678', '1985-05-15', 'male', 'شارع الرئيسي، نابلس', 'Nablus'),
('d2222222-2222-2222-2222-222222222221', 'محمد', 'أحمد', 'Mohammad', 'Smith', '+970-9-2345671', '1980-03-20', 'male', 'رفيديا، نابلس', 'Nablus'),
('d2222222-2222-2222-2222-222222222222', 'أحمد', 'عبدالله', 'Ahmad', 'Johnson', '+970-9-2345672', '1978-07-15', 'male', 'المدينة القديمة، نابلس', 'Nablus'),
('d2222222-2222-2222-2222-222222222223', 'سارة', 'ويليامز', 'Sarah', 'Williams', '+970-9-2345673', '1985-11-25', 'female', 'عين بيت الماء، نابلس', 'Nablus'),
('a3333333-3333-3333-3333-333333333331', 'محمود', 'الخالدي', 'Mahmoud', 'Al-Khalidi', '+970-59-1234567', '1990-08-10', 'male', 'شارع رقم 60، نابلس', 'Nablus'),
('a3333333-3333-3333-3333-333333333332', 'فاطمة', 'الزيود', 'Fatima', 'Al-Zioud', '+970-59-2345678', '1985-12-20', 'female', 'الخالدية، نابلس', 'Nablus'),
('a3333333-3333-3333-3333-333333333333', 'جون', 'سميث', 'John', 'Smith', '+970-59-3456789', '1995-04-15', 'male', 'الإسكان، نابلس', 'Nablus')
ON CONFLICT DO NOTHING;

-- =====================================================
-- Patients
-- =====================================================
INSERT INTO patients (user_id, blood_type, allergies, chronic_conditions, emergency_contact_name, emergency_contact_phone, insurance_provider, insurance_policy_number) VALUES
('a3333333-3333-3333-3333-333333333331', 'O+', '{البنسلين}', '{"لا يوجد"}', 'خالد الخالدي', '+970-59-9876543', 'الأردنية للتأمين', 'INS-001234'),
('a3333333-3333-3333-3333-333333333332', 'A+', '{}', '{السكري}', 'عبدالله الزيود', '+970-59-8765432', 'التأمين الصحي الحكومي', 'GOV-005678'),
('a3333333-3333-3333-3333-333333333333', 'B+', '{}', '{}', 'ماريا سميث', '+970-59-7654321', NULL, NULL)
ON CONFLICT DO NOTHING;

-- =====================================================
-- Doctors
-- =====================================================
INSERT INTO doctors (user_id, medical_license_number, specialty_id, years_of_experience, consultation_fee, consultation_duration, education, certifications, professional_bio_ar, professional_bio_en, is_accepting_patients, average_rating, total_ratings)
SELECT u.id, 'ML-2020-001', s.id, 15, 100.00, 30,
    '{"MD - University of Jordan","Fellowship - Cleveland Clinic"}',
    '{"Jordan Medical Board Certified","American Board Eligible"}',
    'دكتور محمد أحمد هو طبيب قلب معتمد بخبرة 15 عاماً في تشخيص وعلاج أمراض القلب. متخصص في علاج ارتفاع ضغط الدم وأمراض الشرايين.',
    'Dr. Mohammad Smith is a certified cardiologist with 15 years of experience in diagnosing and treating heart diseases. Specialized in hypertension and arterial disease treatment.',
    true, 4.80, 45
FROM users u, specialties s
WHERE u.email = 'dr.smith@medorbit.ps' AND s.name_en = 'Cardiology'
ON CONFLICT DO NOTHING;

INSERT INTO doctors (user_id, medical_license_number, specialty_id, years_of_experience, consultation_fee, consultation_duration, education, certifications, professional_bio_ar, professional_bio_en, is_accepting_patients, average_rating, total_ratings)
SELECT u.id, 'ML-2020-002', s.id, 20, 80.00, 30,
    '{"MD - An-Najah National University","Specialty - Damascus University"}',
    '{"Palestinian Medical Board"}',
    'دكتور أحمد عبدالله هو طبيب عام متمرس يقدم خدمات الرعاية الصحية الأولية لجميع أفراد العائلة.',
    'Dr. Ahmad Abdullah is an experienced general practitioner providing primary healthcare services for all family members.',
    true, 4.50, 120
FROM users u, specialties s
WHERE u.email = 'dr.johnson@medorbit.ps' AND s.name_en = 'General Practice'
ON CONFLICT DO NOTHING;

INSERT INTO doctors (user_id, medical_license_number, specialty_id, years_of_experience, consultation_fee, consultation_duration, education, certifications, professional_bio_ar, professional_bio_en, is_accepting_patients, average_rating, total_ratings)
SELECT u.id, 'ML-2020-003', s.id, 12, 150.00, 45,
    '{"MD - Harvard Medical School","Fellowship - Boston Children Hospital"}',
    '{"American Board of Pediatrics","Neonatal Resuscitation Program"}',
    'دكتورة سارة ويليامز هي طبيبة أطفال متخصصة في رعاية المواليد والأطفال. تقدم خدمات التطعيم والفحوصات الدورية.',
    'Dr. Sarah Williams is a pediatrician specialized in neonatal and child care. Provides vaccination and regular checkup services.',
    true, 4.90, 78
FROM users u, specialties s
WHERE u.email = 'dr.williams@medorbit.ps' AND s.name_en = 'Pediatrics'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Clinics
-- =====================================================
INSERT INTO clinics (name_ar, name_en, address_ar, address_en, city, region, latitude, longitude, phone, email, type, services, insurance_accepted, verification_status) VALUES
('مستشفى نابلس الطبي', 'Nablus Medical Hospital', 'شارع رقم 60، نابلس', '60 Street, Nablus', 'Nablus', 'شارع رقم 60', 32.22340000, 35.25780000, '+970-9-2381000', 'info@nablusmed.ps', 'hospital', '{طوارئ,"عناية مركزة",عمليات,أشعة,مختبر}', '{"الأردنية للتأمين","التأمين الصحي الحكومي","التأمين الصحي الخاص"}', 'verified'),
('عيادة القلب المتميزة', 'Elite Cardiac Clinic', 'رفيديا، شارع المستشفى القديم', 'Rafidia, Old Hospital Street', 'Nablus', 'رفيديا', 32.22560000, 35.25230000, '+970-9-2345671', 'cardio@eliteclinic.ps', 'clinic', '{"تخطيط القلب",إيكو,"اختبار الإجهاد"}', '{"الأردنية للتأمين","التأمين الصحي الخاص"}', 'verified'),
('مركز الرعاية الصحية الأولية', 'Primary Healthcare Center', 'المدينة القديمة، قرب السوق', 'Old City, Near the Market', 'Nablus', 'المدينة القديمة', 32.21980000, 35.25120000, '+970-9-2381234', 'phc@nablus.ps', 'medical_center', '{"طب عام",تطعيمات,"رعاية الأم والطفل"}', '{"التأمين الصحي الحكومي"}', 'verified'),
('عيادة الأطفال السعيدة', 'Happy Kids Clinic', 'عين بيت الماء، قرب مدرسة بنات', 'Ein Beit El Ma, Near Girls School', 'Nablus', 'عين بيت الماء', 32.22150000, 35.24890000, '+970-9-2345673', 'kids@happyclinic.ps', 'clinic', '{"طب أطفال",تطعيمات,"فحص نمو"}', '{"الأردنية للتأمين","التأمين الصحي الحكومي","التأمين الصحي الخاص"}', 'verified'),
('مركز المستقبل للأشعة', 'Future Radiology Center', 'الخالدية، بجوار البنك الإسلامي', 'Al-Khalidiyah, Next to Islamic Bank', 'Nablus', 'الخالدية', 32.22780000, 35.25900000, '+970-9-2345674', 'radio@future.ps', 'radiology', '{"أشعة عادية",سونار,"رنين مغناطيسي","أشعة مقطعية"}', '{"الأردنية للتأمين","التأمين الصحي الخاص"}', 'verified')
ON CONFLICT DO NOTHING;

-- =====================================================
-- Doctor-Clinic Assignments
-- =====================================================
INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT d.id, c.id, 150.00, true
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-001' AND c.name_en = 'Nablus Medical Hospital'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT d.id, c.id, 100.00, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-001' AND c.name_en = 'Elite Cardiac Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT d.id, c.id, 50.00, true
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT d.id, c.id, 180.00, true
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-003' AND c.name_en = 'Nablus Medical Hospital'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_clinic_assignments (doctor_id, clinic_id, consultation_fee_override, is_primary)
SELECT d.id, c.id, 120.00, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-003' AND c.name_en = 'Happy Kids Clinic'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Doctor Availability
-- =====================================================
INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 0, '08:00:00', '12:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-001' AND c.name_en = 'Elite Cardiac Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 2, '08:00:00', '12:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-001' AND c.name_en = 'Elite Cardiac Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 4, '08:00:00', '12:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-001' AND c.name_en = 'Elite Cardiac Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, NULL, 6, '09:00:00', '13:00:00', 30, true
FROM doctors d
WHERE d.medical_license_number = 'ML-2020-001'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 1, '08:00:00', '15:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 2, '08:00:00', '15:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 3, '08:00:00', '15:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 4, '08:00:00', '15:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 5, '08:00:00', '12:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 0, '09:00:00', '17:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-003' AND c.name_en = 'Happy Kids Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 1, '09:00:00', '17:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-003' AND c.name_en = 'Happy Kids Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 3, '09:00:00', '17:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-003' AND c.name_en = 'Happy Kids Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO doctor_availability (doctor_id, clinic_id, day_of_week, start_time, end_time, slot_duration, is_telemedicine)
SELECT d.id, c.id, 5, '09:00:00', '13:00:00', 30, false
FROM doctors d, clinics c
WHERE d.medical_license_number = 'ML-2020-003' AND c.name_en = 'Happy Kids Clinic'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Appointments
-- =====================================================
INSERT INTO appointments (appointment_number, patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
SELECT 'APT-2026-000001', pat.id, d.id, c.id, '2026-07-04', '09:00:00', '09:30:00', 30, 'in_person', 'completed', 'فحص دوري للقلب'
FROM patients pat, doctors d, clinics c
WHERE pat.user_id = 'a3333333-3333-3333-3333-333333333331' AND d.medical_license_number = 'ML-2020-001' AND c.name_en = 'Elite Cardiac Clinic'
ON CONFLICT DO NOTHING;

INSERT INTO appointments (appointment_number, patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
SELECT 'APT-2026-000002', pat.id, d.id, c.id, '2026-07-14', '10:00:00', '10:30:00', 30, 'in_person', 'confirmed', 'صداع مستمر'
FROM patients pat, doctors d, clinics c
WHERE pat.user_id = 'a3333333-3333-3333-3333-333333333331' AND d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO appointments (appointment_number, patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
SELECT 'APT-2026-000003', pat.id, d.id, c.id, '2026-07-12', '11:00:00', '11:30:00', 30, 'in_person', 'scheduled', 'متابعة السكري'
FROM patients pat, doctors d, clinics c
WHERE pat.user_id = 'a3333333-3333-3333-3333-333333333332' AND d.medical_license_number = 'ML-2020-002' AND c.name_en = 'Primary Healthcare Center'
ON CONFLICT DO NOTHING;

INSERT INTO appointments (appointment_number, patient_id, doctor_id, clinic_id, scheduled_date, start_time, end_time, duration_minutes, appointment_type, status, reason_for_visit)
SELECT 'APT-2026-000004', pat.id, d.id, NULL, '2026-07-16', '14:00:00', '14:45:00', 45, 'telemedicine', 'confirmed', 'استشارة حول تطعيمات الطفل'
FROM patients pat, doctors d
WHERE pat.user_id = 'a3333333-3333-3333-3333-333333333333' AND d.medical_license_number = 'ML-2020-003'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Medical Records
-- =====================================================
INSERT INTO medical_records (record_number, patient_id, doctor_id, record_type, chief_complaint, symptoms, diagnosis, treatment_plan, vitals)
SELECT 'MR-2026-000001', pat.id, d.id, 'consultation', 'فحص دوري للقلب', '{"ألم خفيف في الصدر","ضيق تنفس عند المجهود"}', 'ارتفاع طفيف في ضغط الدم مع معدل ضربات قلب طبيعي', 'استمرار الأدوية الحالية مع متابعة ضغط الدم يومياً. تقليل الملح في الطعام.', '{"weight": 85, "heart_rate": 72, "temperature": 36.8, "blood_pressure": "130/85"}'
FROM patients pat, doctors d
WHERE pat.user_id = 'a3333333-3333-3333-3333-333333333331' AND d.medical_license_number = 'ML-2020-001'
ON CONFLICT DO NOTHING;

INSERT INTO medical_records (record_number, patient_id, doctor_id, record_type, chief_complaint, symptoms, diagnosis, treatment_plan, vitals)
SELECT 'MR-2026-000002', pat.id, d.id, 'consultation', 'صداع مستمر', '{"صداع في مقدمة الرأس",دوخة,أرق}', 'توتر وصداع توتري', 'راحة وتجنب التوتر. مسكن للصداع عند الحاجة. متابعة في حال استمرار الأعراض.', '{"heart_rate": 75, "blood_pressure": "125/80"}'
FROM patients pat, doctors d
WHERE pat.user_id = 'a3333333-3333-3333-3333-333333333331' AND d.medical_license_number = 'ML-2020-002'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Prescriptions
-- =====================================================
INSERT INTO prescriptions (prescription_number, patient_id, doctor_id, prescription_date, status, diagnosis, instructions)
SELECT 'RX-2026-000001', pat.id, d.id, '2026-07-11', 'active', 'ارتفاع ضغط الدم الخفيف', 'اتباع نظام غذائي صحي وتقليل الملح'
FROM patients pat, doctors d
WHERE pat.user_id = 'a3333333-3333-3333-3333-333333333331' AND d.medical_license_number = 'ML-2020-001'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Prescription Items
-- =====================================================
INSERT INTO prescription_items (prescription_id, medication_name_ar, medication_name_en, dosage, frequency, duration, quantity, instructions)
SELECT rx.id, 'أملوديبين', 'Amlodipine', '5mg', 'مرة واحدة يومياً', '30 يوم', 30, 'يُؤخذ في الصباح مع الطعام'
FROM prescriptions rx
WHERE rx.prescription_number = 'RX-2026-000001'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Doctor Reviews
-- =====================================================
INSERT INTO doctor_reviews (appointment_id, patient_id, doctor_id, rating, review_text_ar, review_text_en, professionalism_rating, treatment_rating, communication_rating)
SELECT apt.id, pat.id, d.id, 5, 'دكتور ممتاز وفريق العمل جداً محترفين. شرح لي الحالة بوضوح.', 'Excellent doctor and very professional staff. Explained my condition clearly.', 5, 5, 5
FROM appointments apt, patients pat, doctors d
WHERE apt.appointment_number = 'APT-2026-000001' AND pat.user_id = 'a3333333-3333-3333-3333-333333333331' AND d.medical_license_number = 'ML-2020-001'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Notifications
-- =====================================================
INSERT INTO notifications (user_id, title_ar, title_en, message_ar, message_en, notification_type, channel, is_read)
SELECT u.id, 'تأكيد الموعد', 'Appointment Confirmed', 'تم تأكيد موعدك مع دكتور أحمد عبدالله يوم غد الساعة 10:00 صباحاً', 'Your appointment with Dr. Ahmad Abdullah has been confirmed for tomorrow at 10:00 AM', 'appointment', 'in_app', true
FROM users u WHERE u.email = 'mahmoud@example.com'
ON CONFLICT DO NOTHING;

INSERT INTO notifications (user_id, title_ar, title_en, message_ar, message_en, notification_type, channel, is_read)
SELECT u.id, 'تذكير', 'Reminder', 'لا تنسَ موعدك غداً الساعة 10:00 صباحاً مع دكتور أحمد عبدالله', 'Don''t forget your appointment tomorrow at 10:00 AM with Dr. Ahmad Abdullah', 'reminder', 'in_app', false
FROM users u WHERE u.email = 'mahmoud@example.com'
ON CONFLICT DO NOTHING;

INSERT INTO notifications (user_id, title_ar, title_en, message_ar, message_en, notification_type, channel, is_read)
SELECT u.id, 'مستخدم جديد', 'New User', 'تم تسجيل مستخدم جديد: محمود الخالدي', 'New user registered: Mahmoud Al-Khalidi', 'system', 'in_app', false
FROM users u WHERE u.email = 'admin@medorbit.ps'
ON CONFLICT DO NOTHING;

-- =====================================================
-- Symptom-Specialty Mappings (T-044 / T-046)
-- =====================================================
INSERT INTO symptom_specialty_mappings (symptom_keyword, symptom_keyword_ar, specialty_id, weight)
SELECT 'chest pain', 'ألم في الصدر', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'palpitations', 'خفقان', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'shortness of breath', 'ضيق في التنفس', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'high blood pressure', 'ضغط دم مرتفع', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'low blood pressure', 'ضغط دم منخفض', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'heart murmur', 'لغط قلبي', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'swollen ankles', 'تورم في الكاحلين', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'irregular heartbeat', 'نبض غير منتظم', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Cardiology'
UNION ALL SELECT 'child fever', 'حمى طفل', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'child cough', 'سعال طفل', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'child rash', 'طفح جلدي طفل', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'baby not eating', 'الرضيع لا يأكل', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'growth delay', 'تأخر النمو', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'child vomiting', 'تقيؤ طفل', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'colic', 'مغص', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'child diarrhea', 'إسهال طفل', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Pediatrics'
UNION ALL SELECT 'pregnancy', 'حمل', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Obstetrics & Gynecology'
UNION ALL SELECT 'missed period', 'تأخر الدورة', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Obstetrics & Gynecology'
UNION ALL SELECT 'vaginal bleeding', 'نزيف مهبلي', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Obstetrics & Gynecology'
UNION ALL SELECT 'pelvic pain', 'ألم حوضي', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Obstetrics & Gynecology'
UNION ALL SELECT 'irregular menstruation', 'دورة شهرية غير منتظمة', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Obstetrics & Gynecology'
UNION ALL SELECT 'breast lump', 'كتلة في الثدي', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Obstetrics & Gynecology'
UNION ALL SELECT 'menopause symptoms', 'أعراض سن اليأس', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Obstetrics & Gynecology'
UNION ALL SELECT 'back pain', 'ألم في الظهر', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'joint pain', 'ألم في المفاصل', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'knee pain', 'ألم في الركبة', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'fracture', 'كسر', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'sprain', 'التواء', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'neck pain', 'ألم في الرقبة', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'shoulder pain', 'ألم في الكتف', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'bone pain', 'ألم في العظام', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'muscle pain', 'ألم في العضلات', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Orthopedics'
UNION ALL SELECT 'blurred vision', 'ضعف النظر', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Ophthalmology'
UNION ALL SELECT 'eye pain', 'ألم في العين', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Ophthalmology'
UNION ALL SELECT 'eye redness', 'احمرار العين', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Ophthalmology'
UNION ALL SELECT 'dry eyes', 'جفاف العين', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Ophthalmology'
UNION ALL SELECT 'eye discharge', 'إفرازات عين', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Ophthalmology'
UNION ALL SELECT 'sore throat', 'ألم في الحلق', s.id, 2.50 FROM specialties s WHERE s.name_en = 'ENT'
UNION ALL SELECT 'ear pain', 'ألم في الأذن', s.id, 3.00 FROM specialties s WHERE s.name_en = 'ENT'
UNION ALL SELECT 'hearing loss', 'فقدان السمع', s.id, 3.00 FROM specialties s WHERE s.name_en = 'ENT'
UNION ALL SELECT 'nasal congestion', 'انسداد الأنف', s.id, 2.00 FROM specialties s WHERE s.name_en = 'ENT'
UNION ALL SELECT 'sinus pressure', 'ضغط الجيوب الأنفية', s.id, 2.50 FROM specialties s WHERE s.name_en = 'ENT'
UNION ALL SELECT 'tonsillitis', 'التهاب اللوزتين', s.id, 2.50 FROM specialties s WHERE s.name_en = 'ENT'
UNION ALL SELECT 'ringing in ears', 'طنين في الأذن', s.id, 2.50 FROM specialties s WHERE s.name_en = 'ENT'
UNION ALL SELECT 'skin rash', 'طفح جلدي', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'itching', 'حكة', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'acne', 'حب الشباب', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'eczema', 'إكزيما', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'psoriasis', 'صدفية', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'skin infection', 'عدوى جلدية', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'hair loss', 'تساقط الشعر', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'burn', 'حرق', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'wound', 'جرح', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Dermatology'
UNION ALL SELECT 'toothache', 'ألم في الأسنان', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Dentistry'
UNION ALL SELECT 'gum bleeding', 'نزيف اللثة', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Dentistry'
UNION ALL SELECT 'tooth sensitivity', 'حساسية الأسنان', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Dentistry'
UNION ALL SELECT 'swollen gum', 'تورم اللثة', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Dentistry'
UNION ALL SELECT 'jaw pain', 'ألم في الفك', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Dentistry'
UNION ALL SELECT 'headache', 'صداع', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'migraine', 'شقيقة', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'seizure', 'نوبة صرع', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'numbness', 'خدر', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'tingling', 'تنميل', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'memory loss', 'فقدان الذاكرة', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'tremor', 'رعشة', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'fainting', 'إغماء', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Neurology'
UNION ALL SELECT 'anxiety', 'قلق', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Psychiatry'
UNION ALL SELECT 'depression', 'اكتئاب', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Psychiatry'
UNION ALL SELECT 'insomnia', 'أرق', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Psychiatry'
UNION ALL SELECT 'panic attack', 'نوبة هلع', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Psychiatry'
UNION ALL SELECT 'mood swings', 'تقلبات مزاجية', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Psychiatry'
UNION ALL SELECT 'stress', 'توتر', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Psychiatry'
UNION ALL SELECT 'stomach pain', 'ألم في المعدة', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'nausea', 'غثيان', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'vomiting', 'تقيؤ', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'diarrhea', 'إسهال', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'constipation', 'إمساك', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'bloating', 'انتفاخ', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'heartburn', 'حرقة المعدة', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'blood in stool', 'دم في البراز', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'appetite loss', 'فقدان الشهية', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'jaundice', 'يرقان', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Gastroenterology'
UNION ALL SELECT 'excessive thirst', 'عطش شديد', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Endocrinology'
UNION ALL SELECT 'frequent urination', 'تبول متكرر', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Endocrinology'
UNION ALL SELECT 'diabetes', 'سكري', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Endocrinology'
UNION ALL SELECT 'thyroid', 'غدة درقية', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Endocrinology'
UNION ALL SELECT 'excessive sweating', 'تعرق شديد', s.id, 1.50 FROM specialties s WHERE s.name_en = 'Endocrinology'
UNION ALL SELECT 'kidney pain', 'ألم في الكلى', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Nephrology'
UNION ALL SELECT 'blood in urine', 'دم في البول', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Nephrology'
UNION ALL SELECT 'urinary problems', 'مشاكل بولية', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Nephrology'
UNION ALL SELECT 'flank pain', 'ألم في الجنب', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Nephrology'
UNION ALL SELECT 'unexplained weight loss', 'فقدان وزن غير مبرر', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Oncology'
UNION ALL SELECT 'lump', 'كتلة', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Oncology'
UNION ALL SELECT 'persistent cough', 'سعال مستمر', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Oncology'
UNION ALL SELECT 'night sweats', 'تعرق ليلي', s.id, 2.00 FROM specialties s WHERE s.name_en = 'Oncology'
UNION ALL SELECT 'unexplained bleeding', 'نزيف غير مبرر', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Oncology'
UNION ALL SELECT 'chronic cough', 'سعال مزمن', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Pulmonology'
UNION ALL SELECT 'wheezing', 'أزيز', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Pulmonology'
UNION ALL SELECT 'breathing difficulty', 'صعوبة في التنفس', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Pulmonology'
UNION ALL SELECT 'coughing blood', 'سعال دموي', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Pulmonology'
UNION ALL SELECT 'asthma', 'ربو', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Pulmonology'
UNION ALL SELECT 'chest tightness', 'ضيق في الصدر', s.id, 2.50 FROM specialties s WHERE s.name_en = 'Pulmonology'
UNION ALL SELECT 'joint swelling', 'تورم المفاصل', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Rheumatology'
UNION ALL SELECT 'morning stiffness', 'تيبس صباحي', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Rheumatology'
UNION ALL SELECT 'arthritis', 'التهاب المفاصل', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Rheumatology'
UNION ALL SELECT 'lupus', 'ذئبة', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Rheumatology'
UNION ALL SELECT 'appendicitis', 'التهاب الزائدة', s.id, 4.00 FROM specialties s WHERE s.name_en = 'General Surgery'
UNION ALL SELECT 'hernia', 'فتق', s.id, 4.00 FROM specialties s WHERE s.name_en = 'General Surgery'
UNION ALL SELECT 'gallbladder pain', 'ألم المرارة', s.id, 3.50 FROM specialties s WHERE s.name_en = 'General Surgery'
UNION ALL SELECT 'abdominal pain', 'ألم في البطن', s.id, 2.00 FROM specialties s WHERE s.name_en = 'General Surgery'
UNION ALL SELECT 'urinary retention', 'احتباس البول', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Urology'
UNION ALL SELECT 'prostate problems', 'مشاكل البروستاتا', s.id, 3.50 FROM specialties s WHERE s.name_en = 'Urology'
UNION ALL SELECT 'painful urination', 'ألم أثناء التبول', s.id, 3.00 FROM specialties s WHERE s.name_en = 'Urology'
UNION ALL SELECT 'fever', 'حمى', s.id, 1.00 FROM specialties s WHERE s.name_en = 'General Practice'
UNION ALL SELECT 'cold', 'زكام', s.id, 1.00 FROM specialties s WHERE s.name_en = 'General Practice'
UNION ALL SELECT 'flu', 'انفلونزا', s.id, 1.00 FROM specialties s WHERE s.name_en = 'General Practice'
UNION ALL SELECT 'cough', 'سعال', s.id, 0.80 FROM specialties s WHERE s.name_en = 'General Practice'
UNION ALL SELECT 'body aches', 'آلام في الجسم', s.id, 0.80 FROM specialties s WHERE s.name_en = 'General Practice'
UNION ALL SELECT 'severe chest pain', 'ألم صدري حاد', s.id, 5.00 FROM specialties s WHERE s.name_en = 'Emergency Medicine'
UNION ALL SELECT 'difficulty breathing', 'صعوبة التنفس', s.id, 4.50 FROM specialties s WHERE s.name_en = 'Emergency Medicine'
UNION ALL SELECT 'unconscious', 'فقدان الوعي', s.id, 5.00 FROM specialties s WHERE s.name_en = 'Emergency Medicine'
UNION ALL SELECT 'severe bleeding', 'نزيف حاد', s.id, 5.00 FROM specialties s WHERE s.name_en = 'Emergency Medicine'
UNION ALL SELECT 'allergic reaction', 'رد فعل تحسسي', s.id, 4.00 FROM specialties s WHERE s.name_en = 'Emergency Medicine'
UNION ALL SELECT 'choking', 'اختناق', s.id, 5.00 FROM specialties s WHERE s.name_en = 'Emergency Medicine'
UNION ALL SELECT 'poisoning', 'تسمم', s.id, 5.00 FROM specialties s WHERE s.name_en = 'Emergency Medicine'
ON CONFLICT DO NOTHING;
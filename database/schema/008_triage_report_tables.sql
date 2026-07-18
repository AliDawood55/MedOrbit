-- =====================================================
-- MIGRATION 008: Triage & Report Summarization Tables
-- Dependencies: 001_medorbit_schema.sql (specialties, symptom_triage_sessions, medical_records)
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- Table: symptom_specialty_mappings
-- Rule-based symptom -> specialty lookup for triage engine
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

CREATE INDEX IF NOT EXISTS idx_ssm_symptom ON symptom_specialty_mappings(symptom_keyword);
CREATE INDEX IF NOT EXISTS idx_ssm_symptom_ar ON symptom_specialty_mappings(symptom_keyword_ar);
CREATE INDEX IF NOT EXISTS idx_ssm_specialty ON symptom_specialty_mappings(specialty_id);

-- =====================================================
-- Table: report_summarizations
-- Persisted LLM-generated report summaries (bilingual)
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

CREATE INDEX IF NOT EXISTS idx_rsum_record ON report_summarizations(record_id);
CREATE INDEX IF NOT EXISTS idx_rsum_user ON report_summarizations(user_id);

-- =====================================================
-- SEED: Symptom-Specialty Mappings
-- =====================================================
INSERT INTO symptom_specialty_mappings (symptom_keyword, symptom_keyword_ar, specialty_id, weight) VALUES
-- Cardiology
('chest pain', 'ألم في الصدر', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 3.00),
('palpitations', 'خفقان', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 2.50),
('shortness of breath', 'ضيق في التنفس', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 2.00),
('high blood pressure', 'ضغط دم مرتفع', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 2.50),
('low blood pressure', 'ضغط دم منخفض', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 2.00),
('heart murmur', 'لغط قلبي', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 3.00),
('swollen ankles', 'تورم في الكاحلين', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 1.50),
('irregular heartbeat', 'نبض غير منتظم', (SELECT id FROM specialties WHERE name_en = 'Cardiology' LIMIT 1), 2.50),

-- Pediatrics
('child fever', 'حمى طفل', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 3.00),
('child cough', 'سعال طفل', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 2.00),
('child rash', 'طفح جلدي طفل', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 2.00),
('baby not eating', 'الرضيع لا يأكل', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 2.50),
('growth delay', 'تأخر النمو', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 2.50),
('child vomiting', 'تقيؤ طفل', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 2.00),
('colic', 'مغص', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 1.50),
('child diarrhea', 'إسهال طفل', (SELECT id FROM specialties WHERE name_en = 'Pediatrics' LIMIT 1), 2.00),

-- Obstetrics & Gynecology
('pregnancy', 'حمل', (SELECT id FROM specialties WHERE name_en = 'Obstetrics & Gynecology' LIMIT 1), 4.00),
('missed period', 'تأخر الدورة', (SELECT id FROM specialties WHERE name_en = 'Obstetrics & Gynecology' LIMIT 1), 3.00),
('vaginal bleeding', 'نزيف مهبلي', (SELECT id FROM specialties WHERE name_en = 'Obstetrics & Gynecology' LIMIT 1), 3.00),
('pelvic pain', 'ألم حوضي', (SELECT id FROM specialties WHERE name_en = 'Obstetrics & Gynecology' LIMIT 1), 3.00),
('irregular menstruation', 'دورة شهرية غير منتظمة', (SELECT id FROM specialties WHERE name_en = 'Obstetrics & Gynecology' LIMIT 1), 2.50),
('breast lump', 'كتلة في الثدي', (SELECT id FROM specialties WHERE name_en = 'Obstetrics & Gynecology' LIMIT 1), 3.00),
('menopause symptoms', 'أعراض سن اليأس', (SELECT id FROM specialties WHERE name_en = 'Obstetrics & Gynecology' LIMIT 1), 2.50),

-- Orthopedics
('back pain', 'ألم في الظهر', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 3.00),
('joint pain', 'ألم في المفاصل', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 2.50),
('knee pain', 'ألم في الركبة', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 3.00),
('fracture', 'كسر', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 4.00),
('sprain', 'التواء', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 3.00),
('neck pain', 'ألم في الرقبة', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 2.50),
('shoulder pain', 'ألم في الكتف', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 2.50),
('bone pain', 'ألم في العظام', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 2.50),
('muscle pain', 'ألم في العضلات', (SELECT id FROM specialties WHERE name_en = 'Orthopedics' LIMIT 1), 1.50),

-- Ophthalmology
('blurred vision', 'ضعف النظر', (SELECT id FROM specialties WHERE name_en = 'Ophthalmology' LIMIT 1), 3.00),
('eye pain', 'ألم في العين', (SELECT id FROM specialties WHERE name_en = 'Ophthalmology' LIMIT 1), 3.00),
('eye redness', 'احمرار العين', (SELECT id FROM specialties WHERE name_en = 'Ophthalmology' LIMIT 1), 2.50),
('dry eyes', 'جفاف العين', (SELECT id FROM specialties WHERE name_en = 'Ophthalmology' LIMIT 1), 2.00),
('eye discharge', 'إفرازات عين', (SELECT id FROM specialties WHERE name_en = 'Ophthalmology' LIMIT 1), 2.00),

-- ENT
('sore throat', 'ألم في الحلق', (SELECT id FROM specialties WHERE name_en = 'ENT' LIMIT 1), 2.50),
('ear pain', 'ألم في الأذن', (SELECT id FROM specialties WHERE name_en = 'ENT' LIMIT 1), 3.00),
('hearing loss', 'فقدان السمع', (SELECT id FROM specialties WHERE name_en = 'ENT' LIMIT 1), 3.00),
('nasal congestion', 'انسداد الأنف', (SELECT id FROM specialties WHERE name_en = 'ENT' LIMIT 1), 2.00),
('sinus pressure', 'ضغط الجيوب الأنفية', (SELECT id FROM specialties WHERE name_en = 'ENT' LIMIT 1), 2.50),
('tonsillitis', 'التهاب اللوزتين', (SELECT id FROM specialties WHERE name_en = 'ENT' LIMIT 1), 2.50),
('ringing in ears', 'طنين في الأذن', (SELECT id FROM specialties WHERE name_en = 'ENT' LIMIT 1), 2.50),

-- Dermatology
('skin rash', 'طفح جلدي', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 3.00),
('itching', 'حكة', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 2.50),
('acne', 'حب الشباب', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 2.50),
('eczema', 'إكزيما', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 3.00),
('psoriasis', 'صدفية', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 3.00),
('skin infection', 'عدوى جلدية', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 2.50),
('hair loss', 'تساقط الشعر', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 2.00),
('burn', 'حرق', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 2.00),
('wound', 'جرح', (SELECT id FROM specialties WHERE name_en = 'Dermatology' LIMIT 1), 1.50),

-- Dentistry
('toothache', 'ألم في الأسنان', (SELECT id FROM specialties WHERE name_en = 'Dentistry' LIMIT 1), 4.00),
('gum bleeding', 'نزيف اللثة', (SELECT id FROM specialties WHERE name_en = 'Dentistry' LIMIT 1), 3.00),
('tooth sensitivity', 'حساسية الأسنان', (SELECT id FROM specialties WHERE name_en = 'Dentistry' LIMIT 1), 2.50),
('swollen gum', 'تورم اللثة', (SELECT id FROM specialties WHERE name_en = 'Dentistry' LIMIT 1), 2.50),
('jaw pain', 'ألم في الفك', (SELECT id FROM specialties WHERE name_en = 'Dentistry' LIMIT 1), 2.00),

-- Neurology
('headache', 'صداع', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 2.50),
('migraine', 'شقيقة', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 3.00),
('seizure', 'نوبة صرع', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 4.00),
('numbness', 'خدر', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 2.50),
('tingling', 'تنميل', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 2.50),
('memory loss', 'فقدان الذاكرة', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 3.00),
('tremor', 'رعشة', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 2.50),
('fainting', 'إغماء', (SELECT id FROM specialties WHERE name_en = 'Neurology' LIMIT 1), 3.00),

-- Psychiatry
('anxiety', 'قلق', (SELECT id FROM specialties WHERE name_en = 'Psychiatry' LIMIT 1), 2.50),
('depression', 'اكتئاب', (SELECT id FROM specialties WHERE name_en = 'Psychiatry' LIMIT 1), 3.00),
('insomnia', 'أرق', (SELECT id FROM specialties WHERE name_en = 'Psychiatry' LIMIT 1), 2.50),
('panic attack', 'نوبة هلع', (SELECT id FROM specialties WHERE name_en = 'Psychiatry' LIMIT 1), 3.00),
('mood swings', 'تقلبات مزاجية', (SELECT id FROM specialties WHERE name_en = 'Psychiatry' LIMIT 1), 2.00),
('stress', 'توتر', (SELECT id FROM specialties WHERE name_en = 'Psychiatry' LIMIT 1), 1.50),

-- Gastroenterology
('stomach pain', 'ألم في المعدة', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 3.00),
('nausea', 'غثيان', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 2.00),
('vomiting', 'تقيؤ', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 2.00),
('diarrhea', 'إسهال', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 2.50),
('constipation', 'إمساك', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 2.00),
('bloating', 'انتفاخ', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 1.50),
('heartburn', 'حرقة المعدة', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 2.50),
('blood in stool', 'دم في البراز', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 3.50),
('appetite loss', 'فقدان الشهية', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 1.50),
('jaundice', 'يرقان', (SELECT id FROM specialties WHERE name_en = 'Gastroenterology' LIMIT 1), 3.50),

-- Endocrinology
('excessive thirst', 'عطش شديد', (SELECT id FROM specialties WHERE name_en = 'Endocrinology' LIMIT 1), 2.50),
('frequent urination', 'تبول متكرر', (SELECT id FROM specialties WHERE name_en = 'Endocrinology' LIMIT 1), 2.50),
('diabetes', 'سكري', (SELECT id FROM specialties WHERE name_en = 'Endocrinology' LIMIT 1), 4.00),
('thyroid', 'غدة درقية', (SELECT id FROM specialties WHERE name_en = 'Endocrinology' LIMIT 1), 3.50),
('excessive sweating', 'تعرق شديد', (SELECT id FROM specialties WHERE name_en = 'Endocrinology' LIMIT 1), 1.50),

-- Nephrology
('kidney pain', 'ألم في الكلى', (SELECT id FROM specialties WHERE name_en = 'Nephrology' LIMIT 1), 3.50),
('blood in urine', 'دم في البول', (SELECT id FROM specialties WHERE name_en = 'Nephrology' LIMIT 1), 4.00),
('urinary problems', 'مشاكل بولية', (SELECT id FROM specialties WHERE name_en = 'Nephrology' LIMIT 1), 2.50),
('flank pain', 'ألم في الجنب', (SELECT id FROM specialties WHERE name_en = 'Nephrology' LIMIT 1), 2.50),

-- Oncology
('unexplained weight loss', 'فقدان وزن غير مبرر', (SELECT id FROM specialties WHERE name_en = 'Oncology' LIMIT 1), 3.00),
('lump', 'كتلة', (SELECT id FROM specialties WHERE name_en = 'Oncology' LIMIT 1), 2.50),
('persistent cough', 'سعال مستمر', (SELECT id FROM specialties WHERE name_en = 'Oncology' LIMIT 1), 2.00),
('night sweats', 'تعرق ليلي', (SELECT id FROM specialties WHERE name_en = 'Oncology' LIMIT 1), 2.00),
('unexplained bleeding', 'نزيف غير مبرر', (SELECT id FROM specialties WHERE name_en = 'Oncology' LIMIT 1), 3.00),

-- Pulmonology
('chronic cough', 'سعال مزمن', (SELECT id FROM specialties WHERE name_en = 'Pulmonology' LIMIT 1), 3.00),
('wheezing', 'أزيز', (SELECT id FROM specialties WHERE name_en = 'Pulmonology' LIMIT 1), 3.00),
('breathing difficulty', 'صعوبة في التنفس', (SELECT id FROM specialties WHERE name_en = 'Pulmonology' LIMIT 1), 3.00),
('coughing blood', 'سعال دموي', (SELECT id FROM specialties WHERE name_en = 'Pulmonology' LIMIT 1), 4.00),
('asthma', 'ربو', (SELECT id FROM specialties WHERE name_en = 'Pulmonology' LIMIT 1), 3.50),
('chest tightness', 'ضيق في الصدر', (SELECT id FROM specialties WHERE name_en = 'Pulmonology' LIMIT 1), 2.50),

-- Rheumatology
('joint swelling', 'تورم المفاصل', (SELECT id FROM specialties WHERE name_en = 'Rheumatology' LIMIT 1), 3.00),
('morning stiffness', 'تيبس صباحي', (SELECT id FROM specialties WHERE name_en = 'Rheumatology' LIMIT 1), 3.00),
('arthritis', 'التهاب المفاصل', (SELECT id FROM specialties WHERE name_en = 'Rheumatology' LIMIT 1), 3.50),
('lupus', 'ذئبة', (SELECT id FROM specialties WHERE name_en = 'Rheumatology' LIMIT 1), 4.00),

-- General Surgery
('appendicitis', 'التهاب الزائدة', (SELECT id FROM specialties WHERE name_en = 'General Surgery' LIMIT 1), 4.00),
('hernia', 'فتق', (SELECT id FROM specialties WHERE name_en = 'General Surgery' LIMIT 1), 4.00),
('gallbladder pain', 'ألم المرارة', (SELECT id FROM specialties WHERE name_en = 'General Surgery' LIMIT 1), 3.50),
('abdominal pain', 'ألم في البطن', (SELECT id FROM specialties WHERE name_en = 'General Surgery' LIMIT 1), 2.00),

-- Urology
('urinary retention', 'احتباس البول', (SELECT id FROM specialties WHERE name_en = 'Urology' LIMIT 1), 3.50),
('prostate problems', 'مشاكل البروستاتا', (SELECT id FROM specialties WHERE name_en = 'Urology' LIMIT 1), 3.50),
('painful urination', 'ألم أثناء التبول', (SELECT id FROM specialties WHERE name_en = 'Urology' LIMIT 1), 3.00),

-- General Practice (low-weight catch-all)
('fever', 'حمى', (SELECT id FROM specialties WHERE name_en = 'General Practice' LIMIT 1), 1.00),
('cold', 'زكام', (SELECT id FROM specialties WHERE name_en = 'General Practice' LIMIT 1), 1.00),
('flu', 'انفلونزا', (SELECT id FROM specialties WHERE name_en = 'General Practice' LIMIT 1), 1.00),
('cough', 'سعال', (SELECT id FROM specialties WHERE name_en = 'General Practice' LIMIT 1), 0.80),
('body aches', 'آلام في الجسم', (SELECT id FROM specialties WHERE name_en = 'General Practice' LIMIT 1), 0.80),

-- Emergency Medicine (high-weight danger signals)
('severe chest pain', 'ألم صدري حاد', (SELECT id FROM specialties WHERE name_en = 'Emergency Medicine' LIMIT 1), 5.00),
('difficulty breathing', 'صعوبة التنفس', (SELECT id FROM specialties WHERE name_en = 'Emergency Medicine' LIMIT 1), 4.50),
('unconscious', 'فقدان الوعي', (SELECT id FROM specialties WHERE name_en = 'Emergency Medicine' LIMIT 1), 5.00),
('severe bleeding', 'نزيف حاد', (SELECT id FROM specialties WHERE name_en = 'Emergency Medicine' LIMIT 1), 5.00),
('allergic reaction', 'رد فعل تحسسي', (SELECT id FROM specialties WHERE name_en = 'Emergency Medicine' LIMIT 1), 4.00),
('choking', 'اختناق', (SELECT id FROM specialties WHERE name_en = 'Emergency Medicine' LIMIT 1), 5.00),
('poisoning', 'تسمم', (SELECT id FROM specialties WHERE name_en = 'Emergency Medicine' LIMIT 1), 5.00);
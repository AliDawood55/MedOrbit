-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Base Tables (no circular FK dependencies)
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- Table 1: Users (base authentication table)
-- =====================================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) NOT NULL CHECK (role IN ('patient', 'doctor', 'admin')),
    is_active BOOLEAN DEFAULT true,
    email_verified BOOLEAN DEFAULT false,
    preferred_language VARCHAR(5) DEFAULT 'ar',
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP,
    preferences JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE
);

-- =====================================================
-- Table 2: Specialties
-- =====================================================
CREATE TABLE IF NOT EXISTS specialties (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_ar VARCHAR(100) NOT NULL,
    name_en VARCHAR(100) NOT NULL,
    description_ar TEXT,
    description_en TEXT,
    icon VARCHAR(50),
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- Table 3: Medications (drug database)
-- =====================================================
CREATE TABLE IF NOT EXISTS medications (
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

-- =====================================================
-- Table 4: Clinics (healthcare facilities)
-- =====================================================
CREATE TABLE IF NOT EXISTS clinics (
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
    type VARCHAR(50) CHECK (type IN (
        'clinic', 'hospital', 'pharmacy', 'medical_center',
        'laboratory', 'radiology', 'dental', 'emergency',
        'optical', 'vaccination_center'
    )),
    operating_hours JSONB DEFAULT '{
        "sun": {"open": "08:00", "close": "17:00", "is_off": false},
        "mon": {"open": "08:00", "close": "17:00", "is_off": false},
        "tue": {"open": "08:00", "close": "17:00", "is_off": false},
        "wed": {"open": "08:00", "close": "17:00", "is_off": false},
        "thu": {"open": "08:00", "close": "17:00", "is_off": false},
        "fri": {"open": "08:00", "close": "12:00", "is_off": false},
        "sat": {"open": "00:00", "close": "00:00", "is_off": true}
    }',
    services TEXT[],
    insurance_accepted TEXT[],
    images JSONB[] DEFAULT '{}',
    logo_url VARCHAR(500),
    is_active BOOLEAN DEFAULT true,
    verification_status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_clinic_verification CHECK (verification_status IN ('pending', 'verified', 'rejected'))
);

-- =====================================================
-- Table 5: Nablus Regions
-- =====================================================
CREATE TABLE IF NOT EXISTS nablus_regions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name_ar VARCHAR(100) NOT NULL,
    name_en VARCHAR(100) NOT NULL,
    boundary_geojson TEXT,
    is_active BOOLEAN DEFAULT true
);

-- =====================================================
-- Table 6: System Settings
-- =====================================================
CREATE TABLE IF NOT EXISTS system_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    setting_key VARCHAR(100) UNIQUE NOT NULL,
    setting_value JSONB NOT NULL,
    description TEXT,
    is_public BOOLEAN DEFAULT false,
    requires_restart BOOLEAN DEFAULT false,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_by UUID REFERENCES users(id)
);

-- =====================================================
-- Table 7: Audit Logs
-- =====================================================
CREATE TABLE IF NOT EXISTS audit_logs (
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

-- =====================================================
-- Table 8: Generated Reports
-- =====================================================
CREATE TABLE IF NOT EXISTS generated_reports (
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
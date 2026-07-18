-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Migration 001: Add type column to clinics table
-- =====================================================

SET search_path TO medorbit, public;


-- =====================================================
-- Part 1: Enable Required Extensions
-- =====================================================

-- Required for location functions
CREATE EXTENSION IF NOT EXISTS postgis;

-- Required for fuzzy text search indexes
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- =====================================================
-- Part 2: Add type column to clinics
-- =====================================================

ALTER TABLE clinics 
ADD COLUMN IF NOT EXISTS type VARCHAR(50)
CHECK (
    type IN (
        'clinic',
        'hospital',
        'pharmacy',
        'medical_center',
        'laboratory',
        'radiology',
        'dental',
        'emergency',
        'optical',
        'vaccination_center'
    )
);


-- Index for filtering by healthcare type
CREATE INDEX IF NOT EXISTS idx_clinics_type
ON clinics(type);



-- =====================================================
-- Part 3: Update Existing Clinics
-- =====================================================

UPDATE clinics
SET type = 'clinic'
WHERE type IS NULL;



-- =====================================================
-- Part 4: Location Query Optimization
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_clinics_type_coordinates
ON clinics(type, latitude, longitude)
WHERE latitude IS NOT NULL 
AND longitude IS NOT NULL;



-- =====================================================
-- Part 5: Text Search Optimization
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_clinics_name_search
ON clinics
USING gin (
    name_ar gin_trgm_ops,
    name_en gin_trgm_ops
);



-- =====================================================
-- Verification
-- =====================================================

SELECT 
    column_name,
    data_type
FROM information_schema.columns
WHERE table_name = 'clinics'
AND column_name = 'type';


SELECT 
    type,
    COUNT(*)
FROM clinics
GROUP BY type;


SELECT extname
FROM pg_extension
WHERE extname IN ('postgis','pg_trgm');
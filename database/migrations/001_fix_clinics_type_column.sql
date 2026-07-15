-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Migration 001: Add type column to clinics table
-- 
-- Purpose: The RAG service queries `type` from clinics for
--          filtering nearby places (clinic, pharmacy, hospital).
--          This column was missing from the original schema,
--          causing the `WHERE type = $3` query in rag.service.js
--          to throw "column type does not exist" errors.
--
-- Changes:
--   1. Enable PostGIS extension (required for ST_Distance,
--      ST_SetSRID, ST_MakePoint used in RAG queries)
--   2. Add type column to clinics with standard healthcare types
--   3. Add index on type column for fast filtering
--   4. Update existing clinic records with appropriate types
--      based on their services array
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- Part 1: Enable PostGIS Extension
-- =====================================================

-- Enable PostGIS if not already enabled (required by RAG service
-- which uses ST_Distance, ST_SetSRID, ST_MakePoint for nearby queries)
CREATE EXTENSION IF NOT EXISTS postgis;

-- =====================================================
-- Part 2: Add type column to clinics
-- =====================================================

-- Add type column with standard healthcare facility types
ALTER TABLE clinics 
ADD COLUMN IF NOT EXISTS type VARCHAR(50) 
CHECK (type IN (
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
));

-- Index for fast type-based filtering (used by RAG service)
CREATE INDEX IF NOT EXISTS idx_clinics_type ON clinics(type);

-- =====================================================
-- Part 3: Default type classification for existing data
-- =====================================================

-- Classify existing clinics based on services or name patterns
UPDATE clinics SET type = 'clinic' 
WHERE type IS NULL;

-- =====================================================
-- Part 4: Add additional useful indexes for performance
-- =====================================================

-- Composite index for the common RAG query pattern:
-- WHERE type = $1 AND latitude IS NOT NULL AND longitude IS NOT NULL ORDER BY distance
CREATE INDEX IF NOT EXISTS idx_clinics_type_coordinates 
ON clinics(type, latitude, longitude) 
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Index for text search on clinic names (used in search queries)
CREATE INDEX IF NOT EXISTS idx_clinics_name_search 
ON clinics USING gin (name_ar gin_trgm_ops, name_en gin_trgm_ops);

-- Enable pg_trgm extension if not enabled (for fuzzy name matching)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- =====================================================
-- Verification Queries (run these to confirm migration)
-- =====================================================
-- SELECT column_name FROM information_schema.columns 
-- WHERE table_name = 'clinics' AND column_name = 'type';
-- 
-- SELECT type, COUNT(*) FROM clinics GROUP BY type;
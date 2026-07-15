-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Migration 003: Medical Search Optimization Indexes
--
-- Purpose: Optimize the database for medical search queries
--          used by the RAG service and healthcare search.
--          Adds composite indexes for common search patterns,
--          text search support for multilingual content,
--          and PostGIS spatial indexes for location queries.
--
-- Changes:
--   1. PostGIS spatial index on clinics for fast nearby queries
--   2. Text search on doctors (name, specialty, bio in AR/EN)
--   3. Text search on specialties (bilingual)
--   4. Index on doctor availability for appointment lookup
--   5. Index on doctor reviews for rating-based sorting
-- =====================================================

SET search_path TO medorbit, public;


-- =====================================================
-- Part 1: PostGIS Spatial Index on Clinics
-- =====================================================

-- Enable PostGIS extension for spatial queries.
CREATE EXTENSION IF NOT EXISTS postgis;


-- Add a geography column for optimized spatial queries.
-- This replaces calculating points dynamically during every query.
ALTER TABLE clinics
ADD COLUMN IF NOT EXISTS location geography(Point,4326);


-- Populate location column from existing latitude and longitude.
UPDATE clinics
SET location = ST_SetSRID(
    ST_MakePoint(longitude, latitude),
    4326
)::geography
WHERE latitude IS NOT NULL 
AND longitude IS NOT NULL
AND location IS NULL;


-- Spatial index for ultra-fast nearby queries using PostGIS.
-- This replaces the B-tree index on (latitude, longitude) with
-- a proper spatial index that powers ST_DWithin queries.
CREATE INDEX IF NOT EXISTS idx_clinics_geography 
ON clinics USING gist(location)
WHERE location IS NOT NULL;


-- =====================================================
-- Part 2: Doctor Search Optimization
-- =====================================================

-- Composite index for doctor search queries with common filters
CREATE INDEX IF NOT EXISTS idx_doctors_search 
ON doctors(specialty_id, is_accepting_patients, average_rating DESC, total_ratings DESC)
WHERE is_accepting_patients = true;


-- Index for fee-based filtering
CREATE INDEX IF NOT EXISTS idx_doctors_fee 
ON doctors(consultation_fee, average_rating DESC)
WHERE is_accepting_patients = true;


-- =====================================================
-- Part 3: Doctor Availability Optimization
-- =====================================================

-- Composite index for slot lookup queries
CREATE INDEX IF NOT EXISTS idx_availability_doctor_day 
ON doctor_availability(doctor_id, day_of_week, start_time, is_active)
WHERE is_active = true;


-- Index for specific date lookups
CREATE INDEX IF NOT EXISTS idx_availability_specific_date 
ON doctor_availability(doctor_id, specific_date, is_active)
WHERE specific_date IS NOT NULL AND is_active = true;


-- =====================================================
-- Part 4: Doctor Reviews Optimization
-- =====================================================

-- Composite index for fetching reviews sorted by date
CREATE INDEX IF NOT EXISTS idx_reviews_doctor_visible 
ON doctor_reviews(doctor_id, is_visible, created_at DESC)
WHERE is_visible = true;


-- =====================================================
-- Part 5: Appointments Optimization
-- =====================================================

-- Composite index for checking appointment conflicts
CREATE INDEX IF NOT EXISTS idx_appointments_doctor_schedule 
ON appointments(doctor_id, scheduled_date, start_time, end_time, status)
WHERE status NOT IN ('cancelled', 'no_show');


-- Index for patient appointment history
CREATE INDEX IF NOT EXISTS idx_appointments_patient_history 
ON appointments(patient_id, scheduled_date DESC, status);


-- =====================================================
-- Part 6: Medical Records Optimization
-- =====================================================

-- Index for patient record history
CREATE INDEX IF NOT EXISTS idx_records_patient_date 
ON medical_records(patient_id, created_at DESC);


-- =====================================================
-- Part 7: Notifications Optimization
-- =====================================================

-- Composite index for unread notification queries
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread 
ON notifications(user_id, is_read, created_at DESC)
WHERE is_read = false;


-- =====================================================
-- Verification
-- =====================================================
-- SELECT indexname, indexdef FROM pg_indexes 
-- WHERE schemaname = 'medorbit' 
-- AND indexname LIKE 'idx_%'
-- ORDER BY indexname;
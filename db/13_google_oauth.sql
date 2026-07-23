-- =====================================================
-- Migration 13: Google Sign-In support
-- =====================================================
SET search_path TO medorbit, public;

ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id VARCHAR(255) UNIQUE;

-- Google-created accounts authenticate via Google's own verified ID token,
-- not a local password — password_hash must become nullable to allow that.
-- Existing rows are untouched; this only relaxes the constraint going forward.
ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL;

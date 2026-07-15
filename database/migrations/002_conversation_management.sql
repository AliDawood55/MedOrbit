-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Migration 002: Conversation Management System
--
-- Purpose: Support persistent, user-linked conversations
--          with auto-generated titles, saved places, and
--          conversation-level memory.
--
-- Changes:
--   1. conversation_titles — Auto-generated or user-defined titles
--   2. saved_places — Places (clinics, hospitals, etc.) saved per conversation
--   3. Additional indexes on chatbot_conversations for user queries
--   4. Update chatbot_messages with better indexing for history retrieval
-- =====================================================

SET search_path TO medorbit, public;

-- =====================================================
-- Part 1: Conversation Titles
-- =====================================================

-- Stores auto-generated or user-defined conversation titles.
-- Auto-generated titles are created by the AI service based
-- on the first user message (extracts the main topic).
CREATE TABLE IF NOT EXISTS conversation_titles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID UNIQUE NOT NULL REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    title VARCHAR(300) NOT NULL,
    is_auto_generated BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_conv_titles_conversation 
ON conversation_titles(conversation_id);

-- =====================================================
-- Part 2: Saved Places per Conversation
-- =====================================================

-- Stores places (clinics, hospitals, pharmacies, etc.) that were
-- discussed in a conversation. This allows the chatbot to remember
-- previously found places for follow-up commands like "show route"
-- or "take me there" without re-querying the database.
CREATE TABLE IF NOT EXISTS saved_places (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    
    -- Core place info
    place_name VARCHAR(300) NOT NULL,
    place_type VARCHAR(50) NOT NULL,
    latitude DECIMAL(10, 8) NOT NULL,
    longitude DECIMAL(11, 8) NOT NULL,
    address TEXT,
    phone VARCHAR(50),
    distance_km DECIMAL(10, 2),
    rating DECIMAL(3, 2),
    
    -- Source reference (which clinic/doctor/etc. in the DB)
    reference_type VARCHAR(50),
    reference_id UUID,
    
    -- Additional metadata
    metadata JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_saved_places_conversation 
ON saved_places(conversation_id);

CREATE INDEX IF NOT EXISTS idx_saved_places_user 
ON saved_places(user_id);

-- =====================================================
-- Part 3: Additional Indexes on Existing Tables
-- =====================================================

-- Index for fast user-based conversation listing
-- (existing table already has user_id column)
CREATE INDEX IF NOT EXISTS idx_chatbot_conv_user_active 
ON chatbot_conversations(user_id, is_active, last_message_at DESC);

-- Index for message history retrieval (used by memory service)
CREATE INDEX IF NOT EXISTS idx_chatbot_messages_conv_created 
ON chatbot_messages(conversation_id, created_at ASC);

-- Index for finding messages with places metadata (used by memory service)
CREATE INDEX IF NOT EXISTS idx_chatbot_messages_metadata_places 
ON chatbot_messages USING gin (metadata) 
WHERE message_type = 'bot';

-- =====================================================
-- Part 4: User Chat Preferences
-- =====================================================

-- Stores per-user preferences for the chatbot interface
CREATE TABLE IF NOT EXISTS user_chat_preferences (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    preferred_language VARCHAR(5) DEFAULT 'auto', -- 'ar', 'en', 'auto'
    response_style VARCHAR(20) DEFAULT 'balanced', -- 'concise', 'balanced', 'detailed'
    theme VARCHAR(10) DEFAULT 'light', -- 'light', 'dark'
    model_preference VARCHAR(50) DEFAULT 'qwen2:7b',
    streaming_enabled BOOLEAN DEFAULT false,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_prefs_user 
ON user_chat_preferences(user_id);

-- =====================================================
-- Part 5: Trigger for updated_at on conversation_titles
-- =====================================================

CREATE OR REPLACE FUNCTION update_titles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'update_conv_titles_updated_at'
    ) THEN
        CREATE TRIGGER update_conv_titles_updated_at 
        BEFORE UPDATE ON conversation_titles
        FOR EACH ROW EXECUTE FUNCTION update_titles_updated_at();
    END IF;
END;
$$;

-- =====================================================
-- Verification Queries
-- =====================================================
-- SELECT table_name FROM information_schema.tables 
-- WHERE table_schema = 'medorbit' 
-- AND table_name IN ('conversation_titles', 'saved_places', 'user_chat_preferences');
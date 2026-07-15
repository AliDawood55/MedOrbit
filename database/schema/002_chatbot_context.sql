-- =====================================================
-- MEDORBIT SMART HEALTHCARE PLATFORM
-- Chatbot Context Extension
-- Version: 1.0
-- Date: 2026-07
-- =====================================================

SET search_path TO medorbit, public;

-- Table: chatbot_context
-- Stores AI conversation memory for chatbot sessions
CREATE TABLE chatbot_context (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID UNIQUE NOT NULL REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    last_intent VARCHAR(100),
    current_topic VARCHAR(100),
    entities_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    summary TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_chatbot_context_conversation ON chatbot_context(conversation_id);
CREATE INDEX idx_chatbot_context_last_intent ON chatbot_context(last_intent);
CREATE INDEX idx_chatbot_context_current_topic ON chatbot_context(current_topic);
CREATE INDEX idx_chatbot_context_entities_json ON chatbot_context USING GIN (entities_json);

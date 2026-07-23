-- =====================================================
-- Migration 14: Notification templates
-- Source: database/schema/008_update_notification_templeate.sql +
--         009_update_trigger_notification_templates.sql (Omar), rewritten
--         to target medorbit instead of public, and reusing the existing
--         generic update_updated_at_column() trigger function from
--         db/04_triggers_sequences.sql instead of duplicating a
--         near-identical one-off function.
-- =====================================================
SET search_path TO medorbit, public;

CREATE TABLE IF NOT EXISTS notification_templates (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL UNIQUE,
    type VARCHAR(50) NOT NULL,
    subject_en VARCHAR(255) NOT NULL,
    subject_ar VARCHAR(255),
    body_html TEXT NOT NULL,
    body_text TEXT,
    variables JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_notification_templates_type ON notification_templates(type);
CREATE INDEX IF NOT EXISTS idx_notification_templates_active ON notification_templates(is_active);

DROP TRIGGER IF EXISTS notification_templates_updated_at ON notification_templates;
CREATE TRIGGER notification_templates_updated_at
BEFORE UPDATE ON notification_templates
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

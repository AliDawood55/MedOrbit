-- =====================================================
-- Migration 15: Appointment status history
-- Source: database/schema/010_appointment_status_history_table.sql (Omar),
--         rewritten to target medorbit instead of public.
-- =====================================================
SET search_path TO medorbit, public;

CREATE TABLE IF NOT EXISTS appointment_status_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    appointment_id UUID NOT NULL,
    old_status VARCHAR(50),
    new_status VARCHAR(50) NOT NULL,
    changed_by UUID,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_status_history_appointment
        FOREIGN KEY (appointment_id)
        REFERENCES appointments(id)
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_appointment_status_history_appointment ON appointment_status_history(appointment_id);

-- Canonical-schema backfill, slice 3: administration and notifications.
-- Extracted from the protected canonical PostgreSQL schema on 2026-08-24.

CREATE TABLE IF NOT EXISTS medorbit.notification_templates (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  name character varying(100) NOT NULL,
  type character varying(50) NOT NULL,
  subject_en character varying(255) NOT NULL,
  subject_ar character varying(255),
  body_html text NOT NULL,
  body_text text,
  variables jsonb DEFAULT '{}'::jsonb,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT notification_templates_pkey PRIMARY KEY (id),
  CONSTRAINT notification_templates_name_key UNIQUE (name)
);

CREATE TABLE IF NOT EXISTS medorbit.notifications (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid NOT NULL,
  title_ar character varying(200) NOT NULL,
  title_en character varying(200) NOT NULL,
  message_ar text NOT NULL,
  message_en text NOT NULL,
  notification_type character varying(50) NOT NULL,
  reference_id uuid,
  reference_type character varying(50),
  channel character varying(20) DEFAULT 'in_app'::character varying,
  is_read boolean DEFAULT false,
  read_at timestamp with time zone,
  email_sent_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT notifications_pkey PRIMARY KEY (id),
  CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.system_settings (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  setting_key character varying(100) NOT NULL,
  setting_value jsonb NOT NULL,
  description text,
  is_public boolean DEFAULT false,
  requires_restart boolean DEFAULT false,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  updated_by uuid,
  CONSTRAINT system_settings_pkey PRIMARY KEY (id),
  CONSTRAINT system_settings_setting_key_key UNIQUE (setting_key),
  CONSTRAINT system_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES medorbit.users(id)
);

CREATE TABLE IF NOT EXISTS medorbit.feedback (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid NOT NULL,
  overall_rating smallint NOT NULL,
  category_chatbot smallint,
  category_clinics smallint,
  category_booking smallint,
  category_design smallint,
  comment text,
  would_recommend boolean,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT feedback_pkey PRIMARY KEY (id),
  CONSTRAINT feedback_category_booking_check CHECK (category_booking >= 0 AND category_booking <= 5),
  CONSTRAINT feedback_category_chatbot_check CHECK (category_chatbot >= 0 AND category_chatbot <= 5),
  CONSTRAINT feedback_category_clinics_check CHECK (category_clinics >= 0 AND category_clinics <= 5),
  CONSTRAINT feedback_category_design_check CHECK (category_design >= 0 AND category_design <= 5),
  CONSTRAINT feedback_overall_rating_check CHECK (overall_rating >= 1 AND overall_rating <= 5),
  CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_notification_templates_active ON medorbit.notification_templates (is_active);
CREATE INDEX IF NOT EXISTS idx_notification_templates_type ON medorbit.notification_templates (type);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON medorbit.notifications (user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON medorbit.notifications (user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread ON medorbit.notifications (user_id, is_read, created_at DESC) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_feedback_created ON medorbit.feedback (created_at);
CREATE INDEX IF NOT EXISTS idx_feedback_user ON medorbit.feedback (user_id);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='notification_templates_updated_at' AND tgrelid='medorbit.notification_templates'::regclass) THEN
    CREATE TRIGGER notification_templates_updated_at BEFORE UPDATE ON medorbit.notification_templates FOR EACH ROW EXECUTE FUNCTION medorbit.update_updated_at_column();
  END IF;
END
$$;

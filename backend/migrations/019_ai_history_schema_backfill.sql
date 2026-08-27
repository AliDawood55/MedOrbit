-- Canonical-schema backfill, slice 4: AI conversation history and reports.
-- Extracted from the protected canonical PostgreSQL schema on 2026-08-24.

CREATE TABLE IF NOT EXISTS medorbit.chatbot_conversations (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  session_id character varying(100) NOT NULL,
  user_id uuid,
  language character varying(5) DEFAULT 'ar'::character varying,
  platform character varying(20) DEFAULT 'web'::character varying,
  is_active boolean DEFAULT true,
  last_message_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  started_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  ended_at timestamp with time zone,
  CONSTRAINT chatbot_conversations_pkey PRIMARY KEY (id),
  CONSTRAINT chatbot_conversations_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id)
);

CREATE TABLE IF NOT EXISTS medorbit.chatbot_context (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  conversation_id uuid NOT NULL,
  last_intent character varying(100),
  current_topic character varying(100),
  entities_json jsonb DEFAULT '{}'::jsonb NOT NULL,
  summary text,
  updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chatbot_context_pkey PRIMARY KEY (id),
  CONSTRAINT chatbot_context_conversation_id_key UNIQUE (conversation_id),
  CONSTRAINT chatbot_context_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES medorbit.chatbot_conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.chatbot_messages (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  conversation_id uuid NOT NULL,
  message_text text NOT NULL,
  message_type character varying(20) DEFAULT 'user'::character varying,
  intent character varying(100),
  confidence_score numeric(5,4),
  response_text text,
  metadata jsonb,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT chatbot_messages_pkey PRIMARY KEY (id),
  CONSTRAINT chatbot_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES medorbit.chatbot_conversations(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.saved_places (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  conversation_id uuid NOT NULL,
  user_id uuid,
  place_name character varying(300) NOT NULL,
  place_type character varying(50) NOT NULL,
  latitude numeric(10,8) NOT NULL,
  longitude numeric(11,8) NOT NULL,
  address text,
  phone character varying(50),
  distance_km numeric(10,2),
  rating numeric(3,2),
  reference_type character varying(50),
  reference_id uuid,
  metadata jsonb DEFAULT '{}'::jsonb,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT saved_places_pkey PRIMARY KEY (id),
  CONSTRAINT saved_places_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES medorbit.chatbot_conversations(id) ON DELETE CASCADE,
  CONSTRAINT saved_places_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS medorbit.report_summarizations (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  record_id uuid,
  user_id uuid,
  source_file_name character varying(500),
  source_file_type character varying(50),
  extracted_text text,
  summary_ar text NOT NULL,
  summary_en text NOT NULL,
  processing_time_ms integer,
  model_used character varying(100) DEFAULT 'qwen2:7b'::character varying,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT report_summarizations_pkey PRIMARY KEY (id),
  CONSTRAINT report_summarizations_record_id_fkey FOREIGN KEY (record_id) REFERENCES medorbit.medical_records(id) ON DELETE SET NULL,
  CONSTRAINT report_summarizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE SET NULL
);

COMMENT ON TABLE medorbit.chatbot_conversations IS 'Chatbot conversation sessions';
COMMENT ON TABLE medorbit.chatbot_messages IS 'Individual chatbot messages';

CREATE INDEX IF NOT EXISTS idx_chatbot_context_conversation ON medorbit.chatbot_context (conversation_id);
CREATE INDEX IF NOT EXISTS idx_chatbot_context_current_topic ON medorbit.chatbot_context (current_topic);
CREATE INDEX IF NOT EXISTS idx_chatbot_context_entities_json ON medorbit.chatbot_context USING gin (entities_json);
CREATE INDEX IF NOT EXISTS idx_chatbot_context_last_intent ON medorbit.chatbot_context (last_intent);
CREATE INDEX IF NOT EXISTS idx_chatbot_conv_user_active ON medorbit.chatbot_conversations (user_id, is_active, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_chatbot_messages_conv_created ON medorbit.chatbot_messages (conversation_id, created_at);
CREATE INDEX IF NOT EXISTS idx_chatbot_messages_metadata_places ON medorbit.chatbot_messages USING gin (metadata) WHERE message_type = 'bot';
CREATE INDEX IF NOT EXISTS idx_conversations_session ON medorbit.chatbot_conversations (session_id);
CREATE INDEX IF NOT EXISTS idx_conversations_user ON medorbit.chatbot_conversations (user_id);
CREATE INDEX IF NOT EXISTS idx_messages_conversation ON medorbit.chatbot_messages (conversation_id);
CREATE INDEX IF NOT EXISTS idx_rsum_record ON medorbit.report_summarizations (record_id);
CREATE INDEX IF NOT EXISTS idx_rsum_user ON medorbit.report_summarizations (user_id);
CREATE INDEX IF NOT EXISTS idx_saved_places_conversation ON medorbit.saved_places (conversation_id);
CREATE INDEX IF NOT EXISTS idx_saved_places_user ON medorbit.saved_places (user_id);

-- Canonical-schema backfill, slice 5: account recovery and contact support.
-- Extracted from the protected canonical PostgreSQL schema on 2026-08-24.

CREATE TABLE IF NOT EXISTS medorbit.email_verification_tokens (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid NOT NULL,
  token_hash character varying(255) NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  verified_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT email_verification_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT email_verification_tokens_token_hash_key UNIQUE (token_hash),
  CONSTRAINT email_verification_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.password_reset_tokens (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid NOT NULL,
  token_hash character varying(255) NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  used_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
  CONSTRAINT password_reset_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT password_reset_tokens_token_hash_key UNIQUE (token_hash),
  CONSTRAINT password_reset_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS medorbit.contact_messages (
  id uuid DEFAULT public.uuid_generate_v4() NOT NULL,
  user_id uuid,
  sender_name character varying(120),
  sender_email character varying(320),
  subject character varying(160) NOT NULL,
  message text NOT NULL,
  status character varying(16) DEFAULT 'new'::character varying NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  read_at timestamp with time zone,
  resolved_at timestamp with time zone,
  resolved_by uuid,
  CONSTRAINT contact_messages_pkey PRIMARY KEY (id),
  CONSTRAINT contact_messages_body_length CHECK (length(TRIM(BOTH FROM message)) >= 1 AND length(TRIM(BOTH FROM message)) <= 4000),
  CONSTRAINT contact_messages_resolved_state CHECK (status = 'resolved' OR (resolved_at IS NULL AND resolved_by IS NULL)),
  CONSTRAINT contact_messages_sender_email_length CHECK (sender_email IS NULL OR (length(TRIM(BOTH FROM sender_email)) >= 3 AND length(TRIM(BOTH FROM sender_email)) <= 320)),
  CONSTRAINT contact_messages_sender_identity CHECK (user_id IS NOT NULL OR (sender_name IS NOT NULL AND sender_email IS NOT NULL)),
  CONSTRAINT contact_messages_sender_name_length CHECK (sender_name IS NULL OR (length(TRIM(BOTH FROM sender_name)) >= 1 AND length(TRIM(BOTH FROM sender_name)) <= 120)),
  CONSTRAINT contact_messages_status_check CHECK (status = ANY (ARRAY['new'::character varying, 'read'::character varying, 'resolved'::character varying])),
  CONSTRAINT contact_messages_subject_length CHECK (length(TRIM(BOTH FROM subject)) >= 1 AND length(TRIM(BOTH FROM subject)) <= 160),
  CONSTRAINT contact_messages_resolved_by_fkey FOREIGN KEY (resolved_by) REFERENCES medorbit.users(id),
  CONSTRAINT contact_messages_user_id_fkey FOREIGN KEY (user_id) REFERENCES medorbit.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS contact_messages_status_created ON medorbit.contact_messages (status, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS contact_messages_user_created ON medorbit.contact_messages (user_id, created_at DESC) WHERE user_id IS NOT NULL;

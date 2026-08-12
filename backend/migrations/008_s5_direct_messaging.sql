CREATE TABLE medorbit.direct_conversations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  relationship_id UUID NOT NULL REFERENCES medorbit.doctor_patient_relationships(id),
  appointment_id UUID REFERENCES medorbit.appointments(id),
  status VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_message_at TIMESTAMPTZ,
  CONSTRAINT direct_conversations_status_check CHECK (status IN ('active','closed'))
);

CREATE UNIQUE INDEX direct_conversations_one_active_relationship
  ON medorbit.direct_conversations(relationship_id)
  WHERE status='active';

CREATE INDEX direct_conversations_last_message
  ON medorbit.direct_conversations(last_message_at DESC NULLS LAST,created_at DESC,id DESC);

CREATE TABLE medorbit.conversation_members (
  conversation_id UUID NOT NULL REFERENCES medorbit.direct_conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  member_role VARCHAR(16) NOT NULL,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  left_at TIMESTAMPTZ,
  last_read_message_id UUID,
  last_read_at TIMESTAMPTZ,
  PRIMARY KEY (conversation_id,user_id),
  CONSTRAINT conversation_members_role_check CHECK (member_role IN ('patient','doctor'))
);

CREATE INDEX conversation_members_user_active
  ON medorbit.conversation_members(user_id,conversation_id) WHERE left_at IS NULL;

CREATE TABLE medorbit.direct_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES medorbit.direct_conversations(id) ON DELETE CASCADE,
  sender_user_id UUID NOT NULL REFERENCES medorbit.users(id),
  client_message_id UUID NOT NULL,
  body TEXT NOT NULL,
  message_type VARCHAR(16) NOT NULL DEFAULT 'text',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  edited_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  CONSTRAINT direct_messages_body_length CHECK (length(trim(body)) BETWEEN 1 AND 4000),
  CONSTRAINT direct_messages_type_check CHECK (message_type='text'),
  CONSTRAINT direct_messages_sender_client_unique UNIQUE(conversation_id,sender_user_id,client_message_id),
  CONSTRAINT direct_messages_conversation_id_unique UNIQUE(conversation_id,id)
);

CREATE INDEX direct_messages_history
  ON medorbit.direct_messages(conversation_id,created_at DESC,id DESC) WHERE deleted_at IS NULL;

ALTER TABLE medorbit.conversation_members
  ADD CONSTRAINT conversation_members_last_read_fk
  FOREIGN KEY(conversation_id,last_read_message_id)
  REFERENCES medorbit.direct_messages(conversation_id,id);

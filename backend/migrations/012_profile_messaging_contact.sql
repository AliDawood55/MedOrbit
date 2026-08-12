-- Doctor Profile 2.0, privacy-safe patient social profiles, generalized
-- text messaging, and the persisted Contact Us inbox. Migration 009 and its
-- historical video_consultations table intentionally remain untouched.

ALTER TABLE medorbit.doctors
  ADD COLUMN professional_headline VARCHAR(160),
  ADD COLUMN areas_of_expertise TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN professional_interests TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN languages_spoken TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

ALTER TABLE medorbit.doctors
  ADD CONSTRAINT doctors_professional_headline_length
    CHECK (professional_headline IS NULL OR length(trim(professional_headline)) BETWEEN 1 AND 160),
  ADD CONSTRAINT doctors_expertise_count
    CHECK (cardinality(areas_of_expertise) <= 12),
  ADD CONSTRAINT doctors_expertise_total_length
    CHECK (length(array_to_string(areas_of_expertise, '')) <= 960),
  ADD CONSTRAINT doctors_interests_count
    CHECK (cardinality(professional_interests) <= 10),
  ADD CONSTRAINT doctors_interests_total_length
    CHECK (length(array_to_string(professional_interests, '')) <= 800),
  ADD CONSTRAINT doctors_languages_count
    CHECK (cardinality(languages_spoken) <= 10),
  ADD CONSTRAINT doctors_languages_total_length
    CHECK (length(array_to_string(languages_spoken, '')) <= 800);

ALTER TABLE medorbit.user_profiles
  ADD COLUMN public_profile_id UUID DEFAULT uuid_generate_v4(),
  ADD COLUMN social_bio TEXT,
  ADD COLUMN allow_doctor_messages BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE medorbit.user_profiles
SET public_profile_id=uuid_generate_v4()
WHERE public_profile_id IS NULL;

ALTER TABLE medorbit.user_profiles
  ALTER COLUMN public_profile_id SET NOT NULL,
  ADD CONSTRAINT user_profiles_public_profile_id_unique UNIQUE(public_profile_id),
  ADD CONSTRAINT user_profiles_social_bio_length
    CHECK (social_bio IS NULL OR length(trim(social_bio)) BETWEEN 1 AND 500);

ALTER TABLE medorbit.direct_conversations
  ALTER COLUMN relationship_id DROP NOT NULL,
  ADD COLUMN participant_pair_key VARCHAR(73),
  ADD COLUMN conversation_type VARCHAR(24) NOT NULL DEFAULT 'patient_doctor',
  ADD COLUMN initiated_by_user_id UUID REFERENCES medorbit.users(id),
  ADD COLUMN request_status VARCHAR(16) NOT NULL DEFAULT 'accepted',
  ADD COLUMN request_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ADD COLUMN declined_at TIMESTAMPTZ;

UPDATE medorbit.direct_conversations c
SET participant_pair_key = members.pair_key
FROM (
  SELECT conversation_id,
         string_agg(user_id::text, ':' ORDER BY user_id::text) AS pair_key,
         count(*) AS member_count
  FROM medorbit.conversation_members
  WHERE left_at IS NULL
  GROUP BY conversation_id
) members
WHERE members.conversation_id=c.id
  AND members.member_count=2;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM medorbit.direct_conversations
    WHERE participant_pair_key IS NULL OR length(participant_pair_key) <> 73
  ) THEN
    RAISE EXCEPTION 'Cannot backfill direct conversation participant pairs safely';
  END IF;
END $$;

ALTER TABLE medorbit.direct_conversations
  ALTER COLUMN participant_pair_key SET NOT NULL,
  ADD CONSTRAINT direct_conversations_pair_key_length
    CHECK (length(participant_pair_key)=73),
  ADD CONSTRAINT direct_conversations_type_check
    CHECK (conversation_type IN ('patient_doctor','doctor_doctor')),
  ADD CONSTRAINT direct_conversations_request_status_check
    CHECK (request_status IN ('pending','accepted','declined','cancelled')),
  ADD CONSTRAINT direct_conversations_declined_at_check
    CHECK (request_status='declined' OR declined_at IS NULL);

CREATE UNIQUE INDEX direct_conversations_one_open_pair
  ON medorbit.direct_conversations(participant_pair_key)
  WHERE status='active' AND request_status IN ('pending','accepted');

CREATE INDEX direct_conversations_initiator_requests
  ON medorbit.direct_conversations(initiated_by_user_id,created_at DESC)
  WHERE request_status='pending';

CREATE TABLE medorbit.contact_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES medorbit.users(id) ON DELETE SET NULL,
  sender_name VARCHAR(120),
  sender_email VARCHAR(320),
  subject VARCHAR(160) NOT NULL,
  message TEXT NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'new',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES medorbit.users(id),
  CONSTRAINT contact_messages_subject_length
    CHECK (length(trim(subject)) BETWEEN 1 AND 160),
  CONSTRAINT contact_messages_body_length
    CHECK (length(trim(message)) BETWEEN 1 AND 4000),
  CONSTRAINT contact_messages_sender_name_length
    CHECK (sender_name IS NULL OR length(trim(sender_name)) BETWEEN 1 AND 120),
  CONSTRAINT contact_messages_sender_email_length
    CHECK (sender_email IS NULL OR length(trim(sender_email)) BETWEEN 3 AND 320),
  CONSTRAINT contact_messages_sender_identity
    CHECK (user_id IS NOT NULL OR (sender_name IS NOT NULL AND sender_email IS NOT NULL)),
  CONSTRAINT contact_messages_status_check
    CHECK (status IN ('new','read','resolved')),
  CONSTRAINT contact_messages_resolved_state
    CHECK (status='resolved' OR (resolved_at IS NULL AND resolved_by IS NULL))
);

CREATE INDEX contact_messages_status_created
  ON medorbit.contact_messages(status,created_at DESC,id DESC);

CREATE INDEX contact_messages_user_created
  ON medorbit.contact_messages(user_id,created_at DESC)
  WHERE user_id IS NOT NULL;

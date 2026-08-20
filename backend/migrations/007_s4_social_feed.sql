ALTER TABLE medorbit.doctor_posts
  ADD COLUMN IF NOT EXISTS status VARCHAR(16),
  ADD COLUMN IF NOT EXISTS moderation_status VARCHAR(16),
  ADD COLUMN IF NOT EXISTS published_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

ALTER TABLE medorbit.doctor_posts DROP CONSTRAINT IF EXISTS chk_doctor_posts_title;
ALTER TABLE medorbit.doctor_posts DROP CONSTRAINT IF EXISTS doctor_posts_status_check;
ALTER TABLE medorbit.doctor_posts DROP CONSTRAINT IF EXISTS doctor_posts_moderation_status_check;

UPDATE medorbit.doctor_posts
SET status = CASE WHEN is_published THEN 'published' ELSE 'draft' END,
    moderation_status = CASE WHEN is_published THEN 'approved' ELSE 'pending' END,
    published_at = CASE WHEN is_published THEN COALESCE(published_at, created_at, NOW()) ELSE NULL END
WHERE status IS NULL OR moderation_status IS NULL;

ALTER TABLE medorbit.doctor_posts
  ALTER COLUMN status SET DEFAULT 'draft',
  ALTER COLUMN status SET NOT NULL,
  ALTER COLUMN moderation_status SET DEFAULT 'pending',
  ALTER COLUMN moderation_status SET NOT NULL;

ALTER TABLE medorbit.doctor_posts
  ADD CONSTRAINT doctor_posts_status_check CHECK (status IN ('draft','published')),
  ADD CONSTRAINT doctor_posts_moderation_status_check
    CHECK (moderation_status IN ('pending','approved','rejected','hidden'));

CREATE INDEX IF NOT EXISTS doctor_posts_public_feed
  ON medorbit.doctor_posts (published_at DESC, id DESC)
  WHERE status='published' AND moderation_status='approved' AND deleted_at IS NULL;

CREATE TABLE medorbit.post_likes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES medorbit.doctor_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT post_likes_post_user_unique UNIQUE (post_id,user_id)
);

CREATE INDEX post_likes_user_created ON medorbit.post_likes(user_id,created_at DESC);

CREATE TABLE medorbit.post_comments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES medorbit.doctor_posts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  moderation_status VARCHAR(16) NOT NULL DEFAULT 'approved',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT post_comments_body_length CHECK (length(trim(body)) BETWEEN 1 AND 1000),
  CONSTRAINT post_comments_moderation_status_check
    CHECK (moderation_status IN ('approved','hidden','rejected'))
);

CREATE INDEX post_comments_public ON medorbit.post_comments(post_id,created_at,id)
  WHERE moderation_status='approved' AND deleted_at IS NULL;

CREATE TABLE medorbit.user_follows (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  doctor_id UUID NOT NULL REFERENCES medorbit.doctors(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_follows_user_doctor_unique UNIQUE(user_id,doctor_id)
);

CREATE INDEX user_follows_doctor_created ON medorbit.user_follows(doctor_id,created_at DESC);

CREATE TABLE medorbit.user_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES medorbit.users(id) ON DELETE SET NULL,
  event_type VARCHAR(64) NOT NULL,
  entity_type VARCHAR(32) NOT NULL,
  entity_id UUID,
  event_version SMALLINT NOT NULL DEFAULT 1,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  dedupe_key VARCHAR(255),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_events_metadata_object CHECK (jsonb_typeof(metadata)='object'),
  CONSTRAINT user_events_dedupe_unique UNIQUE(dedupe_key)
);

CREATE INDEX user_events_user_time ON medorbit.user_events(user_id,occurred_at DESC);
CREATE INDEX user_events_type_time ON medorbit.user_events(event_type,occurred_at DESC);

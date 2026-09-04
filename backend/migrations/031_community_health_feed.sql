-- The original feed stored only doctor-authored posts.  Community posts use
-- the same moderation and engagement tables, while retaining the doctor_id
-- for existing professional posts and their recommendation data.
ALTER TABLE medorbit.doctor_posts
  ADD COLUMN IF NOT EXISTS author_user_id uuid REFERENCES medorbit.users(id) ON DELETE CASCADE;

ALTER TABLE medorbit.doctor_posts
  ALTER COLUMN doctor_id DROP NOT NULL;

UPDATE medorbit.doctor_posts p
SET author_user_id = d.user_id
FROM medorbit.doctors d
WHERE p.doctor_id = d.id AND p.author_user_id IS NULL;

ALTER TABLE medorbit.doctor_posts
  DROP CONSTRAINT IF EXISTS doctor_posts_author_check;

ALTER TABLE medorbit.doctor_posts
  ADD CONSTRAINT doctor_posts_author_check
  CHECK (doctor_id IS NOT NULL OR author_user_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS doctor_posts_community_author_feed
  ON medorbit.doctor_posts (author_user_id, published_at DESC, id DESC)
  WHERE status='published' AND moderation_status='approved' AND deleted_at IS NULL;

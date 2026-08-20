CREATE TABLE medorbit.user_interest_profiles (
  user_id UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  interest_type VARCHAR(32) NOT NULL,
  interest_key VARCHAR(128) NOT NULL,
  score NUMERIC(8,2) NOT NULL DEFAULT 0,
  interaction_count INTEGER NOT NULL DEFAULT 0,
  last_interaction_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, interest_type, interest_key),
  CONSTRAINT user_interest_profiles_type_check
    CHECK (interest_type IN ('specialty','post_category')),
  CONSTRAINT user_interest_profiles_key_check
    CHECK (length(trim(interest_key)) BETWEEN 1 AND 128),
  CONSTRAINT user_interest_profiles_score_check
    CHECK (score BETWEEN 0 AND 100),
  CONSTRAINT user_interest_profiles_count_check
    CHECK (interaction_count >= 0)
);

CREATE INDEX user_interest_profiles_user_score
  ON medorbit.user_interest_profiles(user_id, score DESC, last_interaction_at DESC);

CREATE INDEX user_interest_profiles_dimension
  ON medorbit.user_interest_profiles(interest_type, interest_key, score DESC);

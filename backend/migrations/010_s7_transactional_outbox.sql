CREATE TABLE medorbit.outbox_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  aggregate_type VARCHAR(100) NOT NULL,
  aggregate_id UUID,
  event_type VARCHAR(150) NOT NULL,
  event_version INTEGER NOT NULL DEFAULT 1,
  payload JSONB NOT NULL,
  headers JSONB NOT NULL DEFAULT '{}'::jsonb,
  kafka_topic VARCHAR(200) NOT NULL,
  partition_key VARCHAR(200),
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_at TIMESTAMPTZ,
  locked_by TEXT,
  published_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT outbox_events_status_check
    CHECK (status IN ('pending','publishing','published','failed','dead')),
  CONSTRAINT outbox_events_attempt_count_check CHECK (attempt_count >= 0),
  CONSTRAINT outbox_events_event_version_check CHECK (event_version > 0),
  CONSTRAINT outbox_events_publish_state_check CHECK (
    (status='published' AND published_at IS NOT NULL)
    OR status<>'published'
  )
);

CREATE INDEX outbox_events_polling
  ON medorbit.outbox_events(status, available_at, created_at)
  WHERE status IN ('pending','failed','publishing');

CREATE TABLE medorbit.processed_events (
  consumer_name VARCHAR(150) NOT NULL,
  event_id UUID NOT NULL,
  event_type VARCHAR(150) NOT NULL,
  event_version INTEGER NOT NULL,
  processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (consumer_name, event_id),
  CONSTRAINT processed_events_event_version_check CHECK (event_version > 0)
);

CREATE INDEX processed_events_processed_at
  ON medorbit.processed_events(processed_at);

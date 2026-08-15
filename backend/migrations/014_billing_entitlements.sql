-- =====================================================================
-- Billing, subscriptions and AI usage entitlements — provider-independent.
--
-- Deliberately contains NO payment-provider specifics and NO medical data.
-- Provider linkage is limited to two opaque string columns per table
-- (provider + provider_*_id) so a provider can be chosen later without a
-- schema rewrite, and so nothing here needs to know what a card is.
--
-- The separation is a hard rule, not a style preference: rows in these
-- tables reference a consultation only by its opaque session identifier.
-- No symptom, transcript, diagnosis, urgency or report content is copied
-- into billing. Billing answers "may this user run this feature", never
-- "what was wrong with this patient".
-- =====================================================================

-- ---------------------------------------------------------------------
-- Plan catalogue — the backend source of truth for price.
--
-- plan_code is identity; price is data. Nothing outside this table may
-- define what a plan costs, and no client is ever trusted to send an
-- amount (it sends a plan_code, which is resolved here).
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.subscription_plans (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  plan_code         VARCHAR(40)  NOT NULL UNIQUE,
  name_en           VARCHAR(80)  NOT NULL,
  name_ar           VARCHAR(80)  NOT NULL,
  -- Integer minor units. Money is never stored as floating point.
  price_cents       INTEGER      NOT NULL,
  currency          CHAR(3)      NOT NULL DEFAULT 'USD',
  billing_interval  VARCHAR(10)  NOT NULL,
  interval_count    SMALLINT     NOT NULL DEFAULT 1,
  grants_pro        BOOLEAN      NOT NULL DEFAULT false,
  is_active         BOOLEAN      NOT NULL DEFAULT true,
  sort_order        SMALLINT     NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT subscription_plans_price_check
    CHECK (price_cents >= 0),
  CONSTRAINT subscription_plans_interval_check
    CHECK (billing_interval IN ('none', 'month', 'year')),
  CONSTRAINT subscription_plans_interval_count_check
    CHECK (interval_count >= 1),
  -- A free plan must be free, and a paid plan must have a real interval.
  CONSTRAINT subscription_plans_free_shape_check
    CHECK (
      (billing_interval = 'none' AND price_cents = 0 AND grants_pro = false)
      OR (billing_interval <> 'none' AND price_cents > 0)
    )
);

-- ---------------------------------------------------------------------
-- Billing identity for a user.
--
-- billing_reference is the opaque handle we send to a payment provider
-- instead of an email address or a patient name, so provider-side records
-- carry no MedOrbit identity beyond a meaningless token.
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.billing_customers (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id              UUID NOT NULL UNIQUE REFERENCES medorbit.users(id) ON DELETE CASCADE,
  billing_reference    VARCHAR(64) NOT NULL UNIQUE,
  provider             VARCHAR(32),
  provider_customer_id VARCHAR(128),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- A provider customer id is meaningless without knowing which provider.
  CONSTRAINT billing_customers_provider_pairing_check
    CHECK (num_nonnulls(provider, provider_customer_id) <> 1)
);

-- One customer record per provider identity; blocks a second local user
-- silently attaching to someone else's provider customer.
CREATE UNIQUE INDEX billing_customers_provider_identity_unique
  ON medorbit.billing_customers (provider, provider_customer_id)
  WHERE provider IS NOT NULL;

-- ---------------------------------------------------------------------
-- Subscriptions.
--
-- Entitlement belongs to user_id, never to role. A patient, doctor, admin
-- and super_admin all resolve entitlement through this one table.
--
-- cancel_at_period_end is modelled as a flag on a still-active row rather
-- than as a status, because that is what it actually is: auto-renew is off
-- but paid access continues to current_period_end. Treating it as a status
-- would lose the distinction between "canceling" and "already lost access".
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.subscriptions (
  id                       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id                  UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  plan_id                  UUID NOT NULL REFERENCES medorbit.subscription_plans(id),
  status                   VARCHAR(24) NOT NULL,
  cancel_at_period_end     BOOLEAN NOT NULL DEFAULT false,
  current_period_start     TIMESTAMPTZ,
  current_period_end       TIMESTAMPTZ,
  -- Set when a renewal payment fails. While NOW() < this instant the user
  -- keeps Pro (product-owner decision: a transient card failure must not
  -- interrupt a consultation). Past it, entitlement drops to free.
  grace_period_ends_at     TIMESTAMPTZ,
  canceled_at              TIMESTAMPTZ,
  ended_at                 TIMESTAMPTZ,
  provider                 VARCHAR(32),
  provider_subscription_id VARCHAR(128),
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT subscriptions_status_check
    CHECK (status IN ('incomplete', 'active', 'past_due', 'canceled', 'expired')),
  CONSTRAINT subscriptions_period_order_check
    CHECK (current_period_end IS NULL
           OR current_period_start IS NULL
           OR current_period_end > current_period_start),
  CONSTRAINT subscriptions_provider_pairing_check
    CHECK (num_nonnulls(provider, provider_subscription_id) <> 1),
  -- Terminal states must record when access actually ended, so entitlement
  -- history stays reconstructible during reconciliation.
  CONSTRAINT subscriptions_terminal_shape_check
    CHECK (status NOT IN ('canceled', 'expired') OR ended_at IS NOT NULL)
);

-- At most one live subscription per user. This is the structural defence
-- against a duplicate webhook or a double checkout granting two overlapping
-- Pro subscriptions to the same account.
CREATE UNIQUE INDEX subscriptions_one_live_per_user_unique
  ON medorbit.subscriptions (user_id)
  WHERE status IN ('incomplete', 'active', 'past_due');

CREATE UNIQUE INDEX subscriptions_provider_identity_unique
  ON medorbit.subscriptions (provider, provider_subscription_id)
  WHERE provider IS NOT NULL;

-- The hot path: "what is this user entitled to right now".
CREATE INDEX subscriptions_entitlement_lookup
  ON medorbit.subscriptions (user_id, status, current_period_end);

-- ---------------------------------------------------------------------
-- Provider webhook events — idempotency, replay resistance, audit.
--
-- Deliberately stores a digest rather than the raw provider payload.
-- A payload can carry cardholder-adjacent and personal data we have no
-- reason to retain; the digest still proves "we saw exactly this event"
-- for reconciliation without becoming a second copy of it.
-- redacted_payload is available for the cases where recovery genuinely
-- needs the fields, and is expected to be written already-filtered.
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.billing_events (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  provider          VARCHAR(32) NOT NULL,
  provider_event_id VARCHAR(191) NOT NULL,
  event_type        VARCHAR(80) NOT NULL,
  -- Provider's own emission time, when supplied: lets us detect and tolerate
  -- out-of-order delivery instead of applying a stale state change.
  event_created_at  TIMESTAMPTZ,
  received_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at      TIMESTAMPTZ,
  processing_status VARCHAR(16) NOT NULL DEFAULT 'received',
  attempts          SMALLINT NOT NULL DEFAULT 0,
  last_error        TEXT,
  payload_digest    CHAR(64),
  redacted_payload  JSONB,
  subscription_id   UUID REFERENCES medorbit.subscriptions(id) ON DELETE SET NULL,
  CONSTRAINT billing_events_processing_status_check
    CHECK (processing_status IN ('received', 'processed', 'failed', 'ignored')),
  CONSTRAINT billing_events_processed_shape_check
    CHECK (processing_status <> 'processed' OR processed_at IS NOT NULL)
);

-- The replay/idempotency guarantee: a provider event is recorded at most
-- once, enforced by the database rather than by application memory.
CREATE UNIQUE INDEX billing_events_provider_event_unique
  ON medorbit.billing_events (provider, provider_event_id);

CREATE INDEX billing_events_unprocessed
  ON medorbit.billing_events (received_at)
  WHERE processing_status IN ('received', 'failed');

-- ---------------------------------------------------------------------
-- Metered usage windows (currently: free chatbot messages).
--
-- Fixed window anchored at first use rather than aligned to midnight UTC:
-- a calendar-aligned window would hand a user who first writes at 23:50 UTC
-- a ten-minute allowance. Anchoring at first use gives every user the same
-- full 24 hours and a stable resets_at to count down to.
--
-- reserved_count and consumed_count are separate so an in-flight AI request
-- holds quota (blocking concurrent overspend) without permanently burning it
-- if the AI call then fails.
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.usage_windows (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  feature_code   VARCHAR(40) NOT NULL,
  window_start   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  window_end     TIMESTAMPTZ NOT NULL,
  reserved_count INTEGER NOT NULL DEFAULT 0,
  consumed_count INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT usage_windows_order_check   CHECK (window_end > window_start),
  CONSTRAINT usage_windows_counts_check  CHECK (reserved_count >= 0 AND consumed_count >= 0)
);

CREATE UNIQUE INDEX usage_windows_user_feature_start_unique
  ON medorbit.usage_windows (user_id, feature_code, window_start);

-- Finds the caller's current window in one index hit.
CREATE INDEX usage_windows_current_lookup
  ON medorbit.usage_windows (user_id, feature_code, window_end DESC);

-- ---------------------------------------------------------------------
-- Usage ledger — one row per logical billable unit.
--
-- Exists chiefly to make idempotency a database guarantee. The unique index
-- below is what stops a double-click, an Enter-mash, or a client retry after
-- a timeout from consuming quota twice: the second insert simply loses.
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.usage_ledger (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  feature_code       VARCHAR(40) NOT NULL,
  window_id          UUID REFERENCES medorbit.usage_windows(id) ON DELETE SET NULL,
  -- Client-supplied idempotency key. Nullable so pre-existing callers that
  -- do not yet send one keep working (they simply get no dedupe).
  client_request_id  VARCHAR(64),
  status             VARCHAR(16) NOT NULL DEFAULT 'reserved',
  -- Which entitlement paid for this unit, for later reconciliation.
  entitlement_source VARCHAR(10) NOT NULL DEFAULT 'free',
  -- Opaque pointer to the conversation. Never the message text.
  reference_id       UUID,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  settled_at         TIMESTAMPTZ,
  CONSTRAINT usage_ledger_status_check
    CHECK (status IN ('reserved', 'consumed', 'released')),
  CONSTRAINT usage_ledger_source_check
    CHECK (entitlement_source IN ('free', 'pro')),
  CONSTRAINT usage_ledger_settled_shape_check
    CHECK (status = 'reserved' OR settled_at IS NOT NULL)
);

-- Idempotency, enforced in the database and not in a JavaScript Set.
CREATE UNIQUE INDEX usage_ledger_client_request_unique
  ON medorbit.usage_ledger (user_id, feature_code, client_request_id)
  WHERE client_request_id IS NOT NULL;

CREATE INDEX usage_ledger_window_status
  ON medorbit.usage_ledger (window_id, status);

-- ---------------------------------------------------------------------
-- Voice consultation grants — the entitlement half of a Virtual Doctor
-- session's lifecycle.
--
-- Kept out of virtual_doctor_sessions on purpose. That table is the medical
-- record of the consultation; this one is the billing/eligibility record
-- that points at it by opaque session identifier. Neither needs the other's
-- columns, and merging them would put quota bookkeeping inside a clinical
-- table.
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.voice_session_grants (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id            UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  -- Matches virtual_doctor_sessions.session_id. Intentionally not a foreign
  -- key: the grant is reserved before the AI service has created its session
  -- row, so the constraint would fire on a row that is about to exist.
  vd_session_id      VARCHAR(64) UNIQUE,
  entitlement_source VARCHAR(10) NOT NULL,
  status             VARCHAR(16) NOT NULL DEFAULT 'active',
  started_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Bumped on every turn. Drives idle expiry, which is what stops a user
  -- parking one consultation open forever to dodge the cooldown.
  last_activity_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Hard ceiling on a single consultation, set at reservation time.
  expires_at         TIMESTAMPTZ NOT NULL,
  finalized_at       TIMESTAMPTZ,
  -- Cooldown anchor, written when a FREE grant finalizes. Pro grants leave
  -- this null: an unlimited plan has no next-free instant.
  next_free_at       TIMESTAMPTZ,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT voice_session_grants_source_check
    CHECK (entitlement_source IN ('free', 'pro')),
  CONSTRAINT voice_session_grants_status_check
    CHECK (status IN ('active', 'completed', 'expired', 'abandoned')),
  CONSTRAINT voice_session_grants_finalized_shape_check
    CHECK (status = 'active' OR finalized_at IS NOT NULL),
  -- Only a free grant may schedule a cooldown.
  CONSTRAINT voice_session_grants_cooldown_shape_check
    CHECK (next_free_at IS NULL OR entitlement_source = 'free')
);

-- The core anti-abuse constraint. At most one active consultation per user,
-- enforced by the database, so two tabs / two devices / a duplicate /start
-- cannot each reserve their own free session. Pro is included deliberately:
-- "unlimited" means no quota, not unbounded concurrency.
CREATE UNIQUE INDEX voice_session_grants_one_active_per_user_unique
  ON medorbit.voice_session_grants (user_id)
  WHERE status = 'active';

-- Cooldown lookup: the most recent finalized free grant for a user.
CREATE INDEX voice_session_grants_cooldown_lookup
  ON medorbit.voice_session_grants (user_id, next_free_at DESC)
  WHERE entitlement_source = 'free';

-- Sweeper scan for grants that outlived their idle/max window.
CREATE INDEX voice_session_grants_expiry_sweep
  ON medorbit.voice_session_grants (expires_at, last_activity_at)
  WHERE status = 'active';

-- ---------------------------------------------------------------------
-- Consultation ownership.
--
-- virtual_doctor_sessions.user_id already existed but was written as NULL by
-- every client, leaving consultations unowned and readable by session id
-- alone. Ownership lookups become a hot path once the AI service filters on
-- it, so it gets an index.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS virtual_doctor_sessions_owner_lookup
  ON medorbit.virtual_doctor_sessions (user_id, created_at DESC);

-- ---------------------------------------------------------------------
-- Seed the plan catalogue.
--
-- Prices live here and nowhere else. The annual price is a plain stored
-- number, not a discount computed at runtime, so no two code paths can ever
-- disagree about what a year costs.
-- ---------------------------------------------------------------------
INSERT INTO medorbit.subscription_plans
  (plan_code, name_en, name_ar, price_cents, currency, billing_interval, interval_count, grants_pro, sort_order)
VALUES
  ('free',        'Free',         'مجاني',       0,     'USD', 'none',  1, false, 0),
  ('pro_monthly', 'MedOrbit Pro', 'مدأوربت برو', 2000,  'USD', 'month', 1, true,  1),
  ('pro_annual',  'MedOrbit Pro', 'مدأوربت برو', 20000, 'USD', 'year',  1, true,  2);

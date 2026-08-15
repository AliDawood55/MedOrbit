-- =====================================================================
-- Checkout sessions and subscription lifecycle — still provider-independent.
--
-- Phase 1 built the entitlement half: who may run what, and why. This adds
-- the half that changes it: a checkout attempt, its outcome, and the
-- scheduled plan change a renewal applies.
--
-- The same hard rule as 014 holds. Nothing here stores a card number, a
-- cardholder name, an amount submitted by a browser, or one word of medical
-- content. Provider linkage stays limited to opaque string columns, so the
-- mock provider used in development and a real hosted provider later occupy
-- exactly the same shape.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Checkout sessions.
--
-- A row here is an *attempt*, not a payment and not an entitlement. It is
-- created before the user leaves for the provider's page and is resolved by
-- a provider event afterwards. Deliberately separate from subscriptions:
-- most attempts never become one, and an abandoned attempt must not leave a
-- half-built subscription row behind.
-- ---------------------------------------------------------------------
CREATE TABLE medorbit.billing_checkout_sessions (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID NOT NULL REFERENCES medorbit.users(id) ON DELETE CASCADE,
  plan_id             UUID NOT NULL REFERENCES medorbit.subscription_plans(id),
  provider            VARCHAR(32)  NOT NULL,
  -- The provider's handle for this attempt, and the token that appears in
  -- the checkout URL. Opaque and unguessable by construction; ownership is
  -- still re-checked against user_id on every read, because a URL that
  -- leaks must not become an entitlement.
  provider_session_id VARCHAR(128) NOT NULL,
  status              VARCHAR(16)  NOT NULL DEFAULT 'open',
  -- Where to send the user once the attempt resolves. Stored server-side
  -- rather than carried in the redirect, so a tampered return URL cannot
  -- turn checkout into an open redirect.
  return_path         VARCHAR(255),
  expires_at          TIMESTAMPTZ  NOT NULL,
  completed_at        TIMESTAMPTZ,
  subscription_id     UUID REFERENCES medorbit.subscriptions(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT billing_checkout_sessions_status_check
    CHECK (status IN ('open', 'completed', 'canceled', 'failed', 'expired')),
  -- A resolved attempt must record when it resolved.
  CONSTRAINT billing_checkout_sessions_resolved_shape_check
    CHECK (status = 'open' OR completed_at IS NOT NULL),
  -- Only a completed attempt may point at a subscription.
  CONSTRAINT billing_checkout_sessions_subscription_shape_check
    CHECK (subscription_id IS NULL OR status = 'completed')
);

-- One attempt per provider handle. This is what makes replaying a checkout
-- completion a no-op rather than a second subscription.
CREATE UNIQUE INDEX billing_checkout_sessions_provider_session_unique
  ON medorbit.billing_checkout_sessions (provider, provider_session_id);

CREATE INDEX billing_checkout_sessions_user_lookup
  ON medorbit.billing_checkout_sessions (user_id, created_at DESC);

-- Sweep for attempts the user walked away from.
CREATE INDEX billing_checkout_sessions_open_expiry
  ON medorbit.billing_checkout_sessions (expires_at)
  WHERE status = 'open';

-- ---------------------------------------------------------------------
-- Scheduled plan change.
--
-- Monthly <-> Annual takes effect at the next renewal, never mid-period.
-- Modelled as a pointer on the live subscription rather than as an
-- immediate plan_id swap, because swapping immediately would either give
-- away a year for a month's payment or take away access already paid for.
-- Both of those are proration decisions, and proration is a financial
-- policy that belongs to a real provider, not to a sandbox.
-- ---------------------------------------------------------------------
ALTER TABLE medorbit.subscriptions
  ADD COLUMN pending_plan_id UUID REFERENCES medorbit.subscription_plans(id);

-- A subscription that is ending has nothing to change plan to.
ALTER TABLE medorbit.subscriptions
  ADD CONSTRAINT subscriptions_pending_plan_shape_check
    CHECK (pending_plan_id IS NULL OR cancel_at_period_end = false);

-- ---------------------------------------------------------------------
-- Event ownership.
--
-- billing_events could previously only be attributed to a user through its
-- subscription, which leaves exactly the events a user most needs to see
-- unattributable: a failed FIRST payment never produces a subscription.
-- Nullable because a provider may legitimately send an event we cannot yet
-- attribute to anyone, and dropping such an event would lose the audit
-- trail that makes reconciliation possible.
-- ---------------------------------------------------------------------
ALTER TABLE medorbit.billing_events
  ADD COLUMN user_id UUID REFERENCES medorbit.users(id) ON DELETE CASCADE;

-- Drives the user-facing billing history in one index hit.
CREATE INDEX billing_events_user_history
  ON medorbit.billing_events (user_id, received_at DESC)
  WHERE user_id IS NOT NULL;

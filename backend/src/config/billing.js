/**
 * Billing and entitlement policy — the single place business policy lives.
 *
 * Every quota number, window length, timeout and grace period in the product
 * is defined here and nowhere else. Features ask this module; they never
 * carry their own copy of "20" or "24 hours". Operators can retune any of it
 * through the environment without a code change, and every value is clamped
 * so a typo in .env degrades to something sane rather than disabling a limit.
 *
 * Price is deliberately NOT here — it lives in medorbit.subscription_plans,
 * because a price is data that changes per plan row, while these are policy
 * constants that apply across plans.
 */

function intFromEnv(name, fallback, { min, max }) {
    const parsed = Number(process.env[name]);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(Math.max(Math.trunc(parsed), min), max);
}

/**
 * Feature codes. These strings are written into usage_ledger.feature_code and
 * usage_windows.feature_code, so they are storage identifiers — renaming one
 * orphans existing usage rows.
 */
const FEATURES = {
    CHATBOT_MESSAGE: 'chatbot_message',
    VOICE_CONSULTATION: 'voice_consultation',
};

/**
 * Plan codes. Identity, never price. The client submits one of these; the
 * backend resolves it against the plan catalogue to decide what it costs.
 */
const PLAN_CODES = {
    FREE: 'free',
    PRO_MONTHLY: 'pro_monthly',
    PRO_ANNUAL: 'pro_annual',
};

/**
 * Subscription statuses that grant Pro entitlement.
 *
 * 'past_due' is intentionally absent from this list and handled separately:
 * it grants Pro only while inside its grace window (see isProGrantingStatus).
 * Encoding it here as an unconditional grant would give a permanently failing
 * card permanent free Pro.
 */
const PRO_GRANTING_STATUSES = Object.freeze(['active']);

/** Statuses that occupy the "one live subscription per user" slot. */
const LIVE_STATUSES = Object.freeze(['incomplete', 'active', 'past_due']);

const policy = {
    chatbot: {
        /**
         * Free user messages accepted per window. Counts accepted messages
         * only — never assistant replies, history loads, or requests rejected
         * before the AI was called.
         */
        freeMessagesPerWindow: intFromEnv('BILLING_CHATBOT_FREE_MESSAGES', 20, { min: 0, max: 10000 }),
        windowHours: intFromEnv('BILLING_CHATBOT_WINDOW_HOURS', 24, { min: 1, max: 24 * 30 }),
    },

    voice: {
        /**
         * Free consultations granted per cooldown cycle. The cooldown starts
         * when a consultation FINALIZES, not when it starts, so a user who
         * finishes quickly is not punished for it.
         */
        freeSessionsPerCycle: intFromEnv('BILLING_VOICE_FREE_SESSIONS', 1, { min: 0, max: 100 }),
        cooldownHours: intFromEnv('BILLING_VOICE_COOLDOWN_HOURS', 24, { min: 1, max: 24 * 30 }),

        /**
         * Idle expiry. A consultation with no patient turn for this long is
         * finalized as 'expired' and the cooldown begins. This is what stops
         * a user from parking one session open forever to avoid ever entering
         * the cooldown — without cutting off someone who is genuinely mid-
         * consultation and thinking about an answer.
         */
        idleTimeoutMinutes: intFromEnv('BILLING_VOICE_IDLE_TIMEOUT_MINUTES', 30, { min: 5, max: 24 * 60 }),

        /**
         * Hard ceiling on one consultation regardless of activity. A real
         * consultation is minutes long; anything approaching this is either
         * abandoned or automated.
         */
        maxLifetimeMinutes: intFromEnv('BILLING_VOICE_MAX_LIFETIME_MINUTES', 120, { min: 10, max: 24 * 60 }),
    },

    idempotency: {
        /**
         * How long a reservation may sit un-settled before a retry of the same
         * client_request_id is allowed to take it over.
         *
         * Must exceed the AI call timeout (AI_SERVICE_TIMEOUT_MS, 60s by
         * default), or a slow-but-alive request would have its unit stolen by
         * its own retry. Below that ceiling the duplicate is rejected as
         * still-in-flight; above it the original is assumed dead, so a crashed
         * request cannot strand a request id until the window rolls over.
         */
        inFlightSeconds: intFromEnv('BILLING_IDEMPOTENCY_INFLIGHT_SECONDS', 120, { min: 5, max: 900 }),
    },

    subscription: {
        /**
         * How long a past_due subscription keeps Pro while the provider
         * retries the payment. Product-owner decision: a transient card
         * failure must not interrupt service mid-consultation.
         */
        pastDueGraceDays: intFromEnv('BILLING_PAST_DUE_GRACE_DAYS', 7, { min: 0, max: 90 }),
    },

    /**
     * Fair-use ceilings that apply to EVERYONE, Pro included. "Unlimited"
     * describes the product quota, not the infrastructure. These exist to
     * stop one account from monopolising the AI workers.
     */
    fairUse: {
        maxConcurrentVoiceSessions: 1,
        chatbotMessagesPerMinute: intFromEnv('BILLING_FAIR_USE_CHAT_PER_MINUTE', 20, { min: 1, max: 600 }),
    },
};

/**
 * Machine-readable error codes. Clients branch on these, never on the English
 * message text, so business decisions survive translation and copy edits.
 */
const ERROR_CODES = {
    FREE_QUOTA_EXHAUSTED: 'FREE_QUOTA_EXHAUSTED',
    /** The same client_request_id is already being processed right now. */
    DUPLICATE_IN_FLIGHT: 'DUPLICATE_IN_FLIGHT',
    VOICE_COOLDOWN: 'VOICE_COOLDOWN',
    VOICE_SESSION_ACTIVE: 'VOICE_SESSION_ACTIVE',
    SUBSCRIPTION_REQUIRED: 'SUBSCRIPTION_REQUIRED',
    SUBSCRIPTION_INACTIVE: 'SUBSCRIPTION_INACTIVE',
    ENTITLEMENT_UNAVAILABLE: 'ENTITLEMENT_UNAVAILABLE',
    /** No checkout attempt matches this token for this user. */
    CHECKOUT_NOT_FOUND: 'CHECKOUT_NOT_FOUND',
    /** The attempt exists but has already been resolved or has expired. */
    CHECKOUT_NOT_OPEN: 'CHECKOUT_NOT_OPEN',
    /** The caller has no live subscription to act on. */
    SUBSCRIPTION_NOT_FOUND: 'SUBSCRIPTION_NOT_FOUND',
    /** The caller already holds a live subscription; buying a second is refused. */
    SUBSCRIPTION_ALREADY_LIVE: 'SUBSCRIPTION_ALREADY_LIVE',
    /** The requested plan change is not one this phase supports. */
    PLAN_CHANGE_INVALID: 'PLAN_CHANGE_INVALID',
    /** A sandbox-only route was reached without sandbox billing enabled. */
    SANDBOX_DISABLED: 'SANDBOX_DISABLED',
};

/**
 * Decide whether a subscription row currently grants Pro.
 *
 * Kept as a function rather than a status list because past_due is time-
 * dependent: the same row grants Pro before its grace deadline and not after,
 * and no static list can express that.
 *
 * @param {{status: string, grace_period_ends_at?: Date|string|null, current_period_end?: Date|string|null}} subscription
 * @param {Date} now - Server time. Passed in so callers can use database time.
 */
function isProGrantingStatus(subscription, now = new Date()) {
    if (!subscription) return false;

    if (PRO_GRANTING_STATUSES.includes(subscription.status)) {
        // cancel_at_period_end deliberately does not appear here. An active
        // subscription with auto-renew switched off keeps paid access until
        // the period actually ends — cancelling is not a refund.
        const periodEnd = subscription.current_period_end
            ? new Date(subscription.current_period_end)
            : null;
        return !periodEnd || periodEnd > now;
    }

    if (subscription.status === 'past_due') {
        const graceEnd = subscription.grace_period_ends_at
            ? new Date(subscription.grace_period_ends_at)
            : null;
        return Boolean(graceEnd && graceEnd > now);
    }

    return false;
}


/**
 * Canonical billing event types.
 *
 * Provider-independent by design. A real provider's own event names are
 * translated into these by its adapter and never reach the subscription
 * state machine, so swapping providers cannot require editing business
 * logic — which is the whole reason the mock provider is worth building
 * against the same vocabulary a real one will use.
 */
const BILLING_EVENTS = Object.freeze({
    CHECKOUT_COMPLETED: 'checkout.completed',
    SUBSCRIPTION_ACTIVATED: 'subscription.activated',
    SUBSCRIPTION_RENEWED: 'subscription.renewed',
    SUBSCRIPTION_UPDATED: 'subscription.updated',
    SUBSCRIPTION_CANCEL_AT_PERIOD_END: 'subscription.cancel_at_period_end',
    SUBSCRIPTION_CANCELED: 'subscription.canceled',
    PAYMENT_FAILED: 'payment.failed',
    PAYMENT_RECOVERED: 'payment.recovered',
});

const MOCK_PROVIDER_NAME = 'mock';

/**
 * Resolve which provider is configured, and whether the sandbox may run.
 *
 * Enabling the mock takes TWO deliberate variables, not one. A single
 * mistyped or inherited BILLING_PROVIDER cannot by itself turn on a
 * checkout that grants Pro for free — the operator has to have said so
 * twice.
 */
function readProviderConfig(env = process.env) {
    const name = String(env.BILLING_PROVIDER || '').trim().toLowerCase() || null;
    const nodeEnv = String(env.NODE_ENV || 'development').trim().toLowerCase();
    const isProduction = nodeEnv === 'production';
    const mockRequested = name === MOCK_PROVIDER_NAME;
    const mockFlagSet = String(env.BILLING_MOCK_ENABLED || '').trim().toLowerCase() === 'true';

    return {
        name,
        nodeEnv,
        isProduction,
        mockRequested,
        mockFlagSet,
        // The only expression in the codebase that may authorise a simulated
        // payment. Read it; never re-derive it from the raw variables.
        mockEnabled: mockRequested && mockFlagSet && !isProduction,
    };
}

/**
 * Refuse to boot a production process that has sandbox billing configured.
 *
 * Failing startup is the right severity, and quietly disabling the mock
 * would be the wrong one. A deployment that believes it is taking payments
 * while a simulate-success button is reachable is a far worse outcome than
 * a container that will not start and says exactly why. Both variables are
 * checked, so neither one alone can survive into production unnoticed.
 *
 * @throws {Error} when NODE_ENV=production and any mock billing variable is set.
 */
function assertProviderConfigSafe(env = process.env) {
    const config = readProviderConfig(env);
    if (!config.isProduction) return config;

    if (config.mockRequested) {
        throw new Error(
            'BILLING_PROVIDER=mock is refused when NODE_ENV=production. ' +
            'The mock provider grants Pro without payment and must never be reachable in production.'
        );
    }
    if (config.mockFlagSet) {
        throw new Error(
            'BILLING_MOCK_ENABLED=true is refused when NODE_ENV=production. ' +
            'Remove it from the production environment.'
        );
    }
    return config;
}

module.exports = {
    FEATURES,
    PLAN_CODES,
    PRO_GRANTING_STATUSES,
    LIVE_STATUSES,
    ERROR_CODES,
    BILLING_EVENTS,
    MOCK_PROVIDER_NAME,
    policy,
    isProGrantingStatus,
    readProviderConfig,
    assertProviderConfigSafe,
};

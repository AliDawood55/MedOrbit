const crypto = require('crypto');

const { BILLING_EVENTS, ERROR_CODES, MOCK_PROVIDER_NAME, readProviderConfig } = require('../../config/billing');
const { BillingProviderError } = require('./provider');

/**
 * MockBillingProvider — a local sandbox that behaves like a payment provider
 * without being one.
 *
 * The point is not to fake a payment. It is to exercise the real pipeline:
 * a checkout session the backend creates, a hosted page the user is
 * redirected to, an asynchronous signed event coming back, signature
 * verification over raw bytes, idempotent event recording, and only then a
 * subscription state change. Every one of those steps is the step a real
 * provider will use. Phase 3 replaces this file and nothing else.
 *
 * What it deliberately does NOT simulate is card collection. There is no
 * card number, expiry, CVV or fake PAN anywhere in this provider or on the
 * page it redirects to, because the future architecture keeps card entry on
 * the provider's PCI DSS validated pages and MedOrbit out of PCI scope
 * entirely. Building a fake card form now would be practice for the wrong
 * architecture.
 *
 * Enabling it requires BILLING_PROVIDER=mock AND BILLING_MOCK_ENABLED=true,
 * and is refused outright when NODE_ENV=production (see
 * assertProviderConfigSafe in config/billing.js).
 */

/** Signed events older than this are refused, so a captured body cannot be replayed later. */
const SIGNATURE_TOLERANCE_SECONDS = 300;

const SIGNATURE_HEADER = 'x-medorbit-billing-signature';

/**
 * Sign the RAW body, with the timestamp inside the signed material.
 *
 * Signing `${timestamp}.${body}` rather than the body alone is what makes
 * the timestamp trustworthy: an attacker who captures a valid delivery
 * cannot slide its timestamp forward to defeat the freshness window without
 * invalidating the signature.
 */
function computeSignature(secret, timestamp, rawBody) {
    return crypto
        .createHmac('sha256', secret)
        .update(`${timestamp}.`)
        .update(rawBody)
        .digest('hex');
}

/**
 * Compare two signatures without leaking where they first differ.
 *
 * timingSafeEqual throws on a length mismatch, which would itself be a
 * length oracle, so the lengths are checked first and a mismatch simply
 * returns false.
 */
function signaturesMatch(expected, received) {
    if (typeof received !== 'string') return false;
    const a = Buffer.from(expected, 'utf8');
    const b = Buffer.from(received, 'utf8');
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
}

function parseSignatureHeader(value) {
    // Format: t=<unix seconds>,v1=<hex>. Matches the shape real providers use,
    // so the verification code does not change when one replaces this.
    const parts = String(value || '').split(',');
    const out = { t: null, v1: null };
    for (const part of parts) {
        const [key, val] = part.split('=');
        if (key === 't') out.t = val;
        if (key === 'v1') out.v1 = val;
    }
    return out;
}

function requireSecret() {
    const secret = process.env.BILLING_MOCK_WEBHOOK_SECRET;
    if (!secret || String(secret).length < 16) {
        throw new BillingProviderError(
            'BILLING_MOCK_WEBHOOK_SECRET must be set to at least 16 characters when sandbox billing is enabled.',
            ERROR_CODES.ENTITLEMENT_UNAVAILABLE
        );
    }
    return String(secret);
}

/**
 * Where the sandbox "hosted checkout" lives.
 *
 * A real provider hosts this on its own domain. The sandbox serves it from
 * the frontend, but the page has no more authority than a provider's page
 * would: it cannot write a subscription, and everything it does goes back
 * through a signed event.
 */
function checkoutPageUrl(providerSessionId) {
    const base = String(process.env.FRONTEND_URL || '').replace(/\/+$/, '');
    return `${base}/billing-sandbox.html?session=${encodeURIComponent(providerSessionId)}`;
}

const mockProvider = {
    name: MOCK_PROVIDER_NAME,
    isConfigured: true,
    isSandbox: true,

    /**
     * Mint a checkout handle and the URL to send the browser to.
     *
     * Note what is absent: the amount. The caller passes a plan_code, and
     * price is resolved from the plan catalogue by the code that persists
     * the attempt. A provider adapter never accepts a number from a client,
     * and this one is written to make that impossible to forget.
     */
    async createCheckout({ planCode }) {
        requireSecret();
        if (!planCode) throw new BillingProviderError('A plan_code is required to create a checkout.');

        const providerSessionId = `cs_mock_${crypto.randomBytes(24).toString('hex')}`;
        return { checkoutUrl: checkoutPageUrl(providerSessionId), providerSessionId };
    },

    async createOrGetCustomer({ billingReference }) {
        return { providerCustomerId: `cus_mock_${billingReference}` };
    },

    /**
     * Provider-side cancel.
     *
     * Returns rather than mutating anything: in the real architecture the
     * provider records the intent and then tells us about it in an event,
     * and our own state only changes when that event arrives. The sandbox
     * keeps the same ordering so the code path is the one that ships.
     */
    async cancelSubscription({ providerSubscriptionId, atPeriodEnd }) {
        return {
            providerSubscriptionId,
            cancel_at_period_end: Boolean(atPeriodEnd),
            events: [buildEvent(BILLING_EVENTS.SUBSCRIPTION_CANCEL_AT_PERIOD_END, {
                provider_subscription_id: providerSubscriptionId,
                cancel_at_period_end: Boolean(atPeriodEnd),
            })],
        };
    },

    async resumeSubscription({ providerSubscriptionId }) {
        return {
            providerSubscriptionId,
            cancel_at_period_end: false,
            events: [buildEvent(BILLING_EVENTS.SUBSCRIPTION_CANCEL_AT_PERIOD_END, {
                provider_subscription_id: providerSubscriptionId,
                cancel_at_period_end: false,
            })],
        };
    },

    /**
     * Schedule a plan change. The sandbox reports it exactly as a provider
     * would: as an update event naming the plan that takes effect next
     * renewal, never as an immediate price adjustment.
     */
    async updateSubscription({ providerSubscriptionId, planCode }) {
        return {
            providerSubscriptionId,
            events: [buildEvent(BILLING_EVENTS.SUBSCRIPTION_UPDATED, {
                provider_subscription_id: providerSubscriptionId,
                pending_plan_code: planCode,
            })],
        };
    },

    async getSubscription({ providerSubscriptionId }) {
        return { providerSubscriptionId };
    },

    /**
     * There is no provider-hosted portal in the sandbox, so this points back
     * at MedOrbit's own billing page rather than inventing a fake one.
     */
    async createBillingPortalSession({ returnUrl }) {
        const base = String(process.env.FRONTEND_URL || '').replace(/\/+$/, '');
        return { portalUrl: returnUrl || `${base}/billing.html` };
    },

    /**
     * Produce the headers a signed delivery carries.
     *
     * Used by the sandbox to deliver its own events through the ordinary
     * webhook entry point. The sandbox does not get a shortcut past
     * signature verification — it has to produce a valid signature like any
     * other sender, which is what keeps the verification path exercised.
     */
    signPayload(rawBody) {
        const secret = requireSecret();
        const timestamp = Math.floor(Date.now() / 1000);
        return {
            [SIGNATURE_HEADER]: `t=${timestamp},v1=${computeSignature(secret, timestamp, rawBody)}`,
            'content-type': 'application/json',
        };
    },

    /**
     * Verify a delivery over its RAW bytes.
     *
     * Raw bytes, not the parsed object: re-serialising JSON reorders keys and
     * changes whitespace, so a signature checked against a re-serialised body
     * verifies nothing. Anything that fails here returns verified:false and
     * the caller rejects without reading a single field out of the payload.
     */
    async verifyWebhook({ rawBody, headers }) {
        const unverified = { verified: false, eventId: null, eventType: null, eventCreatedAt: null, data: null };

        let secret;
        try { secret = requireSecret(); } catch { return unverified; }

        if (!rawBody || !rawBody.length) return unverified;

        const header = headers ? (headers[SIGNATURE_HEADER] || headers[SIGNATURE_HEADER.toUpperCase()]) : null;
        const { t, v1 } = parseSignatureHeader(header);
        if (!t || !v1) return unverified;

        const timestamp = Number(t);
        if (!Number.isFinite(timestamp)) return unverified;

        const ageSeconds = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
        if (ageSeconds > SIGNATURE_TOLERANCE_SECONDS) return unverified;

        if (!signaturesMatch(computeSignature(secret, timestamp, rawBody), v1)) return unverified;

        let payload;
        try { payload = JSON.parse(rawBody.toString('utf8')); } catch { return unverified; }

        if (!payload || typeof payload.id !== 'string' || typeof payload.type !== 'string') return unverified;

        return {
            verified: true,
            eventId: payload.id,
            eventType: payload.type,
            eventCreatedAt: payload.created_at || null,
            data: payload.data && typeof payload.data === 'object' ? payload.data : {},
        };
    },
};

/**
 * Build the canonical envelope for a sandbox event.
 *
 * provider_event_id is generated here and is what makes replay a no-op: the
 * events table holds it under a unique index, so delivering the same
 * envelope twice records once and applies once.
 */
function buildEvent(type, data) {
    return {
        id: `evt_mock_${crypto.randomBytes(16).toString('hex')}`,
        type,
        created_at: new Date().toISOString(),
        data: data || {},
    };
}

function isMockEnabled() {
    return readProviderConfig().mockEnabled;
}

/**
 * The outcomes a sandbox checkout page may produce.
 *
 * 'canceled' produces no event at all, which is correct rather than lazy: a
 * user who backs out of a provider's page generates nothing on the
 * provider's side either. The attempt is closed locally by the route.
 */
const CHECKOUT_OUTCOMES = Object.freeze(['success', 'failure', 'canceled']);

function checkoutOutcomeEvents(providerSessionId, outcome) {
    if (outcome === 'success') {
        return [buildEvent(BILLING_EVENTS.CHECKOUT_COMPLETED, {
            checkout_session_id: providerSessionId,
            // The provider's own handle for the subscription it just created.
            // Derived from the attempt so a redelivery names the same one.
            provider_subscription_id: `sub_mock_${providerSessionId.replace(/^cs_mock_/, '')}`,
        })];
    }
    if (outcome === 'failure') {
        // Carries the checkout handle, NOT a subscription id. That is what
        // routes it to the initial-payment branch, where no grace window and
        // no entitlement are created.
        return [buildEvent(BILLING_EVENTS.PAYMENT_FAILED, {
            checkout_session_id: providerSessionId,
        })];
    }
    return [];
}

/**
 * Lifecycle events a developer can trigger against an existing subscription.
 *
 * These stand in for the things a real provider does on its own schedule —
 * a monthly charge, a declined card, a successful retry — none of which can
 * be waited for in a development environment.
 */
const LIFECYCLE_SIMULATIONS = Object.freeze(['renewal', 'renewal_failure', 'payment_recovered', 'ended']);

function lifecycleEvents(kind, providerSubscriptionId) {
    const data = { provider_subscription_id: providerSubscriptionId };
    switch (kind) {
        case 'renewal':          return [buildEvent(BILLING_EVENTS.SUBSCRIPTION_RENEWED, data)];
        case 'renewal_failure':  return [buildEvent(BILLING_EVENTS.PAYMENT_FAILED, data)];
        case 'payment_recovered':return [buildEvent(BILLING_EVENTS.PAYMENT_RECOVERED, data)];
        case 'ended':            return [buildEvent(BILLING_EVENTS.SUBSCRIPTION_CANCELED, data)];
        default:                 return [];
    }
}

module.exports = {
    mockProvider,
    buildEvent,
    isMockEnabled,
    checkoutOutcomeEvents,
    lifecycleEvents,
    CHECKOUT_OUTCOMES,
    LIFECYCLE_SIMULATIONS,
    SIGNATURE_HEADER,
    SIGNATURE_TOLERANCE_SECONDS,
};

const { ERROR_CODES } = require('../../config/billing');

/**
 * BillingProvider — the seam a payment provider will eventually plug into.
 *
 * This exists so that no provider's name ever appears in business code. When
 * a provider is chosen, it is implemented behind this interface and selected
 * by configuration; EntitlementService, the routes and the repositories stay
 * untouched, because none of them know or care who processes the money.
 *
 * There is deliberately NO working implementation here, and no mock that
 * pretends to be one. A stub that returned a plausible-looking checkout URL
 * would be worse than nothing: it would let a "working" upgrade flow be
 * demonstrated, reviewed and merged while activating Pro on nothing but the
 * frontend's say-so. Until a real provider is integrated, every operation
 * below fails loudly.
 *
 * PCI note: none of these operations accept a card number, a CVV, or any
 * cardholder data. createCheckout returns a URL the user is redirected to,
 * so card entry happens entirely on the provider's PCI DSS validated pages
 * and never touches a MedOrbit form, process or log.
 */

class BillingProviderError extends Error {
    constructor(message, code = ERROR_CODES.ENTITLEMENT_UNAVAILABLE) {
        super(message);
        this.name = 'BillingProviderError';
        this.code = code;
    }
}

/**
 * The operations a provider must supply. Documented as an interface rather
 * than enforced as an abstract class, matching how the rest of this codebase
 * defines service contracts.
 *
 * @typedef {Object} BillingProvider
 * @property {string} name
 * @property {(args: {userId: string, planCode: string, billingReference: string, successUrl: string, cancelUrl: string}) => Promise<{checkoutUrl: string, providerSessionId: string}>} createCheckout
 *   Resolves plan_code to a provider price server-side. Never accepts an
 *   amount from a client.
 * @property {(args: {userId: string, billingReference: string}) => Promise<{providerCustomerId: string}>} createOrGetCustomer
 * @property {(args: {providerSubscriptionId: string, atPeriodEnd: boolean}) => Promise<object>} cancelSubscription
 * @property {(args: {providerSubscriptionId: string}) => Promise<object>} resumeSubscription
 * @property {(args: {providerSubscriptionId: string}) => Promise<object>} getSubscription
 * @property {(args: {rawBody: Buffer, headers: object}) => Promise<{verified: boolean, eventId: string, eventType: string, eventCreatedAt: string|null, data: object}>} verifyWebhook
 *   Must verify a cryptographic signature over the RAW request body. A
 *   webhook that merely parses as JSON is not verified.
 * @property {(args: {billingReference: string, returnUrl: string}) => Promise<{portalUrl: string}>} createBillingPortalSession
 */

const UNCONFIGURED = 'No payment provider is configured. Billing operations are unavailable.';

/**
 * The active provider until one is selected and approved.
 *
 * Every method rejects. This is the correct behaviour for Phase 1: the
 * entitlement foundation is complete and enforcing, but there is no way to
 * become Pro yet, and pretending otherwise would be a security hole rather
 * than a convenience.
 */
const unconfiguredProvider = {
    name: 'unconfigured',
    isConfigured: false,

    async createCheckout() { throw new BillingProviderError(UNCONFIGURED); },
    async createOrGetCustomer() { throw new BillingProviderError(UNCONFIGURED); },
    async cancelSubscription() { throw new BillingProviderError(UNCONFIGURED); },
    async resumeSubscription() { throw new BillingProviderError(UNCONFIGURED); },
    async getSubscription() { throw new BillingProviderError(UNCONFIGURED); },
    async createBillingPortalSession() { throw new BillingProviderError(UNCONFIGURED); },

    /**
     * Refuses rather than throwing, because a webhook endpoint that 500s on an
     * unconfigured provider invites retry storms from a misdirected sender.
     * An unverified webhook is rejected, never processed.
     */
    async verifyWebhook() {
        return { verified: false, eventId: null, eventType: null, eventCreatedAt: null, data: null };
    },
};

const registry = new Map();

/** Register a real provider implementation. Called once a provider is approved. */
function registerProvider(provider) {
    if (!provider || !provider.name) throw new Error('A billing provider must have a name');
    registry.set(provider.name, provider);
}

/**
 * The provider selected by configuration.
 *
 * Falls back to the unconfigured provider rather than throwing at import time,
 * so the rest of the application boots normally with billing simply
 * unavailable — the state Phase 1 ships in.
 */
function getProvider() {
    const configured = process.env.BILLING_PROVIDER;
    if (configured && registry.has(configured)) return registry.get(configured);
    return unconfiguredProvider;
}

module.exports = {
    BillingProviderError,
    registerProvider,
    getProvider,
    unconfiguredProvider,
};

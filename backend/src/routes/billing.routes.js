const express = require('express');

const { authenticate } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const entitlementService = require('../services/entitlement.service');
const subscriptionService = require('../services/billing/subscription.service');
const billingRepository = require('../repositories/billing.repository');
const { getProvider, BillingProviderError } = require('../services/billing/provider');
const { ERROR_CODES, readProviderConfig } = require('../config/billing');
const logger = require('../utils/logger');

const router = express.Router();

/**
 * The single read endpoint clients render quota and paywall UI from.
 *
 * Everything here is computed server-side against database time. The client
 * may display it and may count down toward the timestamps it returns, but it
 * has no path to change any of it — there is no corresponding write endpoint,
 * by design.
 */
router.get('/entitlements', authenticate, async (req, res, next) => {
    try {
        const snapshot = await entitlementService.getEntitlementSnapshot(req.user.sub);
        return success(res, snapshot);
    } catch (err) {
        return next(err);
    }
});

/**
 * Plan catalogue with prices, straight from the database.
 *
 * The frontend renders these numbers and never computes them. There is no
 * second place in the codebase where $20 or $200 is written down, so a price
 * change is one UPDATE and cannot leave the UI and the checkout disagreeing.
 */
router.get('/plans', authenticate, async (req, res, next) => {
    try {
        const plans = await billingRepository.listActivePlans();
        return success(res, {
            plans: plans.map((plan) => ({
                plan_code: plan.plan_code,
                name_en: plan.name_en,
                name_ar: plan.name_ar,
                price_cents: plan.price_cents,
                currency: plan.currency,
                billing_interval: plan.billing_interval,
                interval_count: plan.interval_count,
                grants_pro: plan.grants_pro,
            })),
        });
    } catch (err) {
        return next(err);
    }
});

/**
 * What the billing UI needs to know about the environment.
 *
 * Reports whether checkout is available at all and whether it is a sandbox,
 * so the frontend can show the "no real payment will be processed" banner
 * honestly rather than guessing from a build flag. Carries no authority:
 * a client that lies to itself about this still cannot buy anything, because
 * the sandbox routes below are absent from a production process entirely.
 */
router.get('/config', authenticate, async (req, res) => {
    const provider = getProvider();
    return success(res, {
        checkout_available: Boolean(provider.isConfigured),
        sandbox: Boolean(provider.isSandbox),
    });
});

/**
 * Begin an upgrade.
 *
 * The client sends a plan_code and, optionally, where to return afterwards.
 * Any amount, price, currency, is_pro, status or discount in the request body
 * is ignored outright — price is resolved from the plan catalogue server-side,
 * so a tampered request cannot buy Pro for a dollar or grant itself anything.
 *
 * Returns 503 when no provider is configured. That is not a stub: a fake
 * checkout that appeared to succeed would be a way to obtain Pro without
 * paying, which is exactly what the sandbox is carefully fenced off to avoid.
 */
router.post('/checkout', authenticate, async (req, res, next) => {
    try {
        const planCode = typeof req.body?.plan_code === 'string' ? req.body.plan_code : null;
        if (!planCode) {
            return error(res, 'A plan_code is required', 400, 'VALIDATION_ERROR');
        }

        const result = await subscriptionService.createCheckout({
            userId: req.user.sub,
            planCode,
            returnPath: req.body?.return_path,
        });

        if (!result.ok) {
            return error(res, result.message, result.status, result.code, result.meta);
        }
        return success(res, { checkout_url: result.checkoutUrl });
    } catch (err) {
        if (err instanceof BillingProviderError) {
            return error(res, err.message, 503, err.code);
        }
        return next(err);
    }
});

/**
 * Provider webhook intake.
 *
 * This is the ONLY path that may activate Pro. The frontend success URL
 * cannot: it is a redirect target the user's browser controls, so treating it
 * as proof of payment would let anyone type their way to a subscription.
 *
 * Deliberately unauthenticated in the MedOrbit sense — the sender is a
 * provider, not a user — and therefore authenticated cryptographically
 * instead, over the raw request bytes. An unverified body is rejected before
 * anything is read out of it.
 */
router.post('/webhook', async (req, res) => {
    const result = await subscriptionService.processProviderEvent({
        rawBody: req.rawBody,
        headers: req.headers,
    });

    if (!result.ok) {
        return error(res, 'Webhook rejected', result.status, result.code);
    }
    if (result.duplicate) {
        return success(res, { duplicate: true }, 'Event already processed');
    }
    return success(res, { received: true });
});

// =====================================================================
// Subscription management
//
// Note what none of these accept: a subscription id. Each one loads the
// caller's OWN live subscription from their authenticated user id, so
// "cancel someone else's subscription" is not a request that can be
// expressed, rather than one that is checked and refused.
// =====================================================================

router.get('/subscription', authenticate, async (req, res, next) => {
    try {
        const detail = await subscriptionService.getSubscriptionDetail(req.user.sub);
        return success(res, detail);
    } catch (err) {
        return next(err);
    }
});

/**
 * Cancel — as cancel_at_period_end, always.
 *
 * The subscriber keeps Pro until current_period_end. Immediate destructive
 * cancellation is not offered to ordinary users: it would forfeit access
 * already paid for, and no user asking to "cancel" means "and delete the
 * three weeks I have left".
 */
router.post('/subscription/cancel', authenticate, async (req, res, next) => {
    try {
        const result = await subscriptionService.requestCancellation(req.user.sub);
        if (!result.ok) return error(res, result.message, result.status, result.code);
        return success(res, await subscriptionService.getSubscriptionDetail(req.user.sub));
    } catch (err) {
        return next(err);
    }
});

router.post('/subscription/resume', authenticate, async (req, res, next) => {
    try {
        const result = await subscriptionService.requestResume(req.user.sub);
        if (!result.ok) return error(res, result.message, result.status, result.code);
        return success(res, await subscriptionService.getSubscriptionDetail(req.user.sub));
    } catch (err) {
        return next(err);
    }
});

/**
 * Switch between Monthly and Annual at the next renewal.
 *
 * Takes a plan_code and nothing else. The price difference is never computed
 * here or sent by the client; the change simply takes effect at the boundary
 * where both sides are square.
 */
router.post('/subscription/plan', authenticate, async (req, res, next) => {
    try {
        const planCode = typeof req.body?.plan_code === 'string' ? req.body.plan_code : null;
        if (!planCode) return error(res, 'A plan_code is required', 400, 'VALIDATION_ERROR');

        const result = await subscriptionService.requestPlanChange(req.user.sub, planCode);
        if (!result.ok) return error(res, result.message, result.status, result.code);
        return success(res, await subscriptionService.getSubscriptionDetail(req.user.sub));
    } catch (err) {
        return next(err);
    }
});

/**
 * The account's own billing timeline.
 *
 * Event types and timestamps. Never a provider payload, never a digest,
 * never a signature — and never anything clinical, because billing events
 * do not carry clinical data in the first place.
 */
router.get('/history', authenticate, async (req, res, next) => {
    try {
        const events = await subscriptionService.getBillingHistory(req.user.sub, req.query?.limit);
        return success(res, { events });
    } catch (err) {
        return next(err);
    }
});

// =====================================================================
// Sandbox
//
// Mounted only when BILLING_PROVIDER=mock AND BILLING_MOCK_ENABLED=true AND
// NODE_ENV is not production. In a production process these paths do not
// exist at all and return the ordinary 404 — there is no handler to reach,
// no flag to flip at runtime, and no code path that could be talked into
// granting Pro.
//
// Every route below is additionally guarded per request, so a process whose
// configuration changes under it fails closed rather than staying open on
// the strength of a decision made at boot.
// =====================================================================

const sandbox = express.Router();

/** Per-request re-check. Belt and braces with the mount-time condition. */
function requireSandbox(req, res, next) {
    if (!readProviderConfig().mockEnabled) {
        return error(res, 'Sandbox billing is not enabled.', 404, ERROR_CODES.SANDBOX_DISABLED);
    }
    return next();
}

/**
 * What the sandbox checkout page renders.
 *
 * The plan and price come from the stored attempt joined to the plan
 * catalogue, so the page displays what the backend recorded rather than what
 * a query parameter claims. Scoped to the caller: another account asking for
 * this token gets 404, which is also what a stranger with a leaked URL gets.
 */
sandbox.get('/checkout/:token', authenticate, requireSandbox, async (req, res, next) => {
    try {
        const provider = getProvider();
        const attempt = await billingRepository.findOwnedCheckoutSession(
            provider.name, req.params.token, req.user.sub
        );
        if (!attempt) {
            return error(res, 'Checkout session not found', 404, ERROR_CODES.CHECKOUT_NOT_FOUND);
        }

        return success(res, {
            plan_code: attempt.plan_code,
            name_en: attempt.name_en,
            name_ar: attempt.name_ar,
            price_cents: attempt.price_cents,
            currency: attempt.currency,
            billing_interval: attempt.billing_interval,
            interval_count: attempt.interval_count,
            status: attempt.status,
            is_open: attempt.is_open,
            expires_at: attempt.expires_at,
            return_path: attempt.return_path,
            server_time: attempt.server_now,
            sandbox: true,
        });
    } catch (err) {
        return next(err);
    }
});

/**
 * Resolve a sandbox checkout.
 *
 * This endpoint does not touch the subscriptions table. It asks the mock
 * provider for the event a real provider would have sent, and hands it to
 * the same signed pipeline a real webhook goes through — signature
 * verification, idempotent recording, then the state machine. That
 * indirection is the entire point: the sandbox exercises the production
 * path instead of a shortcut that would have to be deleted in Phase 3.
 */
sandbox.post('/checkout/:token/complete', authenticate, requireSandbox, async (req, res, next) => {
    try {
        // eslint-disable-next-line global-require
        const { checkoutOutcomeEvents, CHECKOUT_OUTCOMES } = require('../services/billing/mock.provider');

        const outcome = typeof req.body?.outcome === 'string' ? req.body.outcome : null;
        if (!CHECKOUT_OUTCOMES.includes(outcome)) {
            return error(res, 'Unknown checkout outcome', 400, 'VALIDATION_ERROR');
        }

        const provider = getProvider();
        const attempt = await billingRepository.findOwnedCheckoutSession(
            provider.name, req.params.token, req.user.sub
        );
        if (!attempt) {
            return error(res, 'Checkout session not found', 404, ERROR_CODES.CHECKOUT_NOT_FOUND);
        }
        if (!attempt.is_open) {
            return error(res, 'This checkout is no longer open', 409, ERROR_CODES.CHECKOUT_NOT_OPEN);
        }

        if (outcome === 'canceled') {
            // A user who backs out of a provider's hosted page generates no
            // provider event, so neither does this. The attempt is simply
            // closed.
            await billingRepository.resolveCheckoutSession(attempt.id, { status: 'canceled' });
            logger.info({ billing_event: 'checkout_canceled', user_id: req.user.sub }, 'billing.checkout_canceled');
        } else {
            await subscriptionService.deliverProviderEvents(
                checkoutOutcomeEvents(attempt.provider_session_id, outcome)
            );
        }

        // Answer from the database, not from what was just requested: the
        // client learns what actually happened.
        const entitlements = await entitlementService.getEntitlementSnapshot(req.user.sub);
        return success(res, {
            outcome,
            return_path: attempt.return_path,
            entitlements,
        });
    } catch (err) {
        return next(err);
    }
});

/**
 * Simulate the things a provider does on its own schedule.
 *
 * Renewal, a declined renewal, a recovered payment, an ended subscription —
 * none of which can be waited for in development. Note what is NOT here:
 * there is no simulation that creates a subscription. Becoming Pro requires
 * a checkout attempt that the backend recorded, so even this developer-only
 * endpoint cannot be used as a "make me Pro" button. It only acts on the
 * caller's own existing subscription, and only through signed events.
 */
sandbox.post('/simulate', authenticate, requireSandbox, async (req, res, next) => {
    try {
        // eslint-disable-next-line global-require
        const { lifecycleEvents, LIFECYCLE_SIMULATIONS } = require('../services/billing/mock.provider');

        const kind = typeof req.body?.kind === 'string' ? req.body.kind : null;
        if (!LIFECYCLE_SIMULATIONS.includes(kind)) {
            return error(res, 'Unknown simulation', 400, 'VALIDATION_ERROR');
        }

        const detail = await subscriptionService.getSubscriptionDetail(req.user.sub);
        if (!detail.status) {
            return error(res, 'No subscription to simulate against', 404, ERROR_CODES.SUBSCRIPTION_NOT_FOUND);
        }

        // The provider subscription id is read from the caller's own row, not
        // from the request, so one account cannot aim a simulation at another.
        const own = await billingRepository.findLiveSubscription(req.user.sub);
        if (!own || !own.provider_subscription_id) {
            return error(res, 'No subscription to simulate against', 404, ERROR_CODES.SUBSCRIPTION_NOT_FOUND);
        }

        await subscriptionService.deliverProviderEvents(
            lifecycleEvents(kind, own.provider_subscription_id)
        );

        return success(res, await subscriptionService.getSubscriptionDetail(req.user.sub));
    } catch (err) {
        return next(err);
    }
});

if (readProviderConfig().mockEnabled) {
    router.use('/sandbox', sandbox);
    logger.warn(
        { billing_event: 'sandbox_enabled' },
        'billing.sandbox_enabled — simulated payments are active. This must never be a production environment.'
    );
}

module.exports = router;

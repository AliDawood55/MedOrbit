const express = require('express');
const crypto = require('crypto');

const { authenticate } = require('../middleware/auth');
const { success, error } = require('../utils/response');
const entitlementService = require('../services/entitlement.service');
const billingRepository = require('../repositories/billing.repository');
const { getProvider, BillingProviderError } = require('../services/billing/provider');
const { ERROR_CODES } = require('../config/billing');
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
 * Begin an upgrade.
 *
 * The client sends a plan_code and nothing else. Any amount, currency or
 * discount in the request body is ignored outright — price is resolved from
 * the plan catalogue server-side, so a tampered request cannot buy Pro for a
 * dollar.
 *
 * Returns 503 until a provider is chosen and approved. That is the honest
 * state of Phase 1, and it is deliberately not stubbed: a fake checkout that
 * appeared to succeed would be a way to obtain Pro without paying.
 */
router.post('/checkout', authenticate, async (req, res, next) => {
    try {
        const planCode = typeof req.body?.plan_code === 'string' ? req.body.plan_code : null;
        if (!planCode) {
            return error(res, 'A plan_code is required', 400, 'VALIDATION_ERROR');
        }

        const plan = await billingRepository.findPlanByCode(planCode);
        if (!plan || !plan.grants_pro) {
            return error(res, 'Unknown or non-purchasable plan', 400, 'VALIDATION_ERROR');
        }

        const provider = getProvider();
        if (!provider.isConfigured) {
            return error(
                res,
                'Payments are not yet available.',
                503,
                ERROR_CODES.ENTITLEMENT_UNAVAILABLE,
                { upgrade_available: false }
            );
        }

        // The opaque handle the provider sees instead of an email or a name.
        const billingReference = `mo_${crypto.randomBytes(16).toString('hex')}`;
        const customer = await billingRepository.getOrCreateBillingCustomer(req.user.sub, billingReference);

        const checkout = await provider.createCheckout({
            userId: req.user.sub,
            planCode: plan.plan_code,
            billingReference: customer.billing_reference,
            successUrl: `${process.env.FRONTEND_URL || ''}/billing.html?state=success`,
            cancelUrl: `${process.env.FRONTEND_URL || ''}/billing.html?state=canceled`,
        });

        return success(res, { checkout_url: checkout.checkoutUrl });
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
    const provider = getProvider();

    let verification;
    try {
        verification = await provider.verifyWebhook({
            rawBody: req.rawBody,
            headers: req.headers,
        });
    } catch (err) {
        logger.warn({ billing_event: 'webhook_verification_error' }, 'billing.webhook_verification_error');
        return error(res, 'Webhook rejected', 400, 'WEBHOOK_REJECTED');
    }

    if (!verification || !verification.verified) {
        // No detail in the response: a precise reason would help an attacker
        // iterate toward a forged signature.
        logger.warn({ billing_event: 'webhook_failed', reason: 'unverified' }, 'billing.webhook_failed');
        return error(res, 'Webhook rejected', 400, 'WEBHOOK_REJECTED');
    }

    try {
        const digest = req.rawBody
            ? crypto.createHash('sha256').update(req.rawBody).digest('hex')
            : null;

        // Returns null when this provider_event_id was already recorded, which
        // is how replayed deliveries become no-ops instead of double-applying.
        const recorded = await billingRepository.recordProviderEvent({
            provider: provider.name,
            providerEventId: verification.eventId,
            eventType: verification.eventType,
            eventCreatedAt: verification.eventCreatedAt,
            payloadDigest: digest,
        });

        if (!recorded) {
            return success(res, { duplicate: true }, 'Event already processed');
        }

        // Subscription state transitions land here once a provider exists.
        // Until then the event is durably recorded and left unprocessed, so
        // nothing is lost and nothing is invented.
        await billingRepository.markEventProcessed(recorded.id, { status: 'ignored' });
        return success(res, { received: true });
    } catch (err) {
        logger.error({ billing_event: 'webhook_failed', reason: 'persistence' }, 'billing.webhook_failed');
        return error(res, 'Webhook processing failed', 500, 'WEBHOOK_FAILED');
    }
});

module.exports = router;

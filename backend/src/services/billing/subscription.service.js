const crypto = require('crypto');

const db = require('../../config/database');
const logger = require('../../utils/logger');
const billingRepository = require('../../repositories/billing.repository');
const { getProvider, BillingProviderError } = require('./provider');
const { BILLING_EVENTS, ERROR_CODES, PLAN_CODES, policy } = require('../../config/billing');

/**
 * SubscriptionService — the subscription state machine, and the only code
 * permitted to change what a user is entitled to.
 *
 * Two invariants shape everything below.
 *
 * First, a subscription changes state because a *verified provider event*
 * said so. Not because a browser returned to a success URL, not because a
 * button was clicked, not because a checkout session was created. The
 * frontend can start a checkout and it can ask a provider to cancel, but
 * the state change always arrives afterwards, asynchronously, over a signed
 * channel. That ordering is why the sandbox is worth having: it is the same
 * ordering a real provider forces, so nothing has to be rewritten later.
 *
 * Second, time comes from PostgreSQL. Every period boundary and grace
 * deadline in this file is computed by the database in calendar units, so a
 * subscription bought on 31 January renews on 28 February rather than on a
 * date arrived at by multiplying 86400.
 *
 * Nothing here reads, writes, or forwards medical content. A subscription
 * knows a user id, a plan code and a set of timestamps.
 */

/** Structured billing telemetry: identifiers, codes and counts only. */
function emit(event, fields) {
    // Never a payload, never a signature, never a token, never medical
    // content. Provider payloads in particular are excluded on purpose —
    // they are the one thing in this flow that could carry personal data.
    logger.info({ billing_event: event, ...fields }, `billing.${event}`);
}

/**
 * How long a checkout attempt stays open.
 *
 * Long enough to read a page and decide, short enough that an abandoned
 * attempt does not sit around as a token someone could return to much
 * later.
 */
const CHECKOUT_TTL_MINUTES = 60;

// ---------------------------------------------------------------------
// Lazy reconciliation
// ---------------------------------------------------------------------

/**
 * Retire subscriptions whose time has simply run out.
 *
 * The statement lives in the repository beside the voice-grant sweep, so the
 * entitlement snapshot can run the same reconciliation without this service
 * and that one importing each other. Kept re-exported here because the
 * lifecycle handlers below all sweep before they read.
 */
async function expireLapsedSubscriptions(client, userId) {
    const rows = await billingRepository.expireLapsedSubscriptions(client, userId);
    if (rows.length > 0) {
        emit('subscription_lapsed', { user_id: userId, count: rows.length });
    }
    return rows;
}

// ---------------------------------------------------------------------
// Checkout
// ---------------------------------------------------------------------

/**
 * Only same-origin relative paths may be returned to after checkout.
 *
 * A return target that survives a round trip through the user's browser is
 * an open-redirect waiting to happen, so anything absolute, protocol-
 * relative, or backslash-smuggled is discarded rather than sanitised. The
 * value is also stored server-side against the attempt, so what comes back
 * from the browser is never what decides where the user lands.
 */
function safeReturnPath(value) {
    if (typeof value !== 'string' || !value) return null;
    if (value.length > 200) return null;
    if (!/^[A-Za-z0-9._~\-/?=&#%]+$/.test(value)) return null;
    if (value.startsWith('//') || value.startsWith('/\\')) return null;
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) return null;
    return value.startsWith('/') ? value.slice(1) : value;
}

/**
 * Begin an upgrade.
 *
 * The client sends a plan_code and a return path. It does not send a price,
 * an amount, a currency, a status or an is_pro flag — and if it does, those
 * fields are never read. Price is resolved from the plan catalogue here,
 * server-side, which is what makes "user tampers with amount" a non-event
 * rather than a vulnerability to defend against.
 *
 * @returns {{ok: boolean, checkoutUrl?: string, code?: string, status?: number}}
 */
async function createCheckout({ userId, planCode, returnPath = null }) {
    const plan = await billingRepository.findPlanByCode(planCode);
    if (!plan || !plan.grants_pro) {
        return { ok: false, status: 400, code: 'VALIDATION_ERROR', message: 'Unknown or non-purchasable plan' };
    }

    const provider = getProvider();
    if (!provider.isConfigured) {
        return {
            ok: false,
            status: 503,
            code: ERROR_CODES.ENTITLEMENT_UNAVAILABLE,
            message: 'Payments are not yet available.',
            meta: { upgrade_available: false },
        };
    }

    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        await billingRepository.lockUserFeature(client, userId, 'subscription');
        await expireLapsedSubscriptions(client, userId);

        // Buying a second subscription while one is live would create two
        // overlapping paid periods for one account. The partial unique index
        // would reject it anyway; refusing here turns a 500 into an answer.
        const live = await billingRepository.findLiveSubscriptionForUpdate(client, userId);
        if (live) {
            await client.query('COMMIT');
            return {
                ok: false,
                status: 409,
                code: ERROR_CODES.SUBSCRIPTION_ALREADY_LIVE,
                message: 'This account already has a subscription.',
            };
        }

        // The opaque handle the provider sees instead of an email or a name.
        const billingReference = `mo_${crypto.randomBytes(16).toString('hex')}`;
        const customer = await billingRepository.getOrCreateBillingCustomer(userId, billingReference, client);

        const checkout = await provider.createCheckout({
            userId,
            planCode: plan.plan_code,
            billingReference: customer.billing_reference,
            successUrl: `${process.env.FRONTEND_URL || ''}/billing.html?state=success`,
            cancelUrl: `${process.env.FRONTEND_URL || ''}/billing.html?state=canceled`,
        });

        await billingRepository.createCheckoutSession({
            userId,
            planId: plan.id,
            provider: provider.name,
            providerSessionId: checkout.providerSessionId,
            returnPath: safeReturnPath(returnPath),
            ttlMinutes: CHECKOUT_TTL_MINUTES,
        }, client);

        await client.query('COMMIT');

        emit('checkout_created', { user_id: userId, plan_code: plan.plan_code, provider: provider.name });
        return { ok: true, checkoutUrl: checkout.checkoutUrl, providerSessionId: checkout.providerSessionId };
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

// ---------------------------------------------------------------------
// Event pipeline
// ---------------------------------------------------------------------

/**
 * Handlers for the canonical event vocabulary.
 *
 * Each returns {status, subscriptionId, userId}. 'processed' means the event
 * changed something; 'ignored' means it was understood but had no effect —
 * an event about a subscription we do not have, or a transition that had
 * already happened. Neither is an error, and both are recorded, because the
 * difference between "we ignored this" and "we never saw this" is the whole
 * value of the events table during reconciliation.
 */
const handlers = {

    /**
     * A checkout attempt succeeded.
     *
     * The plan comes from the stored attempt, never from the event payload
     * and never from the returning browser. Even a forged-but-somehow-signed
     * event cannot buy a different plan than the one the attempt recorded.
     */
    async [BILLING_EVENTS.CHECKOUT_COMPLETED](client, data) {
        const provider = getProvider();
        const attempt = await billingRepository.findCheckoutSessionByProviderId(
            provider.name, data.checkout_session_id, client
        );
        if (!attempt) return { status: 'ignored' };

        // Already resolved: a redelivery, or the user clicking twice. The
        // subscription it produced is returned so the caller still gets a
        // useful answer, but nothing is created a second time.
        if (attempt.status !== 'open') {
            return { status: 'ignored', subscriptionId: attempt.subscription_id, userId: attempt.user_id };
        }

        await billingRepository.lockUserFeature(client, attempt.user_id, 'subscription');
        await expireLapsedSubscriptions(client, attempt.user_id);

        const live = await billingRepository.findLiveSubscriptionForUpdate(client, attempt.user_id);
        if (live) {
            // Two attempts completed for one account. The first one wins; the
            // second is closed without creating an overlapping subscription.
            await billingRepository.resolveCheckoutSession(attempt.id, { status: 'failed' }, client);
            return { status: 'ignored', subscriptionId: live.id, userId: attempt.user_id };
        }

        const subscription = await billingRepository.activateSubscription(client, {
            userId: attempt.user_id,
            planId: attempt.plan_id,
            provider: provider.name,
            providerSubscriptionId: data.provider_subscription_id || `sub_${attempt.provider_session_id}`,
        });
        if (!subscription) return { status: 'failed', userId: attempt.user_id };

        await billingRepository.resolveCheckoutSession(
            attempt.id, { status: 'completed', subscriptionId: subscription.id }, client
        );

        emit('subscription_activated', {
            user_id: attempt.user_id,
            plan_code: attempt.plan_code,
            subscription_id: subscription.id,
        });
        return { status: 'processed', subscriptionId: subscription.id, userId: attempt.user_id };
    },

    /**
     * Some providers separate "checkout finished" from "subscription live".
     * Supported so that ordering is a provider detail rather than something
     * MedOrbit assumes.
     */
    async [BILLING_EVENTS.SUBSCRIPTION_ACTIVATED](client, data) {
        const provider = getProvider();
        const existing = await billingRepository.findSubscriptionByProviderId(
            provider.name, data.provider_subscription_id, client
        );
        if (existing) {
            return { status: 'ignored', subscriptionId: existing.id, userId: existing.user_id };
        }
        return handlers[BILLING_EVENTS.CHECKOUT_COMPLETED](client, data);
    },

    /** A renewal was paid. The period advances and any scheduled plan change lands. */
    async [BILLING_EVENTS.SUBSCRIPTION_RENEWED](client, data) {
        const provider = getProvider();
        const subscription = await billingRepository.findSubscriptionByProviderId(
            provider.name, data.provider_subscription_id, client
        );
        if (!subscription) return { status: 'ignored' };

        await billingRepository.lockUserFeature(client, subscription.user_id, 'subscription');

        // A subscription the user asked to end does not renew. Its period
        // running out is a cancellation, handled by the lapse sweep.
        if (subscription.cancel_at_period_end) {
            return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };
        }

        const renewed = await billingRepository.renewSubscription(client, subscription.id);
        if (!renewed) return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };

        emit('subscription_renewed', {
            user_id: renewed.user_id,
            subscription_id: renewed.id,
            period_end: renewed.current_period_end,
        });
        return { status: 'processed', subscriptionId: renewed.id, userId: renewed.user_id };
    },

    /**
     * A payment failed.
     *
     * The single most important distinction in this file lives here. A failed
     * RENEWAL belongs to somebody who has already paid, and they get a grace
     * window rather than an interruption. A failed FIRST payment belongs to
     * somebody who has never paid, and grace would mean a week of Pro for
     * free, repeatable forever with a fresh checkout. So the initial case
     * closes the attempt and creates nothing.
     */
    async [BILLING_EVENTS.PAYMENT_FAILED](client, data) {
        const provider = getProvider();

        if (data.checkout_session_id) {
            const attempt = await billingRepository.findCheckoutSessionByProviderId(
                provider.name, data.checkout_session_id, client
            );
            if (!attempt) return { status: 'ignored' };
            if (attempt.status !== 'open') {
                return { status: 'ignored', userId: attempt.user_id };
            }

            await billingRepository.resolveCheckoutSession(attempt.id, { status: 'failed' }, client);
            emit('checkout_payment_failed', { user_id: attempt.user_id, plan_code: attempt.plan_code });
            // No subscription row, no grace, no entitlement. The user stays
            // Free and may try again.
            return { status: 'processed', userId: attempt.user_id };
        }

        const subscription = await billingRepository.findSubscriptionByProviderId(
            provider.name, data.provider_subscription_id, client
        );
        if (!subscription) return { status: 'ignored' };

        await billingRepository.lockUserFeature(client, subscription.user_id, 'subscription');

        // markPastDue only matches status='active', so an 'incomplete' row
        // cannot be talked into a grace window from here either.
        const pastDue = await billingRepository.markPastDue(
            client, subscription.id, policy.subscription.pastDueGraceDays
        );
        if (!pastDue) return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };

        emit('subscription_past_due', {
            user_id: pastDue.user_id,
            subscription_id: pastDue.id,
            grace_ends_at: pastDue.grace_period_ends_at,
        });
        return { status: 'processed', subscriptionId: pastDue.id, userId: pastDue.user_id };
    },

    /** The retried payment succeeded. Grace is cleared and the warning state ends. */
    async [BILLING_EVENTS.PAYMENT_RECOVERED](client, data) {
        const provider = getProvider();
        const subscription = await billingRepository.findSubscriptionByProviderId(
            provider.name, data.provider_subscription_id, client
        );
        if (!subscription) return { status: 'ignored' };

        await billingRepository.lockUserFeature(client, subscription.user_id, 'subscription');
        const recovered = await billingRepository.recoverPayment(client, subscription.id);
        if (!recovered) return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };

        emit('subscription_recovered', { user_id: recovered.user_id, subscription_id: recovered.id });
        return { status: 'processed', subscriptionId: recovered.id, userId: recovered.user_id };
    },

    /** Auto-renew switched off or back on. Paid access is untouched either way. */
    async [BILLING_EVENTS.SUBSCRIPTION_CANCEL_AT_PERIOD_END](client, data) {
        const provider = getProvider();
        const subscription = await billingRepository.findSubscriptionByProviderId(
            provider.name, data.provider_subscription_id, client
        );
        if (!subscription) return { status: 'ignored' };

        await billingRepository.lockUserFeature(client, subscription.user_id, 'subscription');
        const updated = await billingRepository.setCancelAtPeriodEnd(
            client, subscription.id, data.cancel_at_period_end !== false
        );
        if (!updated) return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };

        emit(updated.cancel_at_period_end ? 'subscription_cancel_scheduled' : 'subscription_resumed', {
            user_id: updated.user_id,
            subscription_id: updated.id,
            period_end: updated.current_period_end,
        });
        return { status: 'processed', subscriptionId: updated.id, userId: updated.user_id };
    },

    /** A scheduled plan change. Takes effect at the next renewal, never mid-period. */
    async [BILLING_EVENTS.SUBSCRIPTION_UPDATED](client, data) {
        const provider = getProvider();
        const subscription = await billingRepository.findSubscriptionByProviderId(
            provider.name, data.provider_subscription_id, client
        );
        if (!subscription) return { status: 'ignored' };

        const plan = data.pending_plan_code
            ? await billingRepository.findPlanByCode(data.pending_plan_code)
            : null;
        if (!plan || !plan.grants_pro) {
            return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };
        }

        await billingRepository.lockUserFeature(client, subscription.user_id, 'subscription');
        const updated = await billingRepository.setPendingPlan(client, subscription.id, plan.id);
        if (!updated) return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };

        emit('subscription_plan_change_scheduled', {
            user_id: updated.user_id,
            subscription_id: updated.id,
            pending_plan_code: plan.plan_code,
            effective_at: updated.current_period_end,
        });
        return { status: 'processed', subscriptionId: updated.id, userId: updated.user_id };
    },

    /**
     * The subscription has ended.
     *
     * Entitlement stops here and nothing else does. No chat message, voice
     * consultation, report, medical record or usage row is touched by this
     * handler — it updates one row in one billing table. Downgrade is a
     * change of permission, never a deletion of what somebody produced.
     */
    async [BILLING_EVENTS.SUBSCRIPTION_CANCELED](client, data) {
        const provider = getProvider();
        const subscription = await billingRepository.findSubscriptionByProviderId(
            provider.name, data.provider_subscription_id, client
        );
        if (!subscription) return { status: 'ignored' };

        await billingRepository.lockUserFeature(client, subscription.user_id, 'subscription');
        const ended = await billingRepository.terminateSubscription(client, subscription.id, 'canceled');
        if (!ended) return { status: 'ignored', subscriptionId: subscription.id, userId: subscription.user_id };

        emit('subscription_ended', { user_id: ended.user_id, subscription_id: ended.id });
        return { status: 'processed', subscriptionId: ended.id, userId: ended.user_id };
    },
};

/**
 * The single entry point for provider events, however they arrive.
 *
 * Verification happens over the raw bytes before one field is read out of
 * the payload, recording happens before dispatch, and both live in the same
 * transaction as the state change. That last part matters: if a handler
 * throws, the event record rolls back with it, so the provider's retry finds
 * no record and genuinely re-applies rather than being deduplicated into
 * silence by a half-finished attempt.
 */
async function processProviderEvent({ rawBody, headers }) {
    const provider = getProvider();

    let verification;
    try {
        verification = await provider.verifyWebhook({ rawBody, headers });
    } catch (err) {
        emit('webhook_verification_error', { provider: provider.name });
        return { ok: false, status: 400, code: 'WEBHOOK_REJECTED' };
    }

    if (!verification || !verification.verified) {
        // No detail in the response: a precise reason would help an attacker
        // iterate toward a forged signature.
        emit('webhook_failed', { provider: provider.name, reason: 'unverified' });
        return { ok: false, status: 400, code: 'WEBHOOK_REJECTED' };
    }

    const digest = rawBody ? crypto.createHash('sha256').update(rawBody).digest('hex') : null;

    const client = await db.getClient();
    try {
        await client.query('BEGIN');

        const recorded = await billingRepository.recordProviderEvent({
            provider: provider.name,
            providerEventId: verification.eventId,
            eventType: verification.eventType,
            eventCreatedAt: verification.eventCreatedAt,
            payloadDigest: digest,
        }, client);

        // Already seen. This is the replay guarantee, and it is a unique
        // index rather than anything held in process memory, so it survives
        // restarts and holds across every backend instance.
        if (!recorded) {
            await client.query('COMMIT');
            emit('webhook_duplicate', { provider: provider.name, event_type: verification.eventType });
            return { ok: true, duplicate: true };
        }

        const handler = handlers[verification.eventType];
        if (!handler) {
            await billingRepository.markEventProcessed(recorded.id, { status: 'ignored' }, client);
            await client.query('COMMIT');
            emit('webhook_unhandled', { provider: provider.name, event_type: verification.eventType });
            return { ok: true, handled: false };
        }

        const outcome = await handler(client, verification.data || {});

        await billingRepository.markEventProcessed(recorded.id, {
            status: outcome.status,
            subscriptionId: outcome.subscriptionId || null,
        }, client);

        if (outcome.userId) {
            await billingRepository.attachEventOwner(recorded.id, outcome.userId, client);
        }

        await client.query('COMMIT');
        return { ok: true, handled: true, outcome: outcome.status, subscriptionId: outcome.subscriptionId || null };
    } catch (err) {
        await client.query('ROLLBACK');
        // SQLSTATE and constraint name, never the message and never the
        // payload: enough to diagnose which invariant refused the write,
        // without copying provider data into a log line.
        emit('webhook_failed', {
            provider: provider.name,
            reason: 'processing',
            sqlstate: err?.code || null,
            constraint: err?.constraint || null,
        });
        return { ok: false, status: 500, code: 'WEBHOOK_FAILED' };
    } finally {
        client.release();
    }
}

/**
 * Deliver an event a provider adapter produced locally.
 *
 * Sandbox events are signed and then verified exactly like a delivery over
 * the network — the sandbox gets no shortcut past signature verification.
 * That is deliberate: it means the verification path is exercised on every
 * simulated payment during development, rather than being code nobody runs
 * until a real provider is connected.
 */
async function deliverProviderEvents(events) {
    const provider = getProvider();
    if (!Array.isArray(events) || events.length === 0) return [];
    if (typeof provider.signPayload !== 'function') return [];

    const results = [];
    for (const envelope of events) {
        const rawBody = Buffer.from(JSON.stringify(envelope), 'utf8');
        results.push(await processProviderEvent({ rawBody, headers: provider.signPayload(rawBody) }));
    }
    return results;
}

// ---------------------------------------------------------------------
// Subscriber-initiated operations
// ---------------------------------------------------------------------

/**
 * Ask the provider to stop auto-renew, then apply whatever it tells us.
 *
 * The local row is not edited directly. The provider is asked first and the
 * change is applied from the event it returns, because that is the only
 * ordering that stays correct when the provider is real and can refuse.
 */
async function requestCancellation(userId) {
    return providerSubscriptionAction(userId, async (provider, subscription) => {
        const result = await provider.cancelSubscription({
            providerSubscriptionId: subscription.provider_subscription_id,
            atPeriodEnd: true,
        });
        return result?.events || [];
    });
}

async function requestResume(userId) {
    return providerSubscriptionAction(userId, async (provider, subscription) => {
        if (!subscription.cancel_at_period_end) {
            return [];
        }
        const result = await provider.resumeSubscription({
            providerSubscriptionId: subscription.provider_subscription_id,
        });
        return result?.events || [];
    });
}

/**
 * Change between Monthly and Annual, effective at the next renewal.
 *
 * Deliberately not immediate. Switching mid-period is a proration decision —
 * how much of the unused month is worth in annual credit — and proration is
 * a financial policy that belongs to a real provider with real money, not
 * to a sandbox inventing an answer. Deferring to the renewal boundary is the
 * one option that is exactly fair to both sides without inventing anything.
 */
async function requestPlanChange(userId, planCode) {
    const plan = await billingRepository.findPlanByCode(planCode);
    if (!plan || !plan.grants_pro) {
        return { ok: false, status: 400, code: ERROR_CODES.PLAN_CHANGE_INVALID, message: 'Unknown or non-purchasable plan' };
    }

    return providerSubscriptionAction(userId, async (provider, subscription) => {
        if (subscription.plan_code === plan.plan_code) return [];
        if (subscription.cancel_at_period_end) {
            const err = new BillingProviderError(
                'Resume the subscription before changing plan.',
                ERROR_CODES.PLAN_CHANGE_INVALID
            );
            err.httpStatus = 409;
            throw err;
        }
        const result = await provider.updateSubscription({
            providerSubscriptionId: subscription.provider_subscription_id,
            planCode: plan.plan_code,
        });
        return result?.events || [];
    });
}

/**
 * Shared shape for the three subscriber-initiated operations.
 *
 * Loads the caller's OWN live subscription — the id is never taken from the
 * request — asks the provider to do the thing, then applies the resulting
 * events. There is consequently no endpoint anywhere that accepts a
 * subscription id, which is what makes "user A cancels user B" unexpressible
 * rather than merely forbidden.
 */
async function providerSubscriptionAction(userId, action) {
    const provider = getProvider();
    if (!provider.isConfigured) {
        return { ok: false, status: 503, code: ERROR_CODES.ENTITLEMENT_UNAVAILABLE, message: 'Billing is unavailable.' };
    }

    const client = await db.getClient();
    let subscription;
    try {
        await client.query('BEGIN');
        await expireLapsedSubscriptions(client, userId);
        subscription = await billingRepository.findLiveSubscriptionForUpdate(client, userId);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }

    if (!subscription) {
        return { ok: false, status: 404, code: ERROR_CODES.SUBSCRIPTION_NOT_FOUND, message: 'No active subscription.' };
    }

    let events;
    try {
        events = await action(provider, subscription);
    } catch (err) {
        if (err instanceof BillingProviderError) {
            return { ok: false, status: err.httpStatus || 503, code: err.code, message: err.message };
        }
        throw err;
    }

    await deliverProviderEvents(events);
    return { ok: true };
}

// ---------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------

/**
 * The billing page's view of an account.
 *
 * Sweeps lapsed rows first so the page never advertises a subscription that
 * has quietly stopped granting anything.
 */
async function getSubscriptionDetail(userId) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        await expireLapsedSubscriptions(client, userId);
        await billingRepository.expireOpenCheckoutSessions(userId, client);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }

    const detail = await billingRepository.findSubscriptionDetail(userId);
    if (!detail) {
        const now = await billingRepository.serverNow();
        return { plan_code: PLAN_CODES.FREE, status: null, server_time: now };
    }

    return {
        plan_code: detail.plan_code,
        plan_name_en: detail.name_en,
        plan_name_ar: detail.name_ar,
        price_cents: detail.price_cents,
        currency: detail.currency,
        billing_interval: detail.billing_interval,
        interval_count: detail.interval_count,
        status: detail.status,
        cancel_at_period_end: detail.cancel_at_period_end,
        current_period_start: detail.current_period_start,
        current_period_end: detail.current_period_end,
        grace_period_ends_at: detail.grace_period_ends_at,
        ended_at: detail.ended_at,
        pending_plan: detail.pending_plan_code
            ? {
                plan_code: detail.pending_plan_code,
                name_en: detail.pending_name_en,
                name_ar: detail.pending_name_ar,
                price_cents: detail.pending_price_cents,
                billing_interval: detail.pending_billing_interval,
                effective_at: detail.current_period_end,
            }
            : null,
        server_time: detail.server_now,
    };
}

/**
 * A readable account history.
 *
 * Event types and timestamps only. The provider payload never leaves the
 * server, and neither does the digest — the user learns that a renewal
 * failed on a date, which is what they actually need, without MedOrbit
 * republishing whatever a provider chose to put in a webhook body.
 */
async function getBillingHistory(userId, limit = 50) {
    const rows = await billingRepository.listBillingHistory(userId, limit);
    return rows.map((row) => ({
        event_type: row.event_type,
        occurred_at: row.received_at,
    }));
}

module.exports = {
    createCheckout,
    processProviderEvent,
    deliverProviderEvents,
    requestCancellation,
    requestResume,
    requestPlanChange,
    getSubscriptionDetail,
    getBillingHistory,
    expireLapsedSubscriptions,
    safeReturnPath,
    CHECKOUT_TTL_MINUTES,
};

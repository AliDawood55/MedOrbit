const db = require('../config/database');
const logger = require('../utils/logger');
const billingRepository = require('../repositories/billing.repository');
const { FEATURES, PLAN_CODES, ERROR_CODES, policy, isProGrantingStatus } = require('../config/billing');

/**
 * EntitlementService — the one place that decides whether a user may use a
 * paid-tier AI feature.
 *
 * Chatbot, Voice Doctor and any future premium feature all route through this
 * module. Nothing else in the codebase is permitted to check a quota, read a
 * subscription status, or decide what "Pro" means; features ask, this answers.
 * That is the entire point — a quota check duplicated inside a feature is a
 * quota check that will drift from the others and eventually disagree.
 *
 * Entitlement is keyed on user_id and never on role. A patient, a doctor, an
 * admin and a super_admin are all subject to the same subscription rules.
 * Role authorization is a separate concern handled by middleware/auth.js, and
 * deliberately does not leak into billing: an admin is an administrator of the
 * platform, not a Pro subscriber, unless they actually hold a subscription.
 */

/** Structured billing telemetry. Carries identifiers and status only. */
function emit(event, fields) {
    // Never medical content, never tokens, never card data. The fields below
    // are the complete permitted vocabulary for billing logs: internal ids,
    // plan/feature codes, counts and timestamps.
    logger.info({ billing_event: event, ...fields }, `billing.${event}`);
}

/**
 * Resolve what a user is entitled to, right now, from the database.
 *
 * `serverNow` comes back from the same query that read the subscription, so
 * every downstream comparison uses one authoritative database instant.
 */
async function resolveEntitlement(userId, client = db) {
    const subscription = await billingRepository.findLiveSubscription(userId, client);
    const serverNow = subscription
        ? new Date(subscription.server_now)
        : new Date(await billingRepository.serverNow(client));

    const isPro = Boolean(subscription)
        && subscription.grants_pro
        && isProGrantingStatus(subscription, serverNow);

    return {
        isPro,
        source: isPro ? 'pro' : 'free',
        planCode: isPro ? subscription.plan_code : PLAN_CODES.FREE,
        subscription: subscription || null,
        serverNow,
    };
}

// ---------------------------------------------------------------------
// Chatbot quota
// ---------------------------------------------------------------------

/**
 * Reserve one chatbot message before the AI is called.
 *
 * Ordering matters and is not arbitrary. The reservation is taken first so
 * that N concurrent requests cannot all observe "19 used" and then all be
 * accepted; taking it afterwards would make the limit advisory. But it is a
 * *reservation*, not a charge, so a failing AI call can hand it back
 * (see settleChatbotMessage) instead of silently costing the user a message.
 *
 * @returns {{allowed: boolean, ledgerId?: string, replay?: boolean, code?: string, meta?: object}}
 */
async function reserveChatbotMessage({ userId, clientRequestId = null, conversationId = null }) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        await billingRepository.lockUserFeature(client, userId, FEATURES.CHATBOT_MESSAGE);

        const entitlement = await resolveEntitlement(userId, client);

        const result = await billingRepository.reserveMeteredUnit(client, {
            userId,
            featureCode: FEATURES.CHATBOT_MESSAGE,
            clientRequestId,
            limit: policy.chatbot.freeMessagesPerWindow,
            windowHours: policy.chatbot.windowHours,
            entitlementSource: entitlement.source,
            referenceId: conversationId,
            inFlightSeconds: policy.idempotency.inFlightSeconds,
        });

        if (result.outcome === 'replay') {
            await client.query('COMMIT');
            // The same message, already answered and already charged. The
            // caller serves the stored reply; the AI is not called again.
            return {
                allowed: true,
                replay: true,
                ledgerId: result.ledger.id,
                alreadySettled: true,
                source: result.ledger.entitlement_source,
            };
        }

        if (result.outcome === 'in_flight') {
            await client.query('COMMIT');
            // A duplicate arriving while the original is still running. It is
            // refused rather than processed: running it would call the AI a
            // second time for one logical message and charge for neither,
            // which turns a retry storm into free capacity.
            return {
                allowed: false,
                code: ERROR_CODES.DUPLICATE_IN_FLIGHT,
                meta: { retry_after_seconds: 2 },
            };
        }

        if (result.outcome === 'denied') {
            await client.query('COMMIT');
            emit('quota_exhausted', {
                user_id: userId,
                feature: FEATURES.CHATBOT_MESSAGE,
                limit: result.limit,
                resets_at: result.resetsAt,
            });
            return {
                allowed: false,
                code: ERROR_CODES.FREE_QUOTA_EXHAUSTED,
                meta: {
                    used: result.used,
                    limit: result.limit,
                    remaining: 0,
                    resets_at: result.resetsAt,
                    upgrade_available: true,
                },
            };
        }

        await client.query('COMMIT');
        return {
            allowed: true,
            replay: false,
            ledgerId: result.ledger.id,
            source: entitlement.source,
            meta: {
                used: result.used,
                limit: entitlement.isPro ? null : result.limit,
                remaining: entitlement.isPro ? null : Math.max(result.limit - result.used, 0),
                resets_at: result.resetsAt,
            },
        };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

/**
 * Settle a reservation once the AI call has resolved.
 *
 * 'consumed' on success, 'released' on failure. Releasing is what prevents the
 * "AI crashed, user permanently loses a message" failure mode.
 */
async function settleChatbotMessage(ledgerId, outcome, referenceId = null) {
    if (!ledgerId) return null;
    return outcome === 'consumed'
        ? billingRepository.consumeReservation(ledgerId, db, referenceId)
        : billingRepository.releaseReservation(ledgerId);
}

/**
 * The reservation a previous identical request produced, if any.
 *
 * Used to answer a replay from what was already computed rather than by
 * calling the AI a second time.
 */
async function findSettledRequest(userId, clientRequestId) {
    const client = await db.getClient();
    try {
        return await billingRepository.findLedgerEntryByRequestId(
            client, userId, FEATURES.CHATBOT_MESSAGE, clientRequestId
        );
    } finally {
        client.release();
    }
}

// ---------------------------------------------------------------------
// Voice consultation lifecycle
// ---------------------------------------------------------------------

/**
 * Decide whether a user may begin (or rejoin) a voice consultation.
 *
 * Resume is checked before eligibility, and that ordering is the whole
 * defence against a page refresh costing someone their free consultation: an
 * existing active grant is returned as-is, so a refresh, a dropped socket, a
 * retried request and an accidental double /start all converge on the same
 * session rather than each reserving a new one.
 *
 * @returns {{allowed: boolean, resumed?: boolean, grant?: object, code?: string, meta?: object}}
 */
async function startVoiceSession(userId) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        await billingRepository.lockUserFeature(client, userId, FEATURES.VOICE_CONSULTATION);

        // Finalize anything abandoned before judging eligibility, so a stale
        // session from yesterday cannot masquerade as "still active" and block
        // a user out of the feature forever.
        const expired = await billingRepository.expireStaleGrants(client, userId, {
            idleTimeoutMinutes: policy.voice.idleTimeoutMinutes,
            cooldownHours: policy.voice.cooldownHours,
        });
        for (const grant of expired) {
            emit('voice_session_expired', {
                user_id: userId,
                grant_id: grant.id,
                source: grant.entitlement_source,
                next_free_at: grant.next_free_at,
            });
        }

        const active = await billingRepository.findActiveGrant(client, userId);
        if (active) {
            await client.query('COMMIT');
            return { allowed: true, resumed: true, grant: active, source: active.entitlement_source };
        }

        const entitlement = await resolveEntitlement(userId, client);

        if (!entitlement.isPro) {
            const cooldown = await billingRepository.findActiveCooldown(client, userId);
            if (cooldown) {
                await client.query('COMMIT');
                emit('entitlement_denied', {
                    user_id: userId,
                    feature: FEATURES.VOICE_CONSULTATION,
                    reason: ERROR_CODES.VOICE_COOLDOWN,
                    next_free_at: cooldown.next_free_at,
                });
                return {
                    allowed: false,
                    code: ERROR_CODES.VOICE_COOLDOWN,
                    meta: {
                        next_free_at: cooldown.next_free_at,
                        upgrade_available: true,
                    },
                };
            }
        }

        let grant;
        try {
            grant = await billingRepository.createGrant(client, {
                userId,
                entitlementSource: entitlement.source,
                maxLifetimeMinutes: policy.voice.maxLifetimeMinutes,
            });
        } catch (err) {
            // The partial unique index on (user_id) WHERE status='active'
            // fired: another request won the race between our read and our
            // insert. That is precisely the duplicate-/start case, so treat it
            // as a resume rather than an error.
            if (err.code === '23505') {
                await client.query('ROLLBACK');
                await client.query('BEGIN');
                const raced = await billingRepository.findActiveGrant(client, userId);
                await client.query('COMMIT');
                if (raced) {
                    return { allowed: true, resumed: true, grant: raced, source: raced.entitlement_source };
                }
                return { allowed: false, code: ERROR_CODES.ENTITLEMENT_UNAVAILABLE, meta: {} };
            }
            throw err;
        }

        await client.query('COMMIT');
        emit('voice_session_granted', {
            user_id: userId,
            grant_id: grant.id,
            source: grant.entitlement_source,
            expires_at: grant.expires_at,
        });
        return { allowed: true, resumed: false, grant, source: grant.entitlement_source };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

/** Bind a reserved grant to the consultation the AI service created for it. */
async function attachVoiceSession(grantId, vdSessionId) {
    return billingRepository.attachSessionToGrant(db, grantId, vdSessionId);
}

/**
 * Release a grant that was reserved but never became a consultation.
 *
 * Needed because the grant is created before the AI service is called — if
 * that call then fails, the user is holding an active grant for a session that
 * does not exist. Releasing it as 'abandoned' WITHOUT a cooldown is the honest
 * outcome: they never received the consultation, so charging them a free
 * session and 24 hours for an outage on our side would be wrong.
 */
async function releaseUnusedGrant(grantId) {
    const result = await db.query(
        `UPDATE medorbit.voice_session_grants
            SET status = 'abandoned', finalized_at = NOW(), next_free_at = NULL, updated_at = NOW()
          WHERE id = $1 AND status = 'active' AND vd_session_id IS NULL
          RETURNING *`,
        [grantId]
    );
    const row = result.rows[0] || null;
    if (row) {
        emit('voice_session_released', { user_id: row.user_id, grant_id: row.id, source: row.entitlement_source });
    }
    return row;
}

/**
 * Wait for an in-flight /start to publish its consultation id.
 *
 * The grant is deliberately created BEFORE the AI service is called, so that
 * it holds the one-active-session slot and a burst of requests cannot each
 * reserve their own free consultation. The consequence is a brief window where
 * a concurrent request sees an active grant whose vd_session_id is still null
 * because the first request is still waiting on the AI service.
 *
 * Without this wait, that second request would conclude there was nothing to
 * resume and start a SECOND upstream consultation — which is exactly the
 * double-tap bug the grant was meant to prevent. Polling briefly lets both
 * requests converge on the one session instead.
 *
 * Bounded: if the first request died, this gives up rather than hanging, and
 * the caller reports that the consultation is still starting.
 */
async function awaitSessionAttachment(grantId, { timeoutMs = 8000, intervalMs = 150 } = {}) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
        const grant = await billingRepository.findGrantById(grantId);
        if (!grant || grant.status !== 'active') return null;
        if (grant.vd_session_id) return grant;
        await new Promise((resolve) => setTimeout(resolve, intervalMs));
    }
    return null;
}

/**
 * Authorize a per-turn action against an existing consultation.
 *
 * Ownership is enforced as part of the lookup: a caller who supplies a session
 * id belonging to somebody else gets null, identical to supplying an id that
 * does not exist. The two cases are indistinguishable from outside, so this
 * cannot be used to probe which session ids are real.
 */
async function authorizeVoiceSession(userId, vdSessionId) {
    const grant = await billingRepository.findGrantBySessionId(vdSessionId, userId);
    if (!grant) return { allowed: false, code: 'NOT_FOUND' };

    if (grant.status !== 'active') {
        return {
            allowed: false,
            code: ERROR_CODES.VOICE_COOLDOWN,
            meta: { next_free_at: grant.next_free_at, upgrade_available: true },
        };
    }

    // Keep the consultation alive. Without this, a long but legitimate
    // consultation would trip the idle timeout mid-conversation.
    await billingRepository.touchGrant(vdSessionId, userId);
    return { allowed: true, grant };
}

/** Finalize a consultation. For a free grant this starts the cooldown. */
async function finalizeVoiceSession(userId, vdSessionId, status = 'completed') {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        await billingRepository.lockUserFeature(client, userId, FEATURES.VOICE_CONSULTATION);

        const grant = await billingRepository.findGrantBySessionId(vdSessionId, userId, client);
        if (!grant || grant.status !== 'active') {
            await client.query('COMMIT');
            return grant || null;
        }

        const finalized = await billingRepository.finalizeGrant(client, {
            grantId: grant.id,
            status,
            cooldownHours: policy.voice.cooldownHours,
        });
        await client.query('COMMIT');

        if (finalized) {
            emit('voice_session_consumed', {
                user_id: userId,
                grant_id: finalized.id,
                source: finalized.entitlement_source,
                status: finalized.status,
                next_free_at: finalized.next_free_at,
            });
        }
        return finalized;
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

// ---------------------------------------------------------------------
// Entitlement snapshot (the read API clients render from)
// ---------------------------------------------------------------------

/**
 * Everything a client needs to render accurate quota UI, computed server-side.
 *
 * The client renders this; it never derives entitlement itself. Countdowns are
 * the one thing the UI may compute locally, and only from the absolute
 * timestamps returned here — never from its own clock's notion of when a
 * window started.
 */
async function getEntitlementSnapshot(userId) {
    const client = await db.getClient();
    try {
        const entitlement = await resolveEntitlement(userId, client);
        const { isPro, serverNow, subscription } = entitlement;

        // Chatbot
        const window = await billingRepository.findCurrentWindow(userId, FEATURES.CHATBOT_MESSAGE, client);
        const used = window ? window.reserved_count + window.consumed_count : 0;
        const limit = policy.chatbot.freeMessagesPerWindow;

        const chatbot = isPro
            ? { allowed: true, unlimited: true, used: null, limit: null, remaining: null, resets_at: null }
            : {
                allowed: used < limit,
                unlimited: false,
                used,
                limit,
                remaining: Math.max(limit - used, 0),
                resets_at: window ? window.window_end : null,
            };

        // Voice — expire stale grants first so the snapshot never advertises a
        // dead session as resumable.
        await billingRepository.expireStaleGrants(client, userId, {
            idleTimeoutMinutes: policy.voice.idleTimeoutMinutes,
            cooldownHours: policy.voice.cooldownHours,
        });
        const activeGrant = await billingRepository.findActiveGrant(client, userId);
        const cooldown = isPro ? null : await billingRepository.findActiveCooldown(client, userId);

        const voice = {
            allowed: Boolean(activeGrant) || isPro || !cooldown,
            unlimited: isPro,
            active_session_id: activeGrant ? activeGrant.vd_session_id : null,
            next_free_at: cooldown ? cooldown.next_free_at : null,
        };

        return {
            plan: entitlement.planCode,
            subscription: subscription
                ? {
                    status: subscription.status,
                    cancel_at_period_end: subscription.cancel_at_period_end,
                    current_period_end: subscription.current_period_end,
                    billing_interval: subscription.billing_interval,
                }
                : { status: null },
            features: {
                voice_doctor: voice,
                chatbot,
            },
            server_time: serverNow,
        };
    } finally {
        client.release();
    }
}

module.exports = {
    resolveEntitlement,
    reserveChatbotMessage,
    settleChatbotMessage,
    findSettledRequest,
    startVoiceSession,
    attachVoiceSession,
    releaseUnusedGrant,
    awaitSessionAttachment,
    authorizeVoiceSession,
    finalizeVoiceSession,
    getEntitlementSnapshot,
};

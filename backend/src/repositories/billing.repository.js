const db = require('../config/database');

/**
 * BillingRepository — all entitlement, quota and subscription persistence.
 *
 * Two rules shape everything here:
 *
 * 1. Time comes from the database (NOW()), never from Node and never from a
 *    client. Every deadline this module returns — resets_at, next_free_at,
 *    expires_at — is computed by PostgreSQL so two backend processes on
 *    machines with drifting clocks cannot disagree about whether a quota has
 *    reset.
 *
 * 2. Quota decisions are serialized per (user, feature) with a transaction-
 *    scoped advisory lock. Two tabs, two devices, or a burst of retries all
 *    queue behind the same lock, so "check then write" cannot interleave.
 *    Unique indexes back this up as defence in depth.
 */
class BillingRepository {

    // -----------------------------------------------------------------
    // Locking
    // -----------------------------------------------------------------

    /**
     * Serialize quota decisions for one user+feature for the rest of the
     * transaction. Released automatically on COMMIT or ROLLBACK, so a crashed
     * request cannot leave a user permanently locked out of their own quota.
     *
     * Scoped per user, so one user's burst never blocks anybody else.
     */
    async lockUserFeature(client, userId, featureCode) {
        await client.query(
            `SELECT pg_advisory_xact_lock(hashtext($1::text), hashtext($2::text))`,
            [userId, featureCode]
        );
    }

    // -----------------------------------------------------------------
    // Plans and subscriptions
    // -----------------------------------------------------------------

    async findPlanByCode(planCode) {
        const result = await db.query(
            `SELECT * FROM medorbit.subscription_plans WHERE plan_code = $1 AND is_active = true`,
            [planCode]
        );
        return result.rows[0] || null;
    }

    async listActivePlans() {
        const result = await db.query(
            `SELECT plan_code, name_en, name_ar, price_cents, currency,
                    billing_interval, interval_count, grants_pro
               FROM medorbit.subscription_plans
              WHERE is_active = true
              ORDER BY sort_order`
        );
        return result.rows;
    }

    /**
     * The caller's live subscription, if any, joined to its plan.
     *
     * Returns the row plus `server_now` from the same query, so entitlement is
     * evaluated against one consistent database instant rather than against
     * whatever the Node process thinks the time is.
     */
    async findLiveSubscription(userId, client = db) {
        const result = await client.query(
            `SELECT s.*,
                    p.plan_code, p.grants_pro, p.name_en AS plan_name_en,
                    p.name_ar AS plan_name_ar, p.price_cents, p.currency,
                    p.billing_interval,
                    NOW() AS server_now
               FROM medorbit.subscriptions s
               JOIN medorbit.subscription_plans p ON p.id = s.plan_id
              WHERE s.user_id = $1
                AND s.status IN ('incomplete', 'active', 'past_due')
              ORDER BY s.created_at DESC
              LIMIT 1`,
            [userId]
        );
        return result.rows[0] || null;
    }

    /** Database time, for callers that need an authoritative instant with no subscription row. */
    async serverNow(client = db) {
        const result = await client.query(`SELECT NOW() AS now`);
        return result.rows[0].now;
    }

    // -----------------------------------------------------------------
    // Metered quota (chatbot messages)
    // -----------------------------------------------------------------

    /**
     * The caller's current usage window, or null if they have not used the
     * feature inside one yet.
     *
     * Window counters track FREE consumption only. Pro usage is recorded in
     * the ledger but never incremented here, so a subscription lapsing
     * mid-window does not retroactively push the user over the free limit
     * using messages their subscription already paid for.
     */
    async findCurrentWindow(userId, featureCode, client = db) {
        const result = await client.query(
            `SELECT *, NOW() AS server_now
               FROM medorbit.usage_windows
              WHERE user_id = $1
                AND feature_code = $2
                AND window_end > NOW()
              ORDER BY window_end DESC
              LIMIT 1`,
            [userId, featureCode]
        );
        return result.rows[0] || null;
    }

    async findLedgerEntryByRequestId(client, userId, featureCode, clientRequestId) {
        const result = await client.query(
            `SELECT * FROM medorbit.usage_ledger
              WHERE user_id = $1 AND feature_code = $2 AND client_request_id = $3`,
            [userId, featureCode, clientRequestId]
        );
        return result.rows[0] || null;
    }

    /**
     * Reserve one unit of metered quota.
     *
     * Reservation rather than a plain increment is what makes failure safe in
     * both directions: the unit is held for the duration of the AI call so
     * concurrent requests cannot overspend the limit, and it is released
     * rather than consumed if the AI call fails, so a crash upstream does not
     * silently eat a user's message.
     *
     * Must be called inside a transaction that already holds the advisory lock
     * for (userId, featureCode).
     *
     * @returns {{outcome: 'reserved'|'replay'|'in_flight'|'denied', ...}}
     */
    async reserveMeteredUnit(client, {
        userId,
        featureCode,
        clientRequestId = null,
        limit,
        windowHours,
        entitlementSource,
        referenceId = null,
        inFlightSeconds = 120,
    }) {
        // Idempotency first, but the three settled states of a prior attempt
        // mean three different things and must not be collapsed into one
        // "replay". Treating them all as a replay is what let a single failed
        // attempt turn one request id into an unlimited supply of free AI
        // calls: the caller re-ran the work and the settle then no-opped
        // against an already-settled row, charging nothing.
        let retryOf = null;
        if (clientRequestId) {
            const existing = await this.findLedgerEntryByRequestId(client, userId, featureCode, clientRequestId);

            if (existing && existing.status === 'consumed') {
                // The work completed and was paid for. Answer from what it produced.
                return { outcome: 'replay', ledger: existing };
            }

            if (existing && existing.status === 'reserved') {
                const age = await client.query(
                    `SELECT $1::timestamptz < NOW() - make_interval(secs => $2::int) AS stale`,
                    [existing.created_at, inFlightSeconds]
                );
                if (!age.rows[0].stale) {
                    // Still running. Letting this through would run the AI a
                    // second time for the same logical message and charge for
                    // neither — the caller must wait and retry.
                    return { outcome: 'in_flight', ledger: existing };
                }
                // Older than any call could still be alive: the request that
                // reserved it died. Hand the unit back and re-reserve below,
                // rather than stranding the key until the window rolls over.
                await this.releaseReservation(existing.id, client);
                retryOf = existing;
            }

            if (existing && existing.status === 'released') {
                // A failed attempt being retried. This is real work, so it
                // takes a real unit — re-checked against the quota, because
                // the allowance may have been spent since it failed.
                retryOf = existing;
            }
        }

        let window = await this.findCurrentWindow(userId, featureCode, client);

        if (!window) {
            // Anchored at first use, not at midnight, so every user gets a
            // full window rather than whatever is left of a calendar day.
            const created = await client.query(
                `INSERT INTO medorbit.usage_windows (user_id, feature_code, window_start, window_end)
                 VALUES ($1, $2, NOW(), NOW() + make_interval(hours => $3::int))
                 RETURNING *, NOW() AS server_now`,
                [userId, featureCode, windowHours]
            );
            window = created.rows[0];
        }

        const isFree = entitlementSource === 'free';
        const usedInWindow = window.reserved_count + window.consumed_count;

        if (isFree && usedInWindow >= limit) {
            return {
                outcome: 'denied',
                window,
                used: usedInWindow,
                limit,
                resetsAt: window.window_end,
            };
        }

        let ledger;
        if (retryOf) {
            // Reuse the row so one client_request_id stays one ledger entry
            // and the unique index keeps doing its job. created_at is reset
            // because it is what the in-flight check above measures, and this
            // is a new attempt.
            ledger = await client.query(
                `UPDATE medorbit.usage_ledger
                    SET status             = 'reserved',
                        settled_at         = NULL,
                        window_id          = $2,
                        entitlement_source = $3,
                        reference_id       = COALESCE($4, reference_id),
                        created_at         = NOW()
                  WHERE id = $1 AND status = 'released'
                  RETURNING *`,
                [retryOf.id, window.id, entitlementSource, referenceId]
            );
            if (!ledger.rows[0]) {
                // Another retry of the same id won the race and is now holding
                // the row. Ours is the duplicate.
                const current = await this.findLedgerEntryByRequestId(client, userId, featureCode, clientRequestId);
                return { outcome: current?.status === 'consumed' ? 'replay' : 'in_flight', ledger: current };
            }
        } else {
            ledger = await client.query(
                `INSERT INTO medorbit.usage_ledger
                     (user_id, feature_code, window_id, client_request_id, status, entitlement_source, reference_id)
                 VALUES ($1, $2, $3, $4, 'reserved', $5, $6)
                 RETURNING *`,
                [userId, featureCode, window.id, clientRequestId, entitlementSource, referenceId]
            );
        }

        if (isFree) {
            const updated = await client.query(
                `UPDATE medorbit.usage_windows
                    SET reserved_count = reserved_count + 1, updated_at = NOW()
                  WHERE id = $1
                  RETURNING *`,
                [window.id]
            );
            window = updated.rows[0];
        }

        return {
            outcome: 'reserved',
            ledger: ledger.rows[0],
            window,
            used: isFree ? window.reserved_count + window.consumed_count : usedInWindow,
            limit,
            resetsAt: window.window_end,
        };
    }

    /**
     * Settle a reservation as actually used.
     *
     * referenceId is written here rather than at reservation time because the
     * conversation may not exist yet when the unit is reserved — the first
     * message of a conversation creates it. Recording it on settle is what
     * lets a later replay of the same client_request_id find the answer that
     * was already produced instead of calling the AI again.
     */
    async consumeReservation(ledgerId, client = db, referenceId = null) {
        const result = await client.query(
            `UPDATE medorbit.usage_ledger
                SET status = 'consumed',
                    settled_at = NOW(),
                    reference_id = COALESCE($2, reference_id)
              WHERE id = $1 AND status = 'reserved'
              RETURNING *`,
            [ledgerId, referenceId]
        );
        const row = result.rows[0];
        if (!row) return null;

        if (row.entitlement_source === 'free' && row.window_id) {
            await client.query(
                `UPDATE medorbit.usage_windows
                    SET reserved_count = GREATEST(reserved_count - 1, 0),
                        consumed_count = consumed_count + 1,
                        updated_at = NOW()
                  WHERE id = $1`,
                [row.window_id]
            );
        }
        return row;
    }

    /**
     * Hand a reservation back after a failed AI call.
     *
     * The ledger row is kept (as 'released') rather than deleted so the
     * attempt stays visible for debugging, while the unique index on
     * client_request_id continues to suppress a retry storm of the same
     * logical message.
     */
    async releaseReservation(ledgerId, client = db) {
        const result = await client.query(
            `UPDATE medorbit.usage_ledger
                SET status = 'released', settled_at = NOW()
              WHERE id = $1 AND status = 'reserved'
              RETURNING *`,
            [ledgerId]
        );
        const row = result.rows[0];
        if (!row) return null;

        if (row.entitlement_source === 'free' && row.window_id) {
            await client.query(
                `UPDATE medorbit.usage_windows
                    SET reserved_count = GREATEST(reserved_count - 1, 0), updated_at = NOW()
                  WHERE id = $1`,
                [row.window_id]
            );
        }
        return row;
    }

    // -----------------------------------------------------------------
    // Voice consultation grants
    // -----------------------------------------------------------------

    /**
     * Finalize any of this user's active grants that have outlived their idle
     * or absolute limit.
     *
     * Runs opportunistically before every eligibility decision rather than
     * only in a background sweeper, so eligibility is always evaluated against
     * a current picture even if the sweeper is not running. A free grant that
     * expires this way starts the cooldown exactly as a completed one does —
     * that is what makes abandoning a session pointless as an abuse strategy.
     */
    async expireStaleGrants(client, userId, { idleTimeoutMinutes, cooldownHours }) {
        const result = await client.query(
            `UPDATE medorbit.voice_session_grants
                SET status       = 'expired',
                    finalized_at = NOW(),
                    next_free_at = CASE WHEN entitlement_source = 'free'
                                        THEN NOW() + make_interval(hours => $3::int)
                                        ELSE NULL END,
                    updated_at   = NOW()
              WHERE user_id = $1
                AND status  = 'active'
                AND (expires_at <= NOW()
                     OR last_activity_at <= NOW() - make_interval(mins => $2::int))
              RETURNING *`,
            [userId, idleTimeoutMinutes, cooldownHours]
        );
        return result.rows;
    }

    async findActiveGrant(client, userId) {
        const result = await client.query(
            `SELECT *, NOW() AS server_now
               FROM medorbit.voice_session_grants
              WHERE user_id = $1 AND status = 'active'
              LIMIT 1`,
            [userId]
        );
        return result.rows[0] || null;
    }

    /**
     * The instant this user's next free consultation unlocks, or null if one
     * is available now. Derived from the most recent finalized free grant.
     */
    async findActiveCooldown(client, userId) {
        const result = await client.query(
            `SELECT MAX(next_free_at) AS next_free_at, NOW() AS server_now
               FROM medorbit.voice_session_grants
              WHERE user_id = $1
                AND entitlement_source = 'free'
                AND next_free_at IS NOT NULL
                AND next_free_at > NOW()`,
            [userId]
        );
        const row = result.rows[0];
        return row && row.next_free_at ? row : null;
    }

    async createGrant(client, { userId, entitlementSource, maxLifetimeMinutes }) {
        const result = await client.query(
            `INSERT INTO medorbit.voice_session_grants
                 (user_id, entitlement_source, status, expires_at)
             VALUES ($1, $2, 'active', NOW() + make_interval(mins => $3::int))
             RETURNING *, NOW() AS server_now`,
            [userId, entitlementSource, maxLifetimeMinutes]
        );
        return result.rows[0];
    }

    /**
     * Bind a reserved grant to the session the AI service actually created.
     *
     * Separate from createGrant because the grant must exist (and hold the
     * one-active-session slot) before the AI service is called at all —
     * otherwise a burst of /start requests would each pass eligibility and
     * only then discover they had all created sessions.
     */
    async attachSessionToGrant(client, grantId, vdSessionId) {
        const result = await client.query(
            `UPDATE medorbit.voice_session_grants
                SET vd_session_id = $2, last_activity_at = NOW(), updated_at = NOW()
              WHERE id = $1
              RETURNING *`,
            [grantId, vdSessionId]
        );
        return result.rows[0] || null;
    }

    /**
     * Look up a grant by consultation id, scoped to its owner.
     *
     * userId is a required part of the lookup, not a check applied afterwards,
     * so a caller supplying someone else's session id gets "not found" rather
     * than a row they can then be compared against.
     */
    async findGrantBySessionId(vdSessionId, userId, client = db) {
        const result = await client.query(
            `SELECT *, NOW() AS server_now
               FROM medorbit.voice_session_grants
              WHERE vd_session_id = $1 AND user_id = $2`,
            [vdSessionId, userId]
        );
        return result.rows[0] || null;
    }

    async findGrantById(grantId, client = db) {
        const result = await client.query(
            `SELECT *, NOW() AS server_now FROM medorbit.voice_session_grants WHERE id = $1`,
            [grantId]
        );
        return result.rows[0] || null;
    }

    /** Keep an in-progress consultation alive. Only meaningful while active. */
    async touchGrant(vdSessionId, userId, client = db) {
        const result = await client.query(
            `UPDATE medorbit.voice_session_grants
                SET last_activity_at = NOW(), updated_at = NOW()
              WHERE vd_session_id = $1 AND user_id = $2 AND status = 'active'
              RETURNING *`,
            [vdSessionId, userId]
        );
        return result.rows[0] || null;
    }

    /**
     * Finalize a consultation and, for a free one, start the cooldown.
     *
     * The cooldown is anchored to finalization rather than to start time
     * because the product promise is "24 hours after your consultation ends".
     */
    async finalizeGrant(client, { grantId, status, cooldownHours }) {
        const result = await client.query(
            `UPDATE medorbit.voice_session_grants
                SET status       = $2,
                    finalized_at = NOW(),
                    next_free_at = CASE WHEN entitlement_source = 'free'
                                        THEN NOW() + make_interval(hours => $3::int)
                                        ELSE NULL END,
                    updated_at   = NOW()
              WHERE id = $1 AND status = 'active'
              RETURNING *, NOW() AS server_now`,
            [grantId, status, cooldownHours]
        );
        return result.rows[0] || null;
    }

    // -----------------------------------------------------------------
    // Billing customer identity
    // -----------------------------------------------------------------

    /**
     * Get or create the opaque billing handle for a user.
     *
     * ON CONFLICT rather than check-then-insert: two concurrent checkout
     * attempts must converge on one billing identity, not create two.
     */
    async getOrCreateBillingCustomer(userId, billingReference, client = db) {
        const result = await client.query(
            `INSERT INTO medorbit.billing_customers (user_id, billing_reference)
             VALUES ($1, $2)
             ON CONFLICT (user_id) DO UPDATE SET updated_at = NOW()
             RETURNING *`,
            [userId, billingReference]
        );
        return result.rows[0];
    }

    // -----------------------------------------------------------------
    // Webhook events
    // -----------------------------------------------------------------

    /**
     * Record a provider event exactly once.
     *
     * Returns null when the event was already recorded, which is the whole
     * point: providers retry deliveries, and replaying one must not re-apply
     * its state change. The uniqueness is a database constraint, so it holds
     * across processes and restarts.
     */
    async recordProviderEvent({ provider, providerEventId, eventType, eventCreatedAt, payloadDigest }, client = db) {
        const result = await client.query(
            `INSERT INTO medorbit.billing_events
                 (provider, provider_event_id, event_type, event_created_at, payload_digest)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (provider, provider_event_id) DO NOTHING
             RETURNING *`,
            [provider, providerEventId, eventType, eventCreatedAt || null, payloadDigest || null]
        );
        return result.rows[0] || null;
    }

    async markEventProcessed(eventId, { status, error = null, subscriptionId = null }, client = db) {
        const result = await client.query(
            `UPDATE medorbit.billing_events
                SET processing_status = $2,
                    processed_at      = CASE WHEN $2 = 'processed' THEN NOW() ELSE processed_at END,
                    attempts          = attempts + 1,
                    last_error        = $3,
                    subscription_id   = COALESCE($4, subscription_id)
              WHERE id = $1
              RETURNING *`,
            [eventId, status, error, subscriptionId]
        );
        return result.rows[0] || null;
    }
}

module.exports = new BillingRepository();

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
    async recordProviderEvent({ provider, providerEventId, eventType, eventCreatedAt, payloadDigest, userId = null }, client = db) {
        const result = await client.query(
            `INSERT INTO medorbit.billing_events
                 (provider, provider_event_id, event_type, event_created_at, payload_digest, user_id)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (provider, provider_event_id) DO NOTHING
             RETURNING *`,
            [provider, providerEventId, eventType, eventCreatedAt || null, payloadDigest || null, userId]
        );
        return result.rows[0] || null;
    }

    async markEventProcessed(eventId, { status, error = null, subscriptionId = null }, client = db) {
        const result = await client.query(
            // $2 is cast explicitly at every use. Without it PostgreSQL
            // deduces varchar from the assignment and text from the
            // comparison, and refuses the statement as an ambiguous
            // parameter — which is invisible until a provider exists and
            // this line first runs.
            `UPDATE medorbit.billing_events
                SET processing_status = $2::varchar,
                    processed_at      = CASE WHEN $2::varchar = 'processed' THEN NOW() ELSE processed_at END,
                    attempts          = attempts + 1,
                    last_error        = $3,
                    subscription_id   = COALESCE($4, subscription_id)
              WHERE id = $1
              RETURNING *`,
            [eventId, status, error, subscriptionId]
        );
        return result.rows[0] || null;
    }

    // -----------------------------------------------------------------
    // Subscription reconciliation
    // -----------------------------------------------------------------

    /**
     * Retire subscriptions whose time has simply run out.
     *
     * Entitlement is decided by comparing timestamps, so a lapsed row already
     * grants nothing before this runs. What this fixes is the status column,
     * which would otherwise keep saying "active" — a lie that is harmless
     * right up until somebody reconciles the billing tables against it.
     *
     * Lazy, on read, in the same style as expireStaleGrants above, because
     * MedOrbit has no scheduler. Rows are only ever moved to a terminal
     * state; nothing is deleted, so history survives a downgrade intact.
     */
    async expireLapsedSubscriptions(client, userId) {
        const result = await client.query(
            `UPDATE medorbit.subscriptions
                SET status = CASE
                                -- The subscriber asked to stop and the paid
                                -- period is over: that is a completed
                                -- cancellation, not a failure.
                                WHEN cancel_at_period_end THEN 'canceled'
                                ELSE 'expired'
                             END,
                    ended_at             = COALESCE(ended_at, NOW()),
                    grace_period_ends_at = NULL,
                    pending_plan_id      = NULL,
                    updated_at           = NOW()
              WHERE user_id = $1
                AND (
                      (status = 'active'
                       AND current_period_end IS NOT NULL
                       AND current_period_end <= NOW())
                   OR (status = 'past_due'
                       -- A null deadline is "no grace", not "grace forever";
                       -- such a row grants nothing already and is left alone
                       -- rather than being retired on a guess.
                       AND grace_period_ends_at IS NOT NULL
                       AND grace_period_ends_at <= NOW())
                   OR (status = 'incomplete'
                       -- A checkout that never completed must not hold the
                       -- one-live-subscription slot forever, or a failed
                       -- first payment would lock the account out of ever
                       -- trying again.
                       AND created_at <= NOW() - INTERVAL '1 day')
                )
              RETURNING id, status`,
            [userId]
        );
        return result.rows;
    }

    // -----------------------------------------------------------------
    // Checkout sessions
    // -----------------------------------------------------------------

    /**
     * Record a checkout attempt before the browser leaves for the provider.
     *
     * Persisted first, deliberately. If the row does not exist when the
     * provider's event arrives there is nothing to attribute it to, and the
     * alternative — trusting the returning browser to say which plan it
     * bought — is exactly the tampering this design exists to prevent.
     */
    async createCheckoutSession({
        userId, planId, provider, providerSessionId, returnPath = null, ttlMinutes = 60,
    }, client = db) {
        const result = await client.query(
            `INSERT INTO medorbit.billing_checkout_sessions
                 (user_id, plan_id, provider, provider_session_id, return_path, expires_at)
             VALUES ($1, $2, $3, $4, $5, NOW() + make_interval(mins => $6::int))
             RETURNING *`,
            [userId, planId, provider, providerSessionId, returnPath, ttlMinutes]
        );
        return result.rows[0];
    }

    /**
     * Look up an attempt as its owner.
     *
     * user_id is part of the WHERE clause rather than something checked after
     * the row comes back: a leaked or guessed checkout token belonging to
     * somebody else returns nothing at all, so there is no object for a
     * subsequent ownership check to be forgotten on.
     */
    async findOwnedCheckoutSession(provider, providerSessionId, userId, client = db) {
        const result = await client.query(
            `SELECT cs.*, p.plan_code, p.name_en, p.name_ar, p.price_cents, p.currency,
                    p.billing_interval, p.interval_count,
                    NOW() AS server_now,
                    (cs.status = 'open' AND cs.expires_at > NOW()) AS is_open
               FROM medorbit.billing_checkout_sessions cs
               JOIN medorbit.subscription_plans p ON p.id = cs.plan_id
              WHERE cs.provider = $1 AND cs.provider_session_id = $2 AND cs.user_id = $3`,
            [provider, providerSessionId, userId]
        );
        return result.rows[0] || null;
    }

    /** Provider-event lookup. No user scope: the event names the attempt, not a caller. */
    async findCheckoutSessionByProviderId(provider, providerSessionId, client = db) {
        const result = await client.query(
            `SELECT cs.*, p.plan_code
               FROM medorbit.billing_checkout_sessions cs
               JOIN medorbit.subscription_plans p ON p.id = cs.plan_id
              WHERE cs.provider = $1 AND cs.provider_session_id = $2
              FOR UPDATE OF cs`,
            [provider, providerSessionId]
        );
        return result.rows[0] || null;
    }

    /**
     * Resolve an attempt exactly once.
     *
     * The `AND status = 'open'` guard is what makes a duplicate delivery a
     * no-op: the second update matches no rows and returns null, so the
     * caller can tell "already handled" from "just handled" without keeping
     * state anywhere but the database.
     */
    async resolveCheckoutSession(id, { status, subscriptionId = null }, client = db) {
        const result = await client.query(
            `UPDATE medorbit.billing_checkout_sessions
                SET status          = $2,
                    completed_at    = NOW(),
                    subscription_id = $3,
                    updated_at      = NOW()
              WHERE id = $1 AND status = 'open'
              RETURNING *`,
            [id, status, subscriptionId]
        );
        return result.rows[0] || null;
    }

    /** Retire attempts the user walked away from, so the billing page is not littered with them. */
    async expireOpenCheckoutSessions(userId, client = db) {
        const result = await client.query(
            `UPDATE medorbit.billing_checkout_sessions
                SET status = 'expired', completed_at = NOW(), updated_at = NOW()
              WHERE user_id = $1 AND status = 'open' AND expires_at <= NOW()
              RETURNING id`,
            [userId]
        );
        return result.rowCount;
    }

    // -----------------------------------------------------------------
    // Subscription lifecycle
    // -----------------------------------------------------------------

    /**
     * The live subscription, locked for the rest of the transaction.
     *
     * FOR UPDATE on top of the advisory lock the callers already take. The
     * advisory lock serialises our own code paths; this also serialises
     * against anything else that touches the row, which matters because
     * provider events arrive concurrently with user actions.
     */
    async findLiveSubscriptionForUpdate(client, userId) {
        const result = await client.query(
            `SELECT s.*, p.plan_code, p.billing_interval, p.interval_count, p.grants_pro,
                    NOW() AS server_now
               FROM medorbit.subscriptions s
               JOIN medorbit.subscription_plans p ON p.id = s.plan_id
              WHERE s.user_id = $1
                AND s.status IN ('incomplete', 'active', 'past_due')
              ORDER BY s.created_at DESC
              LIMIT 1
              FOR UPDATE OF s`,
            [userId]
        );
        return result.rows[0] || null;
    }

    async findSubscriptionByProviderId(provider, providerSubscriptionId, client = db) {
        const result = await client.query(
            `SELECT s.*, p.plan_code, p.billing_interval, p.interval_count
               FROM medorbit.subscriptions s
               JOIN medorbit.subscription_plans p ON p.id = s.plan_id
              WHERE s.provider = $1 AND s.provider_subscription_id = $2
              FOR UPDATE OF s`,
            [provider, providerSubscriptionId]
        );
        return result.rows[0] || null;
    }

    /**
     * Create an active subscription with its first paid period.
     *
     * The period is computed by PostgreSQL from the plan's own interval, in
     * calendar units. `+ interval '1 month'` knows that a subscription
     * starting 31 January renews 28 February; `+ 30 * 86400 seconds` does
     * not, and `365 * 24h` silently loses a day every leap year. Neither the
     * client nor Node contributes a single component of these timestamps.
     */
    async activateSubscription(client, {
        userId, planId, provider, providerSubscriptionId,
    }) {
        const result = await client.query(
            `INSERT INTO medorbit.subscriptions
                 (user_id, plan_id, status, current_period_start, current_period_end,
                  provider, provider_subscription_id)
             SELECT $1, p.id, 'active', NOW(),
                    NOW() + CASE p.billing_interval
                              WHEN 'month' THEN make_interval(months => p.interval_count)
                              WHEN 'year'  THEN make_interval(years  => p.interval_count)
                            END,
                    $3, $4
               FROM medorbit.subscription_plans p
              WHERE p.id = $2 AND p.grants_pro = true AND p.billing_interval <> 'none'
             RETURNING *`,
            [userId, planId, provider, providerSubscriptionId]
        );
        return result.rows[0] || null;
    }

    /**
     * Advance a paid period by one interval.
     *
     * Anchored to the previous period_end rather than to NOW(), so a renewal
     * processed a few minutes late does not quietly shorten the year the
     * subscriber paid for, and the billing date stays stable across renewals.
     *
     * A scheduled Monthly<->Annual change lands here too: this is the moment
     * where changing plan costs nobody anything, which is precisely why the
     * change was deferred to it.
     */
    async renewSubscription(client, subscriptionId) {
        const result = await client.query(
            `UPDATE medorbit.subscriptions s
                SET plan_id              = COALESCE(s.pending_plan_id, s.plan_id),
                    pending_plan_id      = NULL,
                    status               = 'active',
                    grace_period_ends_at = NULL,
                    current_period_start = s.current_period_end,
                    current_period_end   = s.current_period_end + CASE np.billing_interval
                                              WHEN 'month' THEN make_interval(months => np.interval_count)
                                              WHEN 'year'  THEN make_interval(years  => np.interval_count)
                                           END,
                    updated_at           = NOW()
               FROM medorbit.subscription_plans np
              WHERE s.id = $1
                AND np.id = COALESCE(s.pending_plan_id, s.plan_id)
                AND s.status IN ('active', 'past_due')
                AND s.current_period_end IS NOT NULL
             RETURNING s.*`,
            [subscriptionId]
        );
        return result.rows[0] || null;
    }

    /**
     * A renewal payment failed on a subscription that was already paid for.
     *
     * Restricted to status='active' on purpose. A failed FIRST payment leaves
     * an 'incomplete' row, and this query will not match it — so there is no
     * code path by which never having paid earns a grace period. That is a
     * business rule, and it is enforced here in the WHERE clause rather than
     * in a caller that could forget it.
     */
    async markPastDue(client, subscriptionId, graceDays) {
        const result = await client.query(
            `UPDATE medorbit.subscriptions
                SET status               = 'past_due',
                    grace_period_ends_at = NOW() + make_interval(days => $2::int),
                    updated_at           = NOW()
              WHERE id = $1 AND status = 'active'
             RETURNING *`,
            [subscriptionId, graceDays]
        );
        return result.rows[0] || null;
    }

    /** The retried payment went through. Grace is cleared, not merely ignored. */
    async recoverPayment(client, subscriptionId) {
        const result = await client.query(
            `UPDATE medorbit.subscriptions
                SET status = 'active', grace_period_ends_at = NULL, updated_at = NOW()
              WHERE id = $1 AND status = 'past_due'
             RETURNING *`,
            [subscriptionId]
        );
        return result.rows[0] || null;
    }

    /**
     * Switch auto-renew off (or back on) without touching paid access.
     *
     * cancel_at_period_end is a flag on a still-active row, so the subscriber
     * keeps everything they paid for until current_period_end. Cancelling is
     * not a refund, and this is where that distinction is kept honest.
     */
    async setCancelAtPeriodEnd(client, subscriptionId, cancelAtPeriodEnd) {
        const result = await client.query(
            `UPDATE medorbit.subscriptions
                SET cancel_at_period_end = $2::boolean,
                    canceled_at          = CASE WHEN $2::boolean THEN NOW() ELSE NULL END,
                    -- Resuming keeps any scheduled plan change; cancelling
                    -- drops it, because the check constraint forbids holding
                    -- both and a subscription that is ending has nothing to
                    -- change plan to.
                    pending_plan_id      = CASE WHEN $2::boolean THEN NULL ELSE pending_plan_id END,
                    updated_at           = NOW()
              WHERE id = $1 AND status IN ('active', 'past_due')
             RETURNING *`,
            [subscriptionId, cancelAtPeriodEnd]
        );
        return result.rows[0] || null;
    }

    /** Schedule a Monthly<->Annual change for the next renewal. */
    async setPendingPlan(client, subscriptionId, pendingPlanId) {
        const result = await client.query(
            `UPDATE medorbit.subscriptions
                SET pending_plan_id = $2, updated_at = NOW()
              WHERE id = $1 AND status IN ('active', 'past_due') AND cancel_at_period_end = false
             RETURNING *`,
            [subscriptionId, pendingPlanId]
        );
        return result.rows[0] || null;
    }

    /**
     * End a subscription.
     *
     * The row is updated, never deleted. Entitlement stops; the record of
     * what the user had and when stays, because a deleted subscription makes
     * a billing dispute unanswerable. Nothing the subscriber produced while
     * subscribed is touched by this — see the entitlement service, which
     * reads state rather than owning content.
     */
    async terminateSubscription(client, subscriptionId, status = 'canceled') {
        const result = await client.query(
            `UPDATE medorbit.subscriptions
                SET status               = $2,
                    ended_at             = NOW(),
                    grace_period_ends_at = NULL,
                    pending_plan_id      = NULL,
                    updated_at           = NOW()
              WHERE id = $1 AND status IN ('incomplete', 'active', 'past_due')
             RETURNING *`,
            [subscriptionId, status]
        );
        return result.rows[0] || null;
    }

    /**
     * Everything the billing page renders, in one query.
     *
     * Includes the pending plan so the UI can say "changes to Annual on 3
     * March" rather than making the user infer it.
     */
    async findSubscriptionDetail(userId, client = db) {
        const result = await client.query(
            `SELECT s.id, s.status, s.cancel_at_period_end, s.current_period_start,
                    s.current_period_end, s.grace_period_ends_at, s.canceled_at, s.ended_at,
                    p.plan_code, p.name_en, p.name_ar, p.price_cents, p.currency,
                    p.billing_interval, p.interval_count,
                    pp.plan_code AS pending_plan_code,
                    pp.name_en   AS pending_name_en,
                    pp.name_ar   AS pending_name_ar,
                    pp.price_cents AS pending_price_cents,
                    pp.billing_interval AS pending_billing_interval,
                    NOW() AS server_now
               FROM medorbit.subscriptions s
               JOIN medorbit.subscription_plans p  ON p.id = s.plan_id
          LEFT JOIN medorbit.subscription_plans pp ON pp.id = s.pending_plan_id
              WHERE s.user_id = $1
              ORDER BY
                    CASE WHEN s.status IN ('incomplete','active','past_due') THEN 0 ELSE 1 END,
                    s.created_at DESC
              LIMIT 1`,
            [userId]
        );
        return result.rows[0] || null;
    }

    // -----------------------------------------------------------------
    // Billing history
    // -----------------------------------------------------------------

    /**
     * The user's own billing timeline.
     *
     * Selects named columns, never the payload. redacted_payload and
     * payload_digest stay server-side: a provider payload is the one place
     * personal and cardholder-adjacent data could leak into a UI, and the
     * user gains nothing from seeing it that the event type does not already
     * tell them.
     */
    async listBillingHistory(userId, limit = 50, client = db) {
        const result = await client.query(
            `SELECT e.provider_event_id, e.event_type, e.received_at, e.processing_status
               FROM medorbit.billing_events e
              WHERE e.user_id = $1
                AND e.processing_status = 'processed'
              ORDER BY e.received_at DESC
              LIMIT $2`,
            [userId, Math.min(Math.max(Number(limit) || 50, 1), 200)]
        );
        return result.rows;
    }

    /** Attribute a recorded event to the account it concerns. */
    async attachEventOwner(eventId, userId, client = db) {
        await client.query(
            `UPDATE medorbit.billing_events SET user_id = $2 WHERE id = $1 AND user_id IS NULL`,
            [eventId, userId]
        );
    }
}

module.exports = new BillingRepository();

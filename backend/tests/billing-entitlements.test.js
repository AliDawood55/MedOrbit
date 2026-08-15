/**
 * Billing, quotas and AI entitlements — provider-independent foundation.
 *
 * The load-bearing claim of this feature is not "the happy path works", it is
 * "the limits cannot be evaded". So most of what follows is adversarial: two
 * tabs racing for the same free session, a retry storm on one chat message, a
 * second account guessing a session id, a browser that has been told it is Pro.
 *
 * Everything runs against real PostgreSQL through the real HTTP API, because
 * the guarantees being tested — unique indexes, advisory locks, transaction
 * boundaries — do not exist in a mock.
 *
 * Requires the docker test stack (see helpers/test-environment.js):
 *   npm run test:billing:docker
 */
const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');
const { policy } = require('../src/config/billing');

const pool = new Pool(poolConfig);
const run = Date.now();
let passed = 0;
let failed = 0;
const ids = {};

function check(name, ok, detail = '') {
    if (ok) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
}

function section(title) {
    console.log(`\n${title}`);
}

function jwt(id, role, version = 1) {
    return generateAccessToken({ sub: id, role, authorizationVersion: version });
}

async function request(method, route, token, body) {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const r = await fetch(`${apiBase}${route}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    let parsed = null;
    try { parsed = await r.json(); } catch { parsed = null; }
    return { status: r.status, body: parsed };
}

/** Parse a raw fetch Response body, tolerating a non-JSON error page. */
async function claimedProJson(response) {
    try { return await response.json(); } catch { return null; }
}

async function user(key, role = 'patient') {
    ids[key] = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.users
           (id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES ($1,$2,'test-only',$3,true,true,1)`,
        [ids[key], `billing_${key}_${run}@medorbit.test`, role]
    );
    return { id: ids[key], token: jwt(ids[key], role) };
}

/** Give a user a live subscription on a plan, bypassing checkout (none exists yet). */
async function grantSubscription(userId, planCode, overrides = {}) {
    const plan = await pool.query(
        `SELECT id FROM medorbit.subscription_plans WHERE plan_code = $1`, [planCode]
    );
    const result = await pool.query(
        `INSERT INTO medorbit.subscriptions
           (user_id, plan_id, status, cancel_at_period_end, current_period_start,
            current_period_end, grace_period_ends_at, ended_at)
         VALUES ($1,$2,$3,$4, $8, $5, $6, $7)
         RETURNING *`,
        [
            userId,
            plan.rows[0].id,
            overrides.status || 'active',
            overrides.cancelAtPeriodEnd || false,
            overrides.currentPeriodEnd || new Date(Date.now() + 30 * 86400000),
            overrides.gracePeriodEndsAt || null,
            overrides.endedAt || null,
            // Far enough back that even an already-elapsed period_end still
            // satisfies the end > start constraint.
            overrides.currentPeriodStart || new Date(Date.now() - 40 * 86400000),
        ]
    );
    return result.rows[0];
}

/** Clear a user's chatbot allowance so a test can start from a known state. */
async function resetChatQuota(userId) {
    await pool.query(`DELETE FROM medorbit.usage_ledger WHERE user_id = $1`, [userId]);
    await pool.query(`DELETE FROM medorbit.usage_windows WHERE user_id = $1`, [userId]);
}

async function main() {
    // =================================================================
    section('A. Schema, constraints and plan catalogue');
    // =================================================================
    {
        const plans = await pool.query(
            `SELECT plan_code, price_cents, currency, billing_interval, grants_pro
               FROM medorbit.subscription_plans ORDER BY sort_order`
        );
        const byCode = Object.fromEntries(plans.rows.map((p) => [p.plan_code, p]));

        check('three plans are seeded', plans.rows.length === 3, `got ${plans.rows.length}`);
        check('free plan grants no Pro and costs nothing',
            byCode.free?.price_cents === 0 && byCode.free.grants_pro === false);
        check('pro_monthly is $20 USD/month in the database',
            byCode.pro_monthly?.price_cents === 2000
            && byCode.pro_monthly.currency === 'USD'
            && byCode.pro_monthly.billing_interval === 'month',
            JSON.stringify(byCode.pro_monthly));
        check('pro_annual is $200 USD/year in the database',
            byCode.pro_annual?.price_cents === 20000
            && byCode.pro_annual.currency === 'USD'
            && byCode.pro_annual.billing_interval === 'year',
            JSON.stringify(byCode.pro_annual));

        // Money as integer minor units — a float column would silently lose
        // cents on arithmetic.
        const priceType = await pool.query(
            `SELECT data_type FROM information_schema.columns
              WHERE table_schema='medorbit' AND table_name='subscription_plans'
                AND column_name='price_cents'`
        );
        check('price is an integer column, not floating point',
            priceType.rows[0]?.data_type === 'integer', priceType.rows[0]?.data_type);

        // Every timestamp must be timezone-aware, or "24 hours" means different
        // things to two servers in different regions.
        const naive = await pool.query(
            `SELECT table_name, column_name FROM information_schema.columns
              WHERE table_schema='medorbit'
                AND table_name IN ('subscriptions','subscription_plans','billing_events',
                                   'usage_windows','usage_ledger','voice_session_grants',
                                   'billing_customers')
                AND data_type = 'timestamp without time zone'`
        );
        check('no naive timestamps in any billing table', naive.rows.length === 0,
            JSON.stringify(naive.rows));
    }

    const alice = await user('alice');
    const bob = await user('bob');

    {
        // One live subscription per user, enforced structurally.
        await grantSubscription(alice.id, 'pro_monthly');
        let rejected = false;
        try {
            await grantSubscription(alice.id, 'pro_annual');
        } catch (err) {
            rejected = err.code === '23505';
        }
        check('a second live subscription for one user is rejected by the database', rejected);

        // Terminal states must record when access ended.
        let shapeRejected = false;
        try {
            const plan = await pool.query(`SELECT id FROM medorbit.subscription_plans WHERE plan_code='pro_monthly'`);
            await pool.query(
                `INSERT INTO medorbit.subscriptions (user_id, plan_id, status) VALUES ($1,$2,'canceled')`,
                [bob.id, plan.rows[0].id]
            );
        } catch (err) {
            shapeRejected = err.code === '23514';
        }
        check('a canceled subscription without ended_at is rejected', shapeRejected);

        // Webhook replay protection is a database constraint, not app memory.
        const eventId = `evt_${run}`;
        await pool.query(
            `INSERT INTO medorbit.billing_events (provider, provider_event_id, event_type)
             VALUES ('test',$1,'sub.updated')`, [eventId]
        );
        let dupeRejected = false;
        try {
            await pool.query(
                `INSERT INTO medorbit.billing_events (provider, provider_event_id, event_type)
                 VALUES ('test',$1,'sub.updated')`, [eventId]
            );
        } catch (err) { dupeRejected = err.code === '23505'; }
        check('a replayed provider event id is rejected by a unique constraint', dupeRejected);

        // Deleting a user must not orphan billing rows.
        const fk = await pool.query(
            `SELECT confdeltype FROM pg_constraint
              WHERE conrelid = 'medorbit.usage_ledger'::regclass AND contype = 'f'
                AND confrelid = 'medorbit.users'::regclass`
        );
        check('usage ledger cascades on user delete', fk.rows[0]?.confdeltype === 'c');

        await pool.query(`DELETE FROM medorbit.subscriptions WHERE user_id = $1`, [alice.id]);
    }

    // =================================================================
    section('B. Entitlement API');
    // =================================================================
    {
        const res = await request('GET', '/billing/entitlements', alice.token);
        check('entitlements require no special role and return 200', res.status === 200);
        const data = res.body?.data;
        check('a user with no subscription is on the free plan', data?.plan === 'free', data?.plan);
        check('subscription status is null when there is none', data?.subscription?.status === null);
        check('chatbot reports the configured free limit',
            data?.features?.chatbot?.limit === policy.chatbot.freeMessagesPerWindow,
            String(data?.features?.chatbot?.limit));
        check('chatbot starts with the full allowance remaining',
            data?.features?.chatbot?.remaining === policy.chatbot.freeMessagesPerWindow);
        check('voice doctor is available and has no cooldown yet',
            data?.features?.voice_doctor?.allowed === true
            && data?.features?.voice_doctor?.next_free_at === null);
        check('the response carries authoritative server time', Boolean(data?.server_time));

        const anon = await request('GET', '/billing/entitlements', null);
        check('entitlements are not readable without authentication', anon.status === 401);

        const plans = await request('GET', '/billing/plans', alice.token);
        const proMonthly = plans.body?.data?.plans?.find((p) => p.plan_code === 'pro_monthly');
        check('plan prices are served from the backend, not the client',
            proMonthly?.price_cents === 2000 && proMonthly?.currency === 'USD');
    }

    // =================================================================
    section('C. Free voice consultation lifecycle');
    // =================================================================
    let aliceSession = null;
    {
        const first = await request('POST', '/virtual-doctor/start', alice.token, { language: 'en' });
        check('a free user can start one consultation', first.status === 200, JSON.stringify(first.body));
        aliceSession = first.body?.data?.session_id;
        check('the consultation has a session id', Boolean(aliceSession));
        check('the first start is not a resume', first.body?.data?.resumed === false);
        check('the consultation is billed as free',
            first.body?.data?.entitlement_source === 'free');

        // The consultation must belong to the account, not to nobody.
        const owner = await pool.query(
            `SELECT user_id FROM medorbit.virtual_doctor_sessions WHERE session_id = $1`,
            [aliceSession]
        );
        check('the consultation is attached to the authenticated account',
            owner.rows[0]?.user_id === alice.id, String(owner.rows[0]?.user_id));

        // A refresh, a reconnect, a double-tap: all the same session.
        const second = await request('POST', '/virtual-doctor/start', alice.token, { language: 'en' });
        check('a duplicate start resumes rather than starting a new consultation',
            second.status === 200 && second.body?.data?.resumed === true);
        check('the resumed consultation is the same session',
            second.body?.data?.session_id === aliceSession);

        const grantCount = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.voice_session_grants WHERE user_id = $1`,
            [alice.id]
        );
        check('a duplicate start consumed only one free session', grantCount.rows[0].n === 1,
            `grants=${grantCount.rows[0].n}`);

        // Concurrency: two tabs racing at the same instant.
        const bobStart = await Promise.all([
            request('POST', '/virtual-doctor/start', bob.token, { language: 'en' }),
            request('POST', '/virtual-doctor/start', bob.token, { language: 'en' }),
            request('POST', '/virtual-doctor/start', bob.token, { language: 'en' }),
        ]);
        check('three simultaneous starts all succeed', bobStart.every((r) => r.status === 200),
            bobStart.map((r) => r.status).join(','));
        const bobSessions = new Set(bobStart.map((r) => r.body?.data?.session_id));
        check('three simultaneous starts converge on ONE consultation', bobSessions.size === 1,
            `distinct sessions=${bobSessions.size}`);
        const bobGrants = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.voice_session_grants WHERE user_id = $1`,
            [bob.id]
        );
        check('a concurrent burst consumed only one free session', bobGrants.rows[0].n === 1,
            `grants=${bobGrants.rows[0].n}`);
    }

    // =================================================================
    section('D. Voice cooldown and second-session denial');
    // =================================================================
    {
        // Drive the consultation to completion, which is what starts the cooldown.
        const done = await request('POST', '/virtual-doctor/message', alice.token, {
            session_id: aliceSession, message: 'please finish',
        });
        check('a consultation can reach its terminal phase',
            done.status === 200 && done.body?.data?.phase === 'complete',
            JSON.stringify(done.body?.data?.phase));

        const grant = await pool.query(
            `SELECT status, next_free_at, finalized_at FROM medorbit.voice_session_grants
              WHERE user_id = $1`, [alice.id]
        );
        check('the grant is finalized when the consultation completes',
            grant.rows[0]?.status === 'completed', grant.rows[0]?.status);
        check('a cooldown is scheduled on completion', Boolean(grant.rows[0]?.next_free_at));

        // The cooldown is anchored to the END of the consultation, not its start.
        const anchored = await pool.query(
            `SELECT (next_free_at - finalized_at) AS delta FROM medorbit.voice_session_grants
              WHERE user_id = $1`, [alice.id]
        );
        // Postgres normalises an interval, so 24 hours comes back as {days: 1}.
        // Compare in hours rather than on the raw shape.
        const delta = anchored.rows[0]?.delta || {};
        const deltaHours = (delta.days || 0) * 24 + (delta.hours || 0);
        check('the cooldown runs from when the consultation ended',
            deltaHours === policy.voice.cooldownHours, JSON.stringify(delta));

        const blocked = await request('POST', '/virtual-doctor/start', alice.token, { language: 'en' });
        check('a second free consultation is denied during the cooldown', blocked.status === 429,
            String(blocked.status));
        check('the denial carries a machine-readable code',
            blocked.body?.error?.code === 'VOICE_COOLDOWN', blocked.body?.error?.code);
        check('the denial tells the client exactly when the next one unlocks',
            Boolean(blocked.body?.error?.details?.next_free_at));
        check('the denial advertises that upgrading is possible',
            blocked.body?.error?.details?.upgrade_available === true);

        const snapshot = await request('GET', '/billing/entitlements', alice.token);
        check('the entitlement snapshot reports the cooldown',
            snapshot.body?.data?.features?.voice_doctor?.next_free_at !== null);

        // Once the cooldown lapses, eligibility returns on its own.
        await pool.query(
            `UPDATE medorbit.voice_session_grants SET next_free_at = NOW() - INTERVAL '1 minute'
              WHERE user_id = $1`, [alice.id]
        );
        const afterWindow = await request('POST', '/virtual-doctor/start', alice.token, { language: 'en' });
        check('a free consultation becomes available again after the cooldown',
            afterWindow.status === 200, JSON.stringify(afterWindow.body?.error?.code));
        aliceSession = afterWindow.body?.data?.session_id;
    }

    // =================================================================
    section('E. Abandonment cannot dodge the cooldown');
    // =================================================================
    {
        const idler = await user('idler');
        const started = await request('POST', '/virtual-doctor/start', idler.token, { language: 'en' });
        check('the idle-test user starts a consultation', started.status === 200);

        // Simulate a user who opens a consultation and walks away forever,
        // hoping never to trigger the 24-hour clock.
        await pool.query(
            `UPDATE medorbit.voice_session_grants
                SET last_activity_at = NOW() - make_interval(mins => $2::int)
              WHERE user_id = $1 AND status = 'active'`,
            [idler.id, policy.voice.idleTimeoutMinutes + 5]
        );

        const retry = await request('POST', '/virtual-doctor/start', idler.token, { language: 'en' });
        check('an abandoned consultation is denied, not silently reopened', retry.status === 429,
            String(retry.status));
        check('abandoning still triggers the cooldown',
            retry.body?.error?.code === 'VOICE_COOLDOWN', retry.body?.error?.code);

        const expired = await pool.query(
            `SELECT status, next_free_at FROM medorbit.voice_session_grants WHERE user_id = $1`,
            [idler.id]
        );
        check('the abandoned grant is finalized as expired',
            expired.rows[0]?.status === 'expired', expired.rows[0]?.status);
        check('the expired grant schedules the next free consultation',
            Boolean(expired.rows[0]?.next_free_at));
    }

    // =================================================================
    section('E2. The absolute ceiling, and whose clock decides');
    // =================================================================
    {
        // Idle expiry is defeated by any keystroke. The absolute ceiling is
        // what stops a scripted client from holding one consultation open
        // indefinitely by tapping it awake every few minutes.
        const marathon = await user('marathon');
        const opened = await request('POST', '/virtual-doctor/start', marathon.token, { language: 'en' });
        check('the ceiling-test user starts a consultation', opened.status === 200);

        const ceiling = await pool.query(
            `SELECT (expires_at - started_at) AS lifetime FROM medorbit.voice_session_grants
              WHERE user_id = $1`, [marathon.id]
        );
        const life = ceiling.rows[0]?.lifetime || {};
        const lifeMinutes = (life.days || 0) * 1440 + (life.hours || 0) * 60 + (life.minutes || 0);
        check('a consultation is given the configured maximum lifetime',
            lifeMinutes === policy.voice.maxLifetimeMinutes, JSON.stringify(life));

        // Push past the ceiling while keeping the session demonstrably active,
        // so only the absolute limit can end it.
        await pool.query(
            `UPDATE medorbit.voice_session_grants
                SET expires_at = NOW() - INTERVAL '1 minute', last_activity_at = NOW()
              WHERE user_id = $1 AND status = 'active'`,
            [marathon.id]
        );

        const afterCeiling = await request('POST', '/virtual-doctor/start', marathon.token, { language: 'en' });
        check('a consultation past its maximum lifetime is not resumed',
            afterCeiling.status === 429, String(afterCeiling.status));
        const ceilingGrant = await pool.query(
            `SELECT status, next_free_at FROM medorbit.voice_session_grants WHERE user_id = $1`,
            [marathon.id]
        );
        check('the over-long grant is finalized as expired',
            ceilingGrant.rows[0]?.status === 'expired', ceilingGrant.rows[0]?.status);
        check('hitting the ceiling starts the cooldown like any other ending',
            Boolean(ceilingGrant.rows[0]?.next_free_at));

        // ---------------------------------------------------------------
        // Time authority. Every deadline is computed by PostgreSQL, so a
        // client cannot move one by lying about what time it is.
        // ---------------------------------------------------------------
        const forgedTime = await request('POST', '/virtual-doctor/start', marathon.token, {
            language: 'en',
            now: new Date(Date.now() + 10 * 86400000).toISOString(),
            next_free_at: new Date(Date.now() - 86400000).toISOString(),
            client_time: new Date(Date.now() + 10 * 86400000).toISOString(),
            timezone: 'Pacific/Kiritimati',
        });
        check('a client-supplied clock does not unlock the next consultation',
            forgedTime.status === 429, String(forgedTime.status));
        const dbNextFree = await pool.query(
            `SELECT MAX(next_free_at) AS next_free_at FROM medorbit.voice_session_grants
              WHERE user_id = $1`, [marathon.id]
        );
        check('the cooldown deadline reported to the client is the database value',
            new Date(forgedTime.body?.error?.details?.next_free_at).getTime()
                === new Date(dbNextFree.rows[0].next_free_at).getTime(),
            `${forgedTime.body?.error?.details?.next_free_at} vs ${dbNextFree.rows[0].next_free_at}`);
        const storedTz = await pool.query(
            `SELECT next_free_at::text AS raw FROM medorbit.voice_session_grants
              WHERE user_id = $1 AND next_free_at IS NOT NULL LIMIT 1`, [marathon.id]
        );
        check('deadlines are stored with a timezone, not as a naive local stamp',
            /[+-]\d{2}(:?\d{2})?$/.test(storedTz.rows[0].raw), storedTz.rows[0].raw);
    }

    // =================================================================
    section('F. Cross-account isolation');
    // =================================================================
    {
        const mallory = await user('mallory');

        // Guessing or stealing a session id must gain nothing.
        const stolen = await request('POST', '/virtual-doctor/message', mallory.token, {
            session_id: aliceSession, message: 'hello',
        });
        check("another account cannot post into someone else's consultation",
            stolen.status === 404, String(stolen.status));

        const peek = await request('GET', `/virtual-doctor/session/${aliceSession}`, mallory.token);
        check("another account cannot read someone else's consultation", peek.status === 404,
            String(peek.status));

        const report = await request('POST', `/virtual-doctor/report/${aliceSession}`, mallory.token);
        check("another account cannot generate a report for someone else's consultation",
            report.status === 404, String(report.status));

        const ended = await request('POST', `/virtual-doctor/session/${aliceSession}/end`, mallory.token);
        check("another account cannot end someone else's consultation", ended.status === 404,
            String(ended.status));

        // The report PDF itself — the most sensitive object in the product.
        // A report id must not work as a bearer token for a medical document.
        const owner = await user('reportowner');
        const ownerSession = (await request('POST', '/virtual-doctor/start', owner.token, { language: 'en' }))
            .body?.data?.session_id;
        await request('POST', '/virtual-doctor/message', owner.token, {
            session_id: ownerSession, message: 'my chest hurts',
        });
        const generated = await request('POST', `/virtual-doctor/report/${ownerSession}`, owner.token);
        const reportId = generated.body?.data?.report_id;
        check('a consultation produces a downloadable report', Boolean(reportId),
            JSON.stringify(generated.body)?.slice(0, 140));

        const ownerDownload = await fetch(`${apiBase}/virtual-doctor/report/${reportId}/download`, {
            headers: { Authorization: `Bearer ${owner.token}` },
        });
        check('the owner can download their own report',
            ownerDownload.status === 200
            && ownerDownload.headers.get('content-type')?.includes('application/pdf'),
            `${ownerDownload.status}/${ownerDownload.headers.get('content-type')}`);

        const stolenDownload = await fetch(`${apiBase}/virtual-doctor/report/${reportId}/download`, {
            headers: { Authorization: `Bearer ${mallory.token}` },
        });
        check("another account cannot download someone else's report",
            stolenDownload.status === 404, String(stolenDownload.status));
        check('the refusal returns no PDF bytes',
            !(stolenDownload.headers.get('content-type') || '').includes('application/pdf'),
            stolenDownload.headers.get('content-type'));

        // Mallory's own quota is untouched by any of that.
        const mine = await request('GET', '/billing/entitlements', mallory.token);
        check('a failed intrusion did not spend the intruder\'s own allowance',
            mine.body?.data?.features?.chatbot?.remaining === policy.chatbot.freeMessagesPerWindow);
    }

    // =================================================================
    section('G. Unauthenticated and forged access');
    // =================================================================
    {
        const anon = await request('POST', '/virtual-doctor/start', null, { language: 'en' });
        check('the Virtual Doctor cannot be started without authentication', anon.status === 401);

        // The original vulnerability: identity supplied by the caller.
        const forged = await request('POST', '/virtual-doctor/start', null, {
            language: 'en', user_id: ids.alice,
        });
        check('a client-supplied user_id does not authenticate anything', forged.status === 401,
            String(forged.status));

        // Even WITH a valid token, a body-supplied user_id must not redirect
        // the consultation to another account.
        const impersonation = await request('POST', '/virtual-doctor/start', (await user('imp')).token, {
            language: 'en', user_id: ids.alice,
        });
        if (impersonation.status === 200) {
            const owner = await pool.query(
                `SELECT user_id FROM medorbit.virtual_doctor_sessions WHERE session_id = $1`,
                [impersonation.body.data.session_id]
            );
            check('a body-supplied user_id is ignored in favour of the token identity',
                owner.rows[0]?.user_id === ids.imp, String(owner.rows[0]?.user_id));
        } else {
            check('a body-supplied user_id is rejected outright', impersonation.status === 403,
                String(impersonation.status));
        }
    }

    // =================================================================
    section('H. Chatbot free quota');
    // =================================================================
    {
        const chatter = await user('chatter');
        const limit = policy.chatbot.freeMessagesPerWindow;

        let accepted = 0;
        let firstDenial = null;
        for (let i = 0; i < limit + 1; i++) {
            const res = await request('POST', '/chat/message', chatter.token, {
                message: `test message ${i}`,
                client_message_id: crypto.randomUUID(),
            });
            if (res.status === 200) accepted++;
            else if (!firstDenial) firstDenial = res;
        }

        check(`exactly ${limit} free messages are accepted`, accepted === limit, `accepted=${accepted}`);
        check(`message ${limit + 1} is denied`, firstDenial?.status === 429,
            String(firstDenial?.status));
        check('the denial carries a machine-readable code',
            firstDenial?.body?.error?.code === 'FREE_QUOTA_EXHAUSTED',
            firstDenial?.body?.error?.code);
        check('the denial reports zero remaining',
            firstDenial?.body?.error?.details?.remaining === 0);
        check('the denial returns an authoritative reset instant',
            Boolean(firstDenial?.body?.error?.details?.resets_at));

        // History must stay readable — only new AI requests are blocked.
        const history = await request('GET', '/conversations', chatter.token);
        check('conversation history is still readable at zero quota',
            history.status === 200, String(history.status));
    }

    // =================================================================
    section('I. Chatbot idempotency');
    // =================================================================
    {
        const retrier = await user('retrier');
        const requestId = crypto.randomUUID();

        const first = await request('POST', '/chat/message', retrier.token, {
            message: 'idempotent hello', client_message_id: requestId,
        });
        check('the first send is accepted', first.status === 200);

        // The same logical message, retried after a "timeout".
        const retry = await request('POST', '/chat/message', retrier.token, {
            message: 'idempotent hello', client_message_id: requestId,
        });
        check('a retry with the same request id is accepted, not rejected', retry.status === 200);

        const ledger = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.usage_ledger
              WHERE user_id = $1 AND client_request_id = $2`,
            [retrier.id, requestId]
        );
        check('a retry did not create a second ledger entry', ledger.rows[0].n === 1,
            `entries=${ledger.rows[0].n}`);

        const snapshot = await request('GET', '/billing/entitlements', retrier.token);
        check('a retry consumed only one message of the allowance',
            snapshot.body?.data?.features?.chatbot?.used === 1,
            String(snapshot.body?.data?.features?.chatbot?.used));

        // Rapid-fire duplicates, the double-click / Enter-mash case.
        const masher = await user('masher');
        const mashId = crypto.randomUUID();
        const mash = await Promise.all([1, 2, 3, 4, 5].map(() =>
            request('POST', '/chat/message', masher.token, {
                message: 'mash', client_message_id: mashId,
            })
        ));
        const mashed = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.usage_ledger WHERE user_id = $1`,
            [masher.id]
        );
        check('five simultaneous identical sends consume exactly one message',
            mashed.rows[0].n === 1, `entries=${mashed.rows[0].n}`);

        // Charging once is not enough on its own: if the other four still
        // reach the AI, one quota unit has bought five inferences.
        const mashConvs = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.chatbot_conversations WHERE user_id = $1`,
            [masher.id]
        );
        check('five simultaneous identical sends call the AI exactly once',
            mashConvs.rows[0].n === 1, `conversations=${mashConvs.rows[0].n}`);
        const refused = mash.filter((r) => r.status === 409);
        check('the in-flight duplicates are refused with a retryable code',
            refused.length === 4 && refused.every((r) => r.body?.error?.code === 'DUPLICATE_IN_FLIGHT'),
            `409s=${refused.length}`);

        // A message that was genuinely answered, whose HTTP response the client
        // never received. The retry must be served from what was already
        // produced — no second AI call, so no second row in the conversation.
        const lost = await user('lostresponse');
        const lostId = crypto.randomUUID();
        const original = await request('POST', '/chat/message', lost.token, {
            message: 'answer me once', client_message_id: lostId,
        });
        const convId = original.body?.data?.conversationId;
        const replayed = await request('POST', '/chat/message', lost.token, {
            message: 'answer me once', client_message_id: lostId,
        });
        check('a lost-response retry is answered from the stored reply',
            replayed.body?.data?.duplicate === true, JSON.stringify(replayed.body?.data)?.slice(0, 120));
        const botRows = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.chatbot_messages
              WHERE conversation_id = $1 AND message_type = 'bot'`,
            [convId]
        );
        check('a lost-response retry did not call the AI a second time',
            botRows.rows[0].n === 1, `bot messages=${botRows.rows[0].n}`);
    }

    // =================================================================
    section('I2. Chatbot failure semantics — nothing is charged for nothing');
    // =================================================================
    {
        // The AI stub returns 503 for this sentinel, which is what an outage,
        // a timeout or an unreachable service all collapse to in ai-client.
        const FAIL = '__AI_FAIL__ diagnose me';

        const faulty = await user('faulty');
        const failId = crypto.randomUUID();
        const failed = await request('POST', '/chat/message', faulty.token, {
            message: FAIL, client_message_id: failId,
        });
        check('a failed AI call still answers the client', failed.status === 200,
            String(failed.status));
        check('a failed AI call reports the error intent',
            failed.body?.data?.intent === 'error', String(failed.body?.data?.intent));

        const afterFailure = await request('GET', '/billing/entitlements', faulty.token);
        check('an AI failure consumes no quota',
            afterFailure.body?.data?.features?.chatbot?.used === 0,
            String(afterFailure.body?.data?.features?.chatbot?.used));

        const releasedRow = await pool.query(
            `SELECT status FROM medorbit.usage_ledger
              WHERE user_id = $1 AND client_request_id = $2`,
            [faulty.id, failId]
        );
        check('the failed attempt is recorded as released, not deleted',
            releasedRow.rows[0]?.status === 'released', String(releasedRow.rows[0]?.status));

        // The retry the user actually makes after seeing the error. It performs
        // real work, so it must cost a real message — otherwise pinning one
        // request id after a single outage yields unlimited free AI calls.
        const retried = await request('POST', '/chat/message', faulty.token, {
            message: 'diagnose me', client_message_id: failId,
        });
        check('a retry after a failure is accepted', retried.status === 200,
            String(retried.status));
        check('a retry after a failure produces a real answer',
            retried.body?.data?.intent !== 'error', String(retried.body?.data?.intent));

        const afterRetry = await request('GET', '/billing/entitlements', faulty.token);
        check('a successful retry after a failure consumes exactly one message',
            afterRetry.body?.data?.features?.chatbot?.used === 1,
            String(afterRetry.body?.data?.features?.chatbot?.used));

        // Amplification: the same id reused again and again must not keep
        // buying free AI calls.
        for (let i = 0; i < 5; i++) {
            await request('POST', '/chat/message', faulty.token, {
                message: 'diagnose me', client_message_id: failId,
            });
        }
        const afterStorm = await request('GET', '/billing/entitlements', faulty.token);
        check('reusing one request id cannot mint free messages',
            afterStorm.body?.data?.features?.chatbot?.used === 1,
            String(afterStorm.body?.data?.features?.chatbot?.used));

        // A failure at the very last unit must hand it back, not strand it.
        const edge = await user('edgefail');
        const limit = policy.chatbot.freeMessagesPerWindow;
        for (let i = 0; i < limit; i++) {
            await request('POST', '/chat/message', edge.token, {
                message: `spend ${i}`, client_message_id: crypto.randomUUID(),
            });
        }
        const exhausted = await request('POST', '/chat/message', edge.token, {
            message: 'one too many', client_message_id: crypto.randomUUID(),
        });
        check('the allowance is exhausted after spending it', exhausted.status === 429);

        // Rewind one unit by failing a fresh attempt inside a reset window.
        await pool.query(
            `UPDATE medorbit.usage_windows
                SET window_start = NOW() - INTERVAL '25 hours',
                    window_end   = NOW() - INTERVAL '1 hour'
              WHERE user_id = $1 AND feature_code = 'chatbot_message'`,
            [edge.id]
        );
        const postResetFailure = await request('POST', '/chat/message', edge.token, {
            message: FAIL, client_message_id: crypto.randomUUID(),
        });
        check('a new window accepts a request after reset', postResetFailure.status === 200);
        const postResetSnapshot = await request('GET', '/billing/entitlements', edge.token);
        check('a failure in a fresh window leaves the full allowance intact',
            postResetSnapshot.body?.data?.features?.chatbot?.used === 0,
            String(postResetSnapshot.body?.data?.features?.chatbot?.used));
    }

    // =================================================================
    section('J. Quota concurrency at the boundary');
    // =================================================================
    {
        const racer = await user('racer');
        const limit = policy.chatbot.freeMessagesPerWindow;

        // Spend everything but one.
        for (let i = 0; i < limit - 1; i++) {
            await request('POST', '/chat/message', racer.token, {
                message: `fill ${i}`, client_message_id: crypto.randomUUID(),
            });
        }

        // Ten distinct requests race for the single remaining unit.
        const race = await Promise.all(
            Array.from({ length: 10 }, () => request('POST', '/chat/message', racer.token, {
                message: 'race', client_message_id: crypto.randomUUID(),
            }))
        );
        const accepted = race.filter((r) => r.status === 200).length;
        check('ten concurrent requests for one remaining unit accept exactly one',
            accepted === 1, `accepted=${accepted}`);

        const spent = await pool.query(
            `SELECT reserved_count + consumed_count AS total FROM medorbit.usage_windows
              WHERE user_id = $1 AND feature_code = 'chatbot_message'`,
            [racer.id]
        );
        check('the free allowance was never exceeded',
            Number(spent.rows[0]?.total) === limit, `total=${spent.rows[0]?.total}`);
    }

    // =================================================================
    section('K. Quota window reset');
    // =================================================================
    {
        const resetter = await user('resetter');
        await request('POST', '/chat/message', resetter.token, {
            message: 'before reset', client_message_id: crypto.randomUUID(),
        });

        // Age the window past its end, exactly as the passage of time would.
        await pool.query(
            `UPDATE medorbit.usage_windows
                SET window_start = NOW() - make_interval(hours => $2::int),
                    window_end   = NOW() - INTERVAL '1 minute'
              WHERE user_id = $1`,
            [resetter.id, policy.chatbot.windowHours + 1]
        );

        const snapshot = await request('GET', '/billing/entitlements', resetter.token);
        check('the allowance is restored once the window ends',
            snapshot.body?.data?.features?.chatbot?.remaining === policy.chatbot.freeMessagesPerWindow,
            String(snapshot.body?.data?.features?.chatbot?.remaining));

        const after = await request('POST', '/chat/message', resetter.token, {
            message: 'after reset', client_message_id: crypto.randomUUID(),
        });
        check('a message is accepted in the new window', after.status === 200);
    }

    // =================================================================
    section('L. Pro entitlement');
    // =================================================================
    {
        const pro = await user('pro');
        await grantSubscription(pro.id, 'pro_monthly');

        const snapshot = await request('GET', '/billing/entitlements', pro.token);
        check('a Pro subscriber reports the pro plan',
            snapshot.body?.data?.plan === 'pro_monthly', snapshot.body?.data?.plan);
        check('Pro sees no chatbot limit',
            snapshot.body?.data?.features?.chatbot?.unlimited === true
            && snapshot.body?.data?.features?.chatbot?.limit === null);
        check('Pro sees no voice quota UI',
            snapshot.body?.data?.features?.voice_doctor?.unlimited === true
            && snapshot.body?.data?.features?.voice_doctor?.next_free_at === null);

        // Well past the free allowance.
        const limit = policy.chatbot.freeMessagesPerWindow;
        let allAccepted = true;
        for (let i = 0; i < limit + 3; i++) {
            const res = await request('POST', '/chat/message', pro.token, {
                message: `pro ${i}`, client_message_id: crypto.randomUUID(),
            });
            if (res.status !== 200) { allAccepted = false; break; }
        }
        check(`Pro sends ${limit + 3} messages without hitting the free limit`, allAccepted);

        // Pro usage must not fill the free window counters, or a lapsing
        // subscription would instantly appear over-quota.
        const window = await pool.query(
            `SELECT reserved_count + consumed_count AS total FROM medorbit.usage_windows
              WHERE user_id = $1 AND feature_code = 'chatbot_message'`,
            [pro.id]
        );
        check('Pro usage does not consume the free allowance counters',
            !window.rows[0] || Number(window.rows[0].total) === 0,
            `total=${window.rows[0]?.total}`);

        // Voice: repeated consultations, no cooldown.
        const v1 = await request('POST', '/virtual-doctor/start', pro.token, { language: 'en' });
        check('Pro starts a consultation', v1.status === 200);
        check('the Pro consultation is billed as pro',
            v1.body?.data?.entitlement_source === 'pro', v1.body?.data?.entitlement_source);
        await request('POST', '/virtual-doctor/message', pro.token, {
            session_id: v1.body.data.session_id, message: 'please finish',
        });
        const v2 = await request('POST', '/virtual-doctor/start', pro.token, { language: 'en' });
        check('Pro starts a second consultation with no cooldown', v2.status === 200,
            v2.body?.error?.code);

        const proGrant = await pool.query(
            `SELECT next_free_at FROM medorbit.voice_session_grants
              WHERE user_id = $1 AND entitlement_source = 'pro' AND next_free_at IS NOT NULL`,
            [pro.id]
        );
        check('a Pro consultation never schedules a cooldown', proGrant.rows.length === 0);
    }

    // =================================================================
    section('M. Subscription status decides entitlement');
    // =================================================================
    {
        // past_due inside its grace window keeps Pro — a transient card
        // failure must not interrupt a consultation.
        const grace = await user('grace');
        await grantSubscription(grace.id, 'pro_monthly', {
            status: 'past_due',
            gracePeriodEndsAt: new Date(Date.now() + 3 * 86400000),
        });
        const graceSnap = await request('GET', '/billing/entitlements', grace.token);
        check('past_due inside the grace window still grants Pro',
            graceSnap.body?.data?.features?.chatbot?.unlimited === true,
            graceSnap.body?.data?.plan);

        // past_due past its grace window does not.
        const lapsed = await user('lapsed');
        await grantSubscription(lapsed.id, 'pro_monthly', {
            status: 'past_due',
            gracePeriodEndsAt: new Date(Date.now() - 86400000),
        });
        const lapsedSnap = await request('GET', '/billing/entitlements', lapsed.token);
        check('past_due beyond the grace window falls back to free',
            lapsedSnap.body?.data?.plan === 'free'
            && lapsedSnap.body?.data?.features?.chatbot?.unlimited === false,
            lapsedSnap.body?.data?.plan);

        // cancel_at_period_end keeps paid access until the period actually ends.
        const canceling = await user('canceling');
        await grantSubscription(canceling.id, 'pro_monthly', {
            cancelAtPeriodEnd: true,
            currentPeriodEnd: new Date(Date.now() + 10 * 86400000),
        });
        const cancelSnap = await request('GET', '/billing/entitlements', canceling.token);
        check('cancel-at-period-end retains Pro until the period ends',
            cancelSnap.body?.data?.features?.chatbot?.unlimited === true);
        check('the client is told the subscription is winding down',
            cancelSnap.body?.data?.subscription?.cancel_at_period_end === true);

        // An expired period grants nothing, whatever the status column says.
        const expired = await user('expired');
        await grantSubscription(expired.id, 'pro_monthly', {
            currentPeriodEnd: new Date(Date.now() - 86400000),
        });
        const expiredSnap = await request('GET', '/billing/entitlements', expired.token);
        check('an elapsed billing period does not grant Pro',
            expiredSnap.body?.data?.plan === 'free', expiredSnap.body?.data?.plan);

        // incomplete = checkout started, never paid.
        const incomplete = await user('incomplete');
        await grantSubscription(incomplete.id, 'pro_monthly', { status: 'incomplete' });
        const incompleteSnap = await request('GET', '/billing/entitlements', incomplete.token);
        check('an incomplete (unpaid) subscription grants nothing',
            incompleteSnap.body?.data?.plan === 'free', incompleteSnap.body?.data?.plan);
    }

    // =================================================================
    section('M2. Terminal statuses, and what a downgrade must not destroy');
    // =================================================================
    {
        // Terminal statuses are outside the live-subscription window entirely,
        // so they cannot occupy the one-live-per-user slot either.
        for (const status of ['canceled', 'expired']) {
            const account = await user(`terminal_${status}`);
            await grantSubscription(account.id, 'pro_monthly', {
                status,
                endedAt: new Date(Date.now() - 86400000),
            });
            const snap = await request('GET', '/billing/entitlements', account.token);
            check(`a ${status} subscription grants nothing`,
                snap.body?.data?.plan === 'free'
                && snap.body?.data?.features?.chatbot?.unlimited === false,
                snap.body?.data?.plan);
        }

        // A grace window is meaningless without a payment that once succeeded.
        // Honouring it on 'incomplete' would hand a week of free Pro to anyone
        // who starts a checkout and abandons it.
        const neverPaid = await user('neverpaid');
        await grantSubscription(neverPaid.id, 'pro_monthly', {
            status: 'incomplete',
            gracePeriodEndsAt: new Date(Date.now() + 7 * 86400000),
        });
        const neverPaidSnap = await request('GET', '/billing/entitlements', neverPaid.token);
        check('a failed initial payment gets no grace period',
            neverPaidSnap.body?.data?.plan === 'free', neverPaidSnap.body?.data?.plan);

        // A null grace deadline is "no grace", not "grace forever".
        const noGrace = await user('nograce');
        await grantSubscription(noGrace.id, 'pro_monthly', {
            status: 'past_due', gracePeriodEndsAt: null,
        });
        const noGraceSnap = await request('GET', '/billing/entitlements', noGrace.token);
        check('past_due with no grace deadline grants nothing',
            noGraceSnap.body?.data?.plan === 'free', noGraceSnap.body?.data?.plan);

        // ---------------------------------------------------------------
        // Losing Pro withdraws an entitlement. It must not withdraw the
        // patient's records — a lapsed card is not a reason to destroy a
        // medical history.
        // ---------------------------------------------------------------
        const downgraded = await user('downgraded');
        const sub = await grantSubscription(downgraded.id, 'pro_monthly');

        await request('POST', '/chat/message', downgraded.token, {
            message: 'remember this', client_message_id: crypto.randomUUID(),
        });
        const started = await request('POST', '/virtual-doctor/start', downgraded.token, { language: 'en' });
        const vdSession = started.body?.data?.session_id;
        await request('POST', '/virtual-doctor/message', downgraded.token, {
            session_id: vdSession, message: 'my head hurts',
        });
        await request('POST', `/virtual-doctor/report/${vdSession}`, downgraded.token);

        const before = await pool.query(
            `SELECT
               (SELECT COUNT(*)::int FROM medorbit.chatbot_messages m
                  JOIN medorbit.chatbot_conversations c ON c.id = m.conversation_id
                 WHERE c.user_id = $1) AS chat_messages,
               (SELECT COUNT(*)::int FROM medorbit.virtual_doctor_sessions WHERE user_id = $1) AS vd_sessions,
               (SELECT COUNT(*)::int FROM medorbit.virtual_doctor_reports r
                  JOIN medorbit.virtual_doctor_sessions s ON s.id = r.session_id
                 WHERE s.user_id = $1) AS vd_reports`,
            [downgraded.id]
        );
        check('the Pro account accumulated history to lose',
            before.rows[0].chat_messages > 0 && before.rows[0].vd_sessions > 0
            && before.rows[0].vd_reports > 0, JSON.stringify(before.rows[0]));

        // The downgrade itself, exactly as a lapsed renewal would write it.
        await pool.query(
            `UPDATE medorbit.subscriptions SET status='canceled', ended_at=NOW() WHERE id=$1`,
            [sub.id]
        );

        const afterSnap = await request('GET', '/billing/entitlements', downgraded.token);
        check('a canceled subscription drops the account to free',
            afterSnap.body?.data?.plan === 'free', afterSnap.body?.data?.plan);
        check('the free chatbot limit applies again after downgrade',
            afterSnap.body?.data?.features?.chatbot?.limit === policy.chatbot.freeMessagesPerWindow,
            String(afterSnap.body?.data?.features?.chatbot?.limit));

        const after = await pool.query(
            `SELECT
               (SELECT COUNT(*)::int FROM medorbit.chatbot_messages m
                  JOIN medorbit.chatbot_conversations c ON c.id = m.conversation_id
                 WHERE c.user_id = $1) AS chat_messages,
               (SELECT COUNT(*)::int FROM medorbit.virtual_doctor_sessions WHERE user_id = $1) AS vd_sessions,
               (SELECT COUNT(*)::int FROM medorbit.virtual_doctor_reports r
                  JOIN medorbit.virtual_doctor_sessions s ON s.id = r.session_id
                 WHERE s.user_id = $1) AS vd_reports`,
            [downgraded.id]
        );
        check('downgrading destroyed no chat history',
            after.rows[0].chat_messages === before.rows[0].chat_messages,
            `${before.rows[0].chat_messages} -> ${after.rows[0].chat_messages}`);
        check('downgrading destroyed no consultation history',
            after.rows[0].vd_sessions === before.rows[0].vd_sessions,
            `${before.rows[0].vd_sessions} -> ${after.rows[0].vd_sessions}`);
        check('downgrading destroyed no medical reports',
            after.rows[0].vd_reports === before.rows[0].vd_reports,
            `${before.rows[0].vd_reports} -> ${after.rows[0].vd_reports}`);

        const stillReadable = await request('GET', '/conversations', downgraded.token);
        check('chat history is still readable on the free plan',
            stillReadable.status === 200, String(stillReadable.status));
        const pastConsultation = await request('GET', `/virtual-doctor/session/${vdSession}`, downgraded.token);
        check('a past consultation is still readable on the free plan',
            pastConsultation.status === 200, String(pastConsultation.status));
        const accountIntact = await pool.query(
            `SELECT is_active FROM medorbit.users WHERE id = $1`, [downgraded.id]
        );
        check('the account itself is untouched by a downgrade',
            accountIntact.rows[0]?.is_active === true);
    }

    // =================================================================
    section('N. Entitlement follows the account, not the role');
    // =================================================================
    {
        const patientRole = await user('rolepatient', 'patient');
        const doctor = await user('doctor', 'doctor');
        const admin = await user('admin', 'admin');
        const superAdmin = await user('superadmin', 'super_admin');

        for (const [label, account] of [
            ['patient', patientRole], ['doctor', doctor], ['admin', admin], ['super_admin', superAdmin],
        ]) {
            const snap = await request('GET', '/billing/entitlements', account.token);
            check(`a ${label} with no subscription is on the free plan`,
                snap.body?.data?.plan === 'free', snap.body?.data?.plan);
            check(`a ${label} does not bypass the chatbot limit`,
                snap.body?.data?.features?.chatbot?.limit === policy.chatbot.freeMessagesPerWindow
                && snap.body?.data?.features?.chatbot?.unlimited === false);
        }

        // A doctor who actually pays gets exactly what a patient who pays gets.
        await grantSubscription(doctor.id, 'pro_annual');
        const paidDoctor = await request('GET', '/billing/entitlements', doctor.token);
        check('a subscribed doctor gets the same Pro entitlement as any other user',
            paidDoctor.body?.data?.plan === 'pro_annual'
            && paidDoctor.body?.data?.features?.chatbot?.unlimited === true,
            paidDoctor.body?.data?.plan);

        // A super_admin is still limited on voice.
        await request('POST', '/virtual-doctor/start', superAdmin.token, { language: 'en' });
        await pool.query(
            `UPDATE medorbit.voice_session_grants
                SET status='completed', finalized_at=NOW(),
                    next_free_at = NOW() + INTERVAL '24 hours'
              WHERE user_id = $1 AND status='active'`, [superAdmin.id]
        );
        const blocked = await request('POST', '/virtual-doctor/start', superAdmin.token, { language: 'en' });
        check('a super_admin is subject to the same voice cooldown',
            blocked.status === 429 && blocked.body?.error?.code === 'VOICE_COOLDOWN',
            `${blocked.status}/${blocked.body?.error?.code}`);
    }

    // =================================================================
    section('O. The client cannot grant itself Pro');
    // =================================================================
    {
        const faker = await user('faker');

        // There is no write endpoint for entitlement. Try the obvious ones.
        const attempts = [
            ['POST', '/billing/entitlements', { plan: 'pro_monthly' }],
            ['PUT', '/billing/entitlements', { plan: 'pro_monthly' }],
            ['POST', '/billing/subscriptions', { plan_code: 'pro_monthly', status: 'active' }],
        ];
        let anyAccepted = false;
        for (const [method, route, body] of attempts) {
            const res = await request(method, route, faker.token, body);
            if (res.status >= 200 && res.status < 300) anyAccepted = true;
        }
        check('no endpoint lets a client set its own subscription state', !anyAccepted);

        // Checkout refuses to trust a client-supplied price.
        const underpay = await request('POST', '/billing/checkout', faker.token, {
            plan_code: 'pro_monthly', price_cents: 1, amount: 1, currency: 'USD', discount: 100,
        });
        check('checkout never activates Pro on the client\'s say-so',
            underpay.status === 503 && underpay.body?.error?.code === 'ENTITLEMENT_UNAVAILABLE',
            `${underpay.status}/${underpay.body?.error?.code}`);

        const stillFree = await request('GET', '/billing/entitlements', faker.token);
        check('the account is still on the free plan after all of that',
            stillFree.body?.data?.plan === 'free', stillFree.body?.data?.plan);

        const noSubscription = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.subscriptions WHERE user_id = $1`, [faker.id]
        );
        check('no subscription row was created', noSubscription.rows[0].n === 0);

        // An unverifiable webhook is the other route to forged Pro.
        const forgedHook = await fetch(`${apiBase}/billing/webhook`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                type: 'subscription.created',
                data: { user_id: ids.faker, plan: 'pro_annual', status: 'active' },
            }),
        });
        check('an unsigned webhook is rejected', forgedHook.status === 400, String(forgedHook.status));

        const afterHook = await request('GET', '/billing/entitlements', faker.token);
        check('a forged webhook did not grant Pro',
            afterHook.body?.data?.plan === 'free', afterHook.body?.data?.plan);
    }

    // =================================================================
    section('P. Quota identity is the account, not the browser');
    // =================================================================
    {
        const multi = await user('multi');

        // "Desktop" spends some allowance.
        for (let i = 0; i < 3; i++) {
            await request('POST', '/chat/message', multi.token, {
                message: `desktop ${i}`, client_message_id: crypto.randomUUID(),
            });
        }

        // "Phone": a completely separate client with a fresh token, no cookies
        // and no localStorage. Same account, so the same spent allowance.
        const phoneToken = jwt(multi.id, 'patient');
        const phone = await request('GET', '/billing/entitlements', phoneToken);
        check('a second device sees the allowance already spent',
            phone.body?.data?.features?.chatbot?.used === 3,
            String(phone.body?.data?.features?.chatbot?.used));
        check('a second device sees the same remaining count',
            phone.body?.data?.features?.chatbot?.remaining === policy.chatbot.freeMessagesPerWindow - 3);

        // Cookies are not consulted for any of this. Sending forged ones,
        // including a fabricated Pro claim, must change nothing.
        const forged = await fetch(`${apiBase}/billing/entitlements`, {
            headers: {
                Authorization: `Bearer ${multi.token}`,
                Cookie: 'chatbot_used=0; quota_remaining=999; plan=pro_annual; is_pro=true',
            },
        });
        const forgedBody = await forged.json();
        check('forged quota cookies do not reset the allowance',
            forgedBody?.data?.features?.chatbot?.used === 3,
            String(forgedBody?.data?.features?.chatbot?.used));
        check('a forged plan cookie does not grant Pro',
            forgedBody?.data?.plan === 'free', forgedBody?.data?.plan);
    }

    // =================================================================
    section('P2. A client that believes it is Pro is still not Pro');
    // =================================================================
    {
        // Everything the browser could be made to say — edited localStorage,
        // a patched JS variable, a hand-written fetch — arrives as request
        // fields. None of them is read, so all of them change nothing.
        const liar = await user('liar');
        const limit = policy.chatbot.freeMessagesPerWindow;
        for (let i = 0; i < limit; i++) {
            await request('POST', '/chat/message', liar.token, {
                message: `spend ${i}`, client_message_id: crypto.randomUUID(),
            });
        }

        const claimedPro = await fetch(`${apiBase}/chat/message`, {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${liar.token}`,
                'Content-Type': 'application/json',
                Cookie: 'plan=pro_annual; is_pro=true; quota_remaining=999; chatbot_used=0',
                'X-Plan': 'pro_annual',
                'X-Is-Pro': 'true',
                'X-Quota-Remaining': '999',
                'X-Subscription-Status': 'active',
            },
            body: JSON.stringify({
                message: 'let me through',
                client_message_id: crypto.randomUUID(),
                is_pro: true,
                plan: 'pro_annual',
                plan_code: 'pro_annual',
                subscription_status: 'active',
                unlimited: true,
                quota_remaining: 999,
                entitlement: { isPro: true, source: 'pro' },
            }),
        });
        const claimedBody = await claimedProJson(claimedPro);
        check('an exhausted account claiming Pro is still refused',
            claimedPro.status === 429, String(claimedPro.status));
        check('the refusal is the quota code, not something the client chose',
            claimedBody?.error?.code === 'FREE_QUOTA_EXHAUSTED', claimedBody?.error?.code);

        const stillFree = await request('GET', '/billing/entitlements', liar.token);
        check('the tampered request did not upgrade the account',
            stillFree.body?.data?.plan === 'free', stillFree.body?.data?.plan);
        check('the tampered request did not restore any allowance',
            stillFree.body?.data?.features?.chatbot?.remaining === 0,
            String(stillFree.body?.data?.features?.chatbot?.remaining));

        // Reading what has already been said is not a premium feature. A user
        // at zero quota still owns their history.
        const conversations = await request('GET', '/conversations', liar.token);
        check('conversations are still listed at zero quota', conversations.status === 200,
            String(conversations.status));
        const list = conversations.body?.data?.conversations
            || conversations.body?.data?.items
            || conversations.body?.data;
        const conversationId = Array.isArray(list) ? list[0]?.id : null;
        const messages = conversationId
            ? await request('GET', `/conversations/${conversationId}`, liar.token)
            : { status: 0 };
        check('past messages are still readable at zero quota',
            messages.status === 200 && Array.isArray(messages.body?.data?.messages),
            `${messages.status} conv=${conversationId}`);

        // Same for the Virtual Doctor: a cooldown is not lifted by claiming Pro.
        const cooling = await user('cooling');
        const opened = await request('POST', '/virtual-doctor/start', cooling.token, { language: 'en' });
        await request('POST', '/virtual-doctor/message', cooling.token, {
            session_id: opened.body?.data?.session_id, message: 'please finish',
        });
        const proClaim = await fetch(`${apiBase}/virtual-doctor/start`, {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${cooling.token}`,
                'Content-Type': 'application/json',
                Cookie: 'plan=pro_annual; is_pro=true; voice_cooldown=0',
            },
            body: JSON.stringify({ language: 'en', is_pro: true, plan_code: 'pro_annual' }),
        });
        check('a cooldown is not lifted by a client claiming Pro',
            proClaim.status === 429, String(proClaim.status));
    }

    // =================================================================
    section('Q. Failure safety');
    // =================================================================
    {
        // A reservation that is released must return to the allowance rather
        // than being silently lost.
        const failer = await user('failer');
        await resetChatQuota(failer.id);

        const before = await request('GET', '/billing/entitlements', failer.token);
        const beforeUsed = before.body?.data?.features?.chatbot?.used ?? 0;

        // Simulate the AI failing after the unit was reserved.
        const reserved = await pool.query(
            `INSERT INTO medorbit.usage_ledger (user_id, feature_code, status, entitlement_source)
             VALUES ($1,'chatbot_message','reserved','free') RETURNING id`,
            [failer.id]
        );
        await pool.query(
            `INSERT INTO medorbit.usage_windows (user_id, feature_code, window_end, reserved_count)
             VALUES ($1,'chatbot_message', NOW() + INTERVAL '24 hours', 1)`,
            [failer.id]
        );
        const held = await request('GET', '/billing/entitlements', failer.token);
        check('an in-flight reservation counts against the allowance',
            held.body?.data?.features?.chatbot?.used === beforeUsed + 1,
            String(held.body?.data?.features?.chatbot?.used));

        // Release it, as a failed AI call would.
        await pool.query(
            `UPDATE medorbit.usage_ledger SET status='released', settled_at=NOW() WHERE id=$1`,
            [reserved.rows[0].id]
        );
        await pool.query(
            `UPDATE medorbit.usage_windows SET reserved_count = GREATEST(reserved_count - 1, 0)
              WHERE user_id = $1 AND feature_code='chatbot_message'`,
            [failer.id]
        );
        const released = await request('GET', '/billing/entitlements', failer.token);
        check('a released reservation is returned to the allowance',
            released.body?.data?.features?.chatbot?.used === beforeUsed,
            String(released.body?.data?.features?.chatbot?.used));

        // A grant reserved for a consultation that never started must not cost
        // the user a free session or a cooldown.
        const unlucky = await user('unlucky');
        const grant = await pool.query(
            `INSERT INTO medorbit.voice_session_grants
               (user_id, entitlement_source, status, expires_at)
             VALUES ($1,'free','active', NOW() + INTERVAL '2 hours') RETURNING id`,
            [unlucky.id]
        );
        await pool.query(
            `UPDATE medorbit.voice_session_grants
                SET status='abandoned', finalized_at=NOW(), next_free_at=NULL WHERE id=$1`,
            [grant.rows[0].id]
        );
        const retry = await request('POST', '/virtual-doctor/start', unlucky.token, { language: 'en' });
        check('a consultation that never started does not cost a free session',
            retry.status === 200, `${retry.status}/${retry.body?.error?.code}`);
    }

    // =================================================================
    section('R. Billing data holds no medical content');
    // =================================================================
    {
        // The separation is structural: assert that no billing table even has
        // a column capable of holding clinical content.
        const clinicalColumns = await pool.query(
            `SELECT table_name, column_name FROM information_schema.columns
              WHERE table_schema = 'medorbit'
                AND table_name IN ('subscriptions','subscription_plans','billing_events',
                                   'billing_customers','usage_windows','usage_ledger',
                                   'voice_session_grants')
                AND (column_name ILIKE '%symptom%'
                  OR column_name ILIKE '%diagnos%'
                  OR column_name ILIKE '%transcript%'
                  OR column_name ILIKE '%urgency%'
                  OR column_name ILIKE '%complaint%'
                  OR column_name ILIKE '%medication%'
                  OR column_name ILIKE '%report_json%'
                  OR column_name ILIKE '%message_text%')`
        );
        check('no billing table has a column for clinical content',
            clinicalColumns.rows.length === 0, JSON.stringify(clinicalColumns.rows));

        // And the grant points at a consultation by opaque id only.
        const grantColumns = await pool.query(
            `SELECT column_name FROM information_schema.columns
              WHERE table_schema='medorbit' AND table_name='voice_session_grants'`
        );
        const names = grantColumns.rows.map((r) => r.column_name);
        check('a voice grant references a consultation only by session id',
            names.includes('vd_session_id') && !names.includes('chief_complaint'),
            names.join(','));
    }

    // =================================================================
    console.log(`\n${'='.repeat(56)}`);
    console.log(`  passed: ${passed}    failed: ${failed}`);
    console.log('='.repeat(56));
    await pool.end();
    process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (err) => {
    console.error('\nFATAL:', err);
    await pool.end().catch(() => {});
    process.exit(1);
});

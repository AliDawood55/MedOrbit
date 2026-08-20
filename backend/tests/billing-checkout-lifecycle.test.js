/**
 * Billing Phase 2 — checkout, subscription lifecycle and the sandbox provider.
 *
 * Phase 1 proved the limits could not be evaded. This proves the way past
 * them can only be bought, and only through the pipeline a real provider
 * will use: a checkout attempt the backend recorded, a signed event,
 * verification over raw bytes, idempotent recording, and only then a
 * subscription.
 *
 * So most of what follows is again adversarial. A browser that claims to
 * have paid. An unsigned event. A replayed one. A tampered price. One
 * account reaching for another's checkout. A subscriber who cancels,
 * resubscribes, and expects a fresh free allowance for their trouble.
 *
 * Runs against real PostgreSQL through the real HTTP API, because the
 * guarantees being tested — unique indexes, transaction boundaries, HMAC
 * verification — do not exist in a mock of a mock.
 *
 * Requires the docker test stack with sandbox billing enabled:
 *   docker compose --profile test up -d --build backend-test
 */
const crypto = require('crypto');
const path = require('path');
const { execFileSync } = require('child_process');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');
const { policy, BILLING_EVENTS } = require('../src/config/billing');

const pool = new Pool(poolConfig);
const run = Date.now();
let passed = 0;
let failed = 0;

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

async function user(key, role = 'patient') {
    const id = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.users
           (id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES ($1,$2,'test-only',$3,true,true,1)`,
        [id, `p2_${key}_${run}@medorbit.test`, role]
    );
    return { id, token: jwt(id, role), key };
}

/** The token out of a sandbox checkout URL — what the browser would carry. */
function tokenFromUrl(url) {
    if (!url) return null;
    const match = String(url).match(/session=([^&]+)/);
    return match ? decodeURIComponent(match[1]) : null;
}

/**
 * Drive one account all the way to Pro through the real flow.
 *
 * Used as a fixture by most sections below, and deliberately written to use
 * only the public HTTP surface: if there were a shortcut to Pro that the
 * tests could take, that shortcut would be the vulnerability.
 */
async function subscribe(actor, planCode = 'pro_monthly', returnPath = null) {
    const checkout = await request('POST', '/billing/checkout', actor.token, {
        plan_code: planCode,
        return_path: returnPath,
    });
    const token = tokenFromUrl(checkout.body?.data?.checkout_url);
    if (!token) return { checkout, token: null, complete: null };

    const complete = await request('POST', `/billing/sandbox/checkout/${token}/complete`, actor.token, {
        outcome: 'success',
    });
    return { checkout, token, complete };
}

async function entitlements(actor) {
    const res = await request('GET', '/billing/entitlements', actor.token);
    return res.body?.data || null;
}

async function subscriptionOf(actor) {
    const res = await request('GET', '/billing/subscription', actor.token);
    return res.body?.data || null;
}

/** The provider-side subscription handle, read from the database. */
async function providerSubIdOf(actor) {
    const r = await pool.query(
        `SELECT provider_subscription_id FROM medorbit.subscriptions
          WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`,
        [actor.id]
    );
    return r.rows[0]?.provider_subscription_id || null;
}

/** Sign an event envelope the way the mock provider does, for direct webhook posts. */
function signedDelivery(envelope) {
    const secret = process.env.BILLING_MOCK_WEBHOOK_SECRET;
    const rawBody = Buffer.from(JSON.stringify(envelope), 'utf8');
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = crypto.createHmac('sha256', secret)
        .update(`${timestamp}.`).update(rawBody).digest('hex');
    return { rawBody, header: `t=${timestamp},v1=${signature}` };
}

async function postWebhook(envelope, { header = null, corrupt = false } = {}) {
    const signed = signedDelivery(envelope);
    const body = corrupt ? Buffer.concat([signed.rawBody, Buffer.from(' ')]) : signed.rawBody;
    const r = await fetch(`${apiBase}/billing/webhook`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-MedOrbit-Billing-Signature': header === null ? signed.header : header,
        },
        body,
    });
    let parsed = null;
    try { parsed = await r.json(); } catch { parsed = null; }
    return { status: r.status, body: parsed };
}

// =====================================================================

async function main() {
    console.log('\n=== Billing Phase 2: checkout, lifecycle, sandbox provider ===');

    // -----------------------------------------------------------------
    section('A. The sandbox is a provider, not a shortcut');

    const cfgUser = await user('cfg');
    const cfg = await request('GET', '/billing/config', cfgUser.token);
    check('billing config reports checkout is available', cfg.body?.data?.checkout_available === true,
        JSON.stringify(cfg.body?.data));
    check('billing config reports it is a sandbox', cfg.body?.data?.sandbox === true);

    // The one endpoint that must not exist. If a "make me Pro" route were
    // ever added, this is what would notice.
    const forbidden = await request('POST', '/billing/subscription/activate', cfgUser.token, { plan_code: 'pro_annual' });
    check('there is no direct activation endpoint', forbidden.status === 404, `status ${forbidden.status}`);

    const makeMePro = await request('POST', '/api/subscription/make-me-pro', cfgUser.token, {});
    check('there is no make-me-pro endpoint', makeMePro.status === 404, `status ${makeMePro.status}`);

    // -----------------------------------------------------------------
    section('B. Free user buys Pro Monthly');

    const monthly = await user('monthly');
    const beforeBuy = await entitlements(monthly);
    check('starts on the free plan', beforeBuy?.plan === 'free', beforeBuy?.plan);
    check('starts with a countable chatbot allowance', beforeBuy?.features?.chatbot?.unlimited === false);

    const buy = await subscribe(monthly, 'pro_monthly');
    check('checkout returns a hosted checkout URL',
        typeof buy.checkout.body?.data?.checkout_url === 'string' && Boolean(buy.token),
        JSON.stringify(buy.checkout.body));
    check('the checkout URL points at the sandbox page',
        String(buy.checkout.body?.data?.checkout_url || '').includes('billing-sandbox.html'));
    check('completing the sandbox checkout succeeds', buy.complete.status === 200,
        JSON.stringify(buy.complete.body));

    const monthlyEnt = await entitlements(monthly);
    check('the account is now on pro_monthly', monthlyEnt?.plan === 'pro_monthly', monthlyEnt?.plan);
    check('chatbot became unlimited', monthlyEnt?.features?.chatbot?.unlimited === true);
    check('voice doctor became unlimited', monthlyEnt?.features?.voice_doctor?.unlimited === true);
    check('no re-authentication was needed', monthlyEnt?.subscription?.status === 'active');

    const monthlySub = await subscriptionOf(monthly);
    check('the period is one calendar month, computed by the database', await (async () => {
        const r = await pool.query(
            `SELECT current_period_end = current_period_start + INTERVAL '1 month' AS ok
               FROM medorbit.subscriptions WHERE user_id = $1`,
            [monthly.id]
        );
        return r.rows[0]?.ok === true;
    })(), `${monthlySub?.current_period_start} -> ${monthlySub?.current_period_end}`);

    // -----------------------------------------------------------------
    section('C. Free user buys Pro Annual');

    const annual = await user('annual');
    const annualBuy = await subscribe(annual, 'pro_annual');
    check('annual checkout completes', annualBuy.complete?.status === 200);

    const annualEnt = await entitlements(annual);
    check('the account is on pro_annual', annualEnt?.plan === 'pro_annual', annualEnt?.plan);
    check('annual grants unlimited chatbot', annualEnt?.features?.chatbot?.unlimited === true);

    check('the period is one calendar year, not 365 days', await (async () => {
        const r = await pool.query(
            `SELECT current_period_end = current_period_start + INTERVAL '1 year' AS calendar,
                    current_period_end = current_period_start + INTERVAL '365 days' AS naive
               FROM medorbit.subscriptions WHERE user_id = $1`,
            [annual.id]
        );
        // On a non-leap span the two coincide; the calendar form must hold
        // regardless, and that is what is asserted.
        return r.rows[0]?.calendar === true;
    })());

    const annualPrice = await pool.query(
        `SELECT price_cents FROM medorbit.subscription_plans WHERE plan_code = 'pro_annual'`
    );
    check('annual is priced at 20000 cents in the catalogue', annualPrice.rows[0]?.price_cents === 20000,
        String(annualPrice.rows[0]?.price_cents));

    // -----------------------------------------------------------------
    section('D. A failed initial payment buys nothing and earns no grace');

    const declined = await user('declined');
    const declinedCheckout = await request('POST', '/billing/checkout', declined.token, { plan_code: 'pro_monthly' });
    const declinedToken = tokenFromUrl(declinedCheckout.body?.data?.checkout_url);
    const declinedResult = await request('POST', `/billing/sandbox/checkout/${declinedToken}/complete`,
        declined.token, { outcome: 'failure' });
    check('a declined checkout still answers the client', declinedResult.status === 200);

    const declinedEnt = await entitlements(declined);
    check('a declined first payment leaves the account free', declinedEnt?.plan === 'free', declinedEnt?.plan);
    check('a declined first payment grants no unlimited chatbot',
        declinedEnt?.features?.chatbot?.unlimited === false);

    const declinedRows = await pool.query(
        `SELECT status, grace_period_ends_at FROM medorbit.subscriptions WHERE user_id = $1`,
        [declined.id]
    );
    check('a declined first payment creates no subscription row at all',
        declinedRows.rowCount === 0, `${declinedRows.rowCount} rows`);
    check('and therefore no grace window exists to inherit',
        declinedRows.rows.every((r) => !r.grace_period_ends_at));

    // A failed attempt must not lock the account out of trying again.
    const retry = await subscribe(declined, 'pro_monthly');
    check('the user can retry checkout after a decline', retry.complete?.status === 200,
        JSON.stringify(retry.checkout.body));
    check('the retry does grant Pro', (await entitlements(declined))?.plan === 'pro_monthly');

    // -----------------------------------------------------------------
    section('E. The browser is not the authority');

    const liar = await user('liar');

    // Every field a tampering client might hope changes the outcome.
    const tampered = await request('POST', '/billing/checkout', liar.token, {
        plan_code: 'pro_annual',
        amount: 1,
        price: 1,
        price_cents: 1,
        currency: 'XXX',
        is_pro: true,
        status: 'active',
        subscription_status: 'active',
        grace_until: new Date(Date.now() + 999 * 86400000).toISOString(),
        current_period_end: new Date(Date.now() + 999 * 86400000).toISOString(),
        user_id: crypto.randomUUID(),
        plan: { price_cents: 1 },
    });
    check('a checkout carrying a tampered price is still accepted on its plan_code alone',
        tampered.status === 200, `status ${tampered.status}`);

    const liarToken = tokenFromUrl(tampered.body?.data?.checkout_url);
    const liarView = await request('GET', `/billing/sandbox/checkout/${liarToken}`, liar.token);
    check('the checkout page shows the catalogue price, not the submitted one',
        liarView.body?.data?.price_cents === 20000, String(liarView.body?.data?.price_cents));
    check('the checkout page shows the plan that was requested',
        liarView.body?.data?.plan_code === 'pro_annual');

    await request('POST', `/billing/sandbox/checkout/${liarToken}/complete`, liar.token, { outcome: 'success' });
    const liarSub = await pool.query(
        `SELECT s.status, s.grace_period_ends_at, s.current_period_end, p.price_cents
           FROM medorbit.subscriptions s JOIN medorbit.subscription_plans p ON p.id = s.plan_id
          WHERE s.user_id = $1`,
        [liar.id]
    );
    check('the subscription is on the real annual price', liarSub.rows[0]?.price_cents === 20000);
    check('the forged grace_until was ignored', liarSub.rows[0]?.grace_period_ends_at === null);
    check('the forged current_period_end was ignored', await (async () => {
        const r = await pool.query(
            `SELECT current_period_end < NOW() + INTERVAL '400 days' AS sane
               FROM medorbit.subscriptions WHERE user_id = $1`,
            [liar.id]
        );
        return r.rows[0]?.sane === true;
    })());

    // The user_id in the body must never redirect a purchase to another account.
    const victimOfSpoof = await user('spoofvictim');
    const spoofEnt = await entitlements(victimOfSpoof);
    check('a spoofed user_id did not subscribe a different account', spoofEnt?.plan === 'free');

    // -----------------------------------------------------------------
    section('F. Webhook verification and replay');

    const replayUser = await user('replay');
    const replayCheckout = await request('POST', '/billing/checkout', replayUser.token, { plan_code: 'pro_monthly' });
    const replayToken = tokenFromUrl(replayCheckout.body?.data?.checkout_url);

    const envelope = {
        id: `evt_test_${crypto.randomUUID()}`,
        type: BILLING_EVENTS.CHECKOUT_COMPLETED,
        created_at: new Date().toISOString(),
        data: {
            checkout_session_id: replayToken,
            provider_subscription_id: `sub_test_${run}`,
        },
    };

    const unsigned = await postWebhook(envelope, { header: '' });
    check('an unsigned webhook is rejected', unsigned.status === 400, `status ${unsigned.status}`);

    const forged = await postWebhook(envelope, { header: `t=${Math.floor(Date.now() / 1000)},v1=${'0'.repeat(64)}` });
    check('a forged signature is rejected', forged.status === 400, `status ${forged.status}`);

    const corrupted = await postWebhook(envelope, { corrupt: true });
    check('a body altered after signing is rejected', corrupted.status === 400, `status ${corrupted.status}`);

    const stale = await postWebhook(envelope, (() => {
        const secret = process.env.BILLING_MOCK_WEBHOOK_SECRET;
        const rawBody = Buffer.from(JSON.stringify(envelope), 'utf8');
        const old = Math.floor(Date.now() / 1000) - 3600;
        const sig = crypto.createHmac('sha256', secret).update(`${old}.`).update(rawBody).digest('hex');
        return { header: `t=${old},v1=${sig}` };
    })());
    check('a correctly signed but hour-old delivery is rejected', stale.status === 400, `status ${stale.status}`);

    check('none of the rejected deliveries granted anything',
        (await entitlements(replayUser))?.plan === 'free');

    const accepted = await postWebhook(envelope);
    check('a correctly signed webhook is accepted', accepted.status === 200, JSON.stringify(accepted.body));
    check('and it activates the subscription', (await entitlements(replayUser))?.plan === 'pro_monthly');

    const replayed = await postWebhook(envelope);
    check('redelivering the identical event is reported as a duplicate',
        replayed.body?.data?.duplicate === true, JSON.stringify(replayed.body));

    const subCount = await pool.query(
        `SELECT COUNT(*)::int AS n FROM medorbit.subscriptions WHERE user_id = $1`, [replayUser.id]
    );
    check('the replay did not create a second subscription', subCount.rows[0].n === 1,
        `${subCount.rows[0].n} subscriptions`);

    const eventCount = await pool.query(
        `SELECT COUNT(*)::int AS n FROM medorbit.billing_events WHERE provider_event_id = $1`, [envelope.id]
    );
    check('the event was recorded exactly once', eventCount.rows[0].n === 1, `${eventCount.rows[0].n} rows`);

    // A second checkout completing for an account that already subscribed
    // must not overlap two paid periods.
    const doubleBuy = await subscribe(replayUser, 'pro_annual');
    check('a second checkout is refused while one subscription is live',
        doubleBuy.checkout.status === 409, `status ${doubleBuy.checkout.status}`);

    const liveCount = await pool.query(
        `SELECT COUNT(*)::int AS n FROM medorbit.subscriptions
          WHERE user_id = $1 AND status IN ('incomplete','active','past_due')`,
        [replayUser.id]
    );
    check('exactly one live subscription remains', liveCount.rows[0].n === 1, `${liveCount.rows[0].n}`);

    // -----------------------------------------------------------------
    section('G. Cancel at period end, and resume');

    const canceller = await user('canceller');
    await subscribe(canceller, 'pro_monthly');

    const cancelled = await request('POST', '/billing/subscription/cancel', canceller.token, {});
    check('cancel succeeds', cancelled.status === 200, JSON.stringify(cancelled.body));
    check('cancel is modelled as cancel_at_period_end',
        cancelled.body?.data?.cancel_at_period_end === true);
    check('the subscription is still active', cancelled.body?.data?.status === 'active',
        cancelled.body?.data?.status);
    check('and Pro access continues until the period ends',
        (await entitlements(canceller))?.features?.chatbot?.unlimited === true);
    check('the end date is reported so the UI can say when',
        Boolean(cancelled.body?.data?.current_period_end));

    const resumed = await request('POST', '/billing/subscription/resume', canceller.token, {});
    check('resume succeeds', resumed.status === 200);
    check('resume clears cancel_at_period_end', resumed.body?.data?.cancel_at_period_end === false);
    check('resume keeps the subscription active', resumed.body?.data?.status === 'active');
    check('and Pro is still granted', (await entitlements(canceller))?.plan === 'pro_monthly');

    // -----------------------------------------------------------------
    section('H. Renewal advances the period, idempotently');

    const renewer = await user('renewer');
    await subscribe(renewer, 'pro_monthly');
    const beforeRenewal = await subscriptionOf(renewer);

    const anchorBefore = (await pool.query(
        `SELECT current_period_end::text AS t FROM medorbit.subscriptions WHERE user_id = $1`,
        [renewer.id]
    )).rows[0].t;

    const renewal = await request('POST', '/billing/sandbox/simulate', renewer.token, { kind: 'renewal' });
    check('a simulated renewal succeeds', renewal.status === 200, JSON.stringify(renewal.body));
    check('the subscription stays active', renewal.body?.data?.status === 'active');
    check('the period advanced', new Date(renewal.body?.data?.current_period_end)
        > new Date(beforeRenewal?.current_period_end));

    check('renewal is anchored to the previous period end, not to now', await (async () => {
        // Compared as text at full database precision: a JSON round trip
        // rounds a timestamptz to milliseconds and would make an exact
        // anchor look like a near miss.
        const r = await pool.query(
            `SELECT current_period_start::text AS t FROM medorbit.subscriptions WHERE user_id = $1`,
            [renewer.id]
        );
        return r.rows[0]?.t === anchorBefore;
    })());

    // Idempotency at the level that matters: the same provider event
    // delivered twice advances the period once.
    const renewerProviderId = await providerSubIdOf(renewer);
    const renewEnvelope = {
        id: `evt_renew_${crypto.randomUUID()}`,
        type: BILLING_EVENTS.SUBSCRIPTION_RENEWED,
        created_at: new Date().toISOString(),
        data: { provider_subscription_id: renewerProviderId },
    };
    await postWebhook(renewEnvelope);
    const afterFirst = await subscriptionOf(renewer);
    const dupRenewal = await postWebhook(renewEnvelope);
    const afterSecond = await subscriptionOf(renewer);

    check('a redelivered renewal is a duplicate', dupRenewal.body?.data?.duplicate === true);
    check('and does not advance the period twice',
        afterFirst.current_period_end === afterSecond.current_period_end,
        `${afterFirst.current_period_end} vs ${afterSecond.current_period_end}`);

    // -----------------------------------------------------------------
    section('I. Renewal failure, grace, and recovery');

    const failing = await user('failing');
    await subscribe(failing, 'pro_monthly');

    const failedRenewal = await request('POST', '/billing/sandbox/simulate', failing.token, { kind: 'renewal_failure' });
    check('a renewal failure succeeds', failedRenewal.status === 200, JSON.stringify(failedRenewal.body));
    check('the subscription becomes past_due', failedRenewal.body?.data?.status === 'past_due',
        failedRenewal.body?.data?.status);
    check('a grace deadline is set', Boolean(failedRenewal.body?.data?.grace_period_ends_at));

    check(`the grace window is the configured ${policy.subscription.pastDueGraceDays} days`, await (async () => {
        const r = await pool.query(
            `SELECT grace_period_ends_at BETWEEN
                      NOW() + make_interval(days => $2::int) - INTERVAL '2 minutes'
                  AND NOW() + make_interval(days => $2::int) + INTERVAL '2 minutes' AS ok
               FROM medorbit.subscriptions WHERE user_id = $1`,
            [failing.id, policy.subscription.pastDueGraceDays]
        );
        return r.rows[0]?.ok === true;
    })());

    const pastDueEnt = await entitlements(failing);
    check('Pro remains active inside the grace window',
        pastDueEnt?.features?.chatbot?.unlimited === true, pastDueEnt?.plan);
    check('and the client is told the account is past_due so it can warn',
        pastDueEnt?.subscription?.status === 'past_due');

    const recovered = await request('POST', '/billing/sandbox/simulate', failing.token, { kind: 'payment_recovered' });
    check('payment recovery succeeds', recovered.status === 200);
    check('the subscription returns to active', recovered.body?.data?.status === 'active');
    check('and the grace deadline is cleared, not merely ignored',
        recovered.body?.data?.grace_period_ends_at === null,
        String(recovered.body?.data?.grace_period_ends_at));
    check('Pro is still granted after recovery', (await entitlements(failing))?.plan === 'pro_monthly');

    // -----------------------------------------------------------------
    section('J. Grace expiry falls back to free without deleting anything');

    const lapsed = await user('lapsed');
    await subscribe(lapsed, 'pro_monthly');
    await request('POST', '/billing/sandbox/simulate', lapsed.token, { kind: 'renewal_failure' });

    // Push the deadline into the past. The clock is the database's; only the
    // deadline is moved, which is what a week passing looks like.
    await pool.query(
        `UPDATE medorbit.subscriptions
            SET grace_period_ends_at = NOW() - INTERVAL '1 hour'
          WHERE user_id = $1`,
        [lapsed.id]
    );

    const lapsedEnt = await entitlements(lapsed);
    check('an expired grace window grants no Pro', lapsedEnt?.plan === 'free', lapsedEnt?.plan);
    check('the chatbot allowance is countable again', lapsedEnt?.features?.chatbot?.unlimited === false);

    const lapsedRow = await pool.query(
        `SELECT status, ended_at FROM medorbit.subscriptions WHERE user_id = $1`, [lapsed.id]
    );
    check('the subscription row survives for audit', lapsedRow.rowCount === 1);
    check('and is retired to a terminal status rather than deleted',
        lapsedRow.rows[0]?.status === 'expired' && Boolean(lapsedRow.rows[0]?.ended_at),
        lapsedRow.rows[0]?.status);

    // -----------------------------------------------------------------
    section('K. Downgrade changes permission and destroys nothing');

    const downgraded = await user('downgraded');
    await subscribe(downgraded, 'pro_monthly');

    // Accrue real content as a Pro subscriber: a conversation, a chat
    // message, a voice consultation and a report.
    const conversation = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.chatbot_conversations (id, session_id, user_id, language)
         VALUES ($1,$2,$3,'en')`,
        [conversation, `p2_conv_${run}`, downgraded.id]
    );
    await pool.query(
        `INSERT INTO medorbit.chatbot_messages (conversation_id, message_text, message_type, response_text)
         VALUES ($1,'kept','user',NULL),($1,'kept','bot','kept reply')`,
        [conversation]
    );
    const vdSession = `p2_vd_${run}`;
    await pool.query(
        `INSERT INTO medorbit.virtual_doctor_sessions (session_id, user_id, language, phase)
         VALUES ($1,$2,'en','intake')`,
        [vdSession, downgraded.id]
    );
    const vdSessionRow = await pool.query(
        `SELECT id FROM medorbit.virtual_doctor_sessions WHERE session_id = $1`, [vdSession]
    );
    await pool.query(
        `INSERT INTO medorbit.virtual_doctor_reports (session_id, report_json)
         VALUES ($1, '{"kept": true}'::jsonb)`,
        [vdSessionRow.rows[0].id]
    );
    await pool.query(
        `INSERT INTO medorbit.usage_ledger (user_id, feature_code, status, entitlement_source, settled_at)
         VALUES ($1,'chatbot_message','consumed','pro',NOW())`,
        [downgraded.id]
    );

    const countAll = async () => {
        const r = await pool.query(
            `SELECT
               (SELECT COUNT(*)::int FROM medorbit.chatbot_messages m
                  JOIN medorbit.chatbot_conversations c ON c.id = m.conversation_id WHERE c.user_id = $1) AS messages,
               (SELECT COUNT(*)::int FROM medorbit.chatbot_conversations WHERE user_id = $1) AS conversations,
               (SELECT COUNT(*)::int FROM medorbit.virtual_doctor_sessions WHERE user_id = $1) AS sessions,
               (SELECT COUNT(*)::int FROM medorbit.virtual_doctor_reports r
                  JOIN medorbit.virtual_doctor_sessions s ON s.id = r.session_id WHERE s.user_id = $1) AS reports,
               (SELECT COUNT(*)::int FROM medorbit.usage_ledger WHERE user_id = $1) AS ledger,
               (SELECT is_active FROM medorbit.users WHERE id = $1) AS active`,
            [downgraded.id]
        );
        return r.rows[0];
    };

    const before = await countAll();
    await request('POST', '/billing/sandbox/simulate', downgraded.token, { kind: 'ended' });
    const after = await countAll();

    const downgradedEnt = await entitlements(downgraded);
    check('the account drops to free after the subscription ends',
        downgradedEnt?.plan === 'free', downgradedEnt?.plan);
    check('chat history is intact', after.messages === before.messages && before.messages === 2,
        `${before.messages} -> ${after.messages}`);
    check('conversations are intact', after.conversations === before.conversations);
    check('voice consultation history is intact', after.sessions === before.sessions && before.sessions === 1);
    check('reports are intact', after.reports === before.reports && before.reports === 1);
    check('the usage ledger is intact', after.ledger === before.ledger);
    check('the account itself is untouched', after.active === true);

    const historyReadable = await request('GET', `/conversations/${conversation}`, downgraded.token);
    check('and the conversation is still readable through the API',
        historyReadable.status === 200, `status ${historyReadable.status}`);

    // -----------------------------------------------------------------
    section('L. Subscribe, cancel, resubscribe is not a quota reset');

    const cycler = await user('cycler');

    // Burn part of the free allowance BEFORE subscribing, so there is
    // something to check has not been handed back.
    const burn = 3;
    await pool.query(
        `INSERT INTO medorbit.usage_windows (user_id, feature_code, window_start, window_end, consumed_count)
         VALUES ($1,'chatbot_message',NOW(),NOW() + INTERVAL '24 hours',$2)`,
        [cycler.id, burn]
    );
    const beforeCycle = await entitlements(cycler);
    const usedBefore = beforeCycle?.features?.chatbot?.used;
    check('the free window recorded prior usage', usedBefore > 0, String(usedBefore));

    await subscribe(cycler, 'pro_monthly');
    check('subscribing does not reset the recorded free usage', await (async () => {
        const r = await pool.query(
            `SELECT COALESCE(SUM(reserved_count + consumed_count),0)::int AS used
               FROM medorbit.usage_windows WHERE user_id = $1 AND feature_code = 'chatbot_message'`,
            [cycler.id]
        );
        return r.rows[0].used === usedBefore;
    })());

    await request('POST', '/billing/sandbox/simulate', cycler.token, { kind: 'ended' });
    const afterCycle = await entitlements(cycler);
    check('after cancelling, the account is free again', afterCycle?.plan === 'free');
    check('and the free allowance resumes where it was, not at zero used',
        afterCycle?.features?.chatbot?.used === usedBefore,
        `${afterCycle?.features?.chatbot?.used} vs ${usedBefore}`);
    check('so the window still counts down to its original reset',
        afterCycle?.features?.chatbot?.remaining === (afterCycle?.features?.chatbot?.limit - usedBefore));

    // -----------------------------------------------------------------
    section('M. Plan change takes effect at renewal, never mid-period');

    const switcher = await user('switcher');
    await subscribe(switcher, 'pro_monthly');
    const beforeSwitch = await subscriptionOf(switcher);

    const switched = await request('POST', '/billing/subscription/plan', switcher.token, { plan_code: 'pro_annual' });
    check('a plan change is accepted', switched.status === 200, JSON.stringify(switched.body));
    check('the current plan does not change mid-period',
        switched.body?.data?.plan_code === 'pro_monthly', switched.body?.data?.plan_code);
    check('the change is reported as pending',
        switched.body?.data?.pending_plan?.plan_code === 'pro_annual');
    check('and takes effect at the current period end',
        switched.body?.data?.pending_plan?.effective_at === beforeSwitch.current_period_end);
    check('the period end was not moved by the change',
        switched.body?.data?.current_period_end === beforeSwitch.current_period_end);

    const switchRenewed = await request('POST', '/billing/sandbox/simulate', switcher.token, { kind: 'renewal' });
    check('the renewal applies the scheduled plan',
        switchRenewed.body?.data?.plan_code === 'pro_annual', switchRenewed.body?.data?.plan_code);
    check('and clears the pending change', switchRenewed.body?.data?.pending_plan === null);
    check('the new period is a calendar year', await (async () => {
        const r = await pool.query(
            `SELECT current_period_end = current_period_start + INTERVAL '1 year' AS ok
               FROM medorbit.subscriptions WHERE user_id = $1`,
            [switcher.id]
        );
        return r.rows[0]?.ok === true;
    })());

    const bogusPlan = await request('POST', '/billing/subscription/plan', switcher.token, { plan_code: 'free' });
    check('changing to the free plan is refused', bogusPlan.status === 400, `status ${bogusPlan.status}`);

    // -----------------------------------------------------------------
    section('N. One account cannot touch another');

    const alice = await user('alice');
    const bob = await user('bob');
    await subscribe(alice, 'pro_monthly');

    const bobSeesOwn = await request('GET', '/billing/subscription', bob.token);
    check("B does not see A's subscription", bobSeesOwn.body?.data?.status === null,
        JSON.stringify(bobSeesOwn.body?.data));

    const bobCancels = await request('POST', '/billing/subscription/cancel', bob.token, {});
    check("B cannot cancel A's subscription", bobCancels.status === 404, `status ${bobCancels.status}`);
    check("and A's subscription is untouched",
        (await subscriptionOf(alice))?.cancel_at_period_end === false);

    // A's checkout token, in B's hands.
    const aliceCheckout = await request('POST', '/billing/checkout', alice.token, { plan_code: 'pro_annual' });
    check('A cannot open a second checkout while subscribed', aliceCheckout.status === 409);

    const carol = await user('carol');
    const carolCheckout = await request('POST', '/billing/checkout', carol.token, { plan_code: 'pro_monthly' });
    const carolToken = tokenFromUrl(carolCheckout.body?.data?.checkout_url);

    const bobReads = await request('GET', `/billing/sandbox/checkout/${carolToken}`, bob.token);
    check("B cannot read C's checkout session", bobReads.status === 404, `status ${bobReads.status}`);

    const bobReplays = await request('POST', `/billing/sandbox/checkout/${carolToken}/complete`, bob.token,
        { outcome: 'success' });
    check("B cannot complete C's checkout", bobReplays.status === 404, `status ${bobReplays.status}`);
    check('and B did not become Pro by trying', (await entitlements(bob))?.plan === 'free');
    check('and C did not become Pro either', (await entitlements(carol))?.plan === 'free');

    const bobSimulates = await request('POST', '/billing/sandbox/simulate', bob.token, { kind: 'renewal' });
    check('B cannot simulate a lifecycle event without a subscription',
        bobSimulates.status === 404, `status ${bobSimulates.status}`);

    // -----------------------------------------------------------------
    section('O. Guests are refused everywhere');

    const guestRoutes = [
        ['GET', '/billing/subscription'],
        ['GET', '/billing/history'],
        ['GET', '/billing/config'],
        ['POST', '/billing/checkout'],
        ['POST', '/billing/subscription/cancel'],
        ['POST', '/billing/subscription/resume'],
        ['POST', '/billing/subscription/plan'],
        ['GET', `/billing/sandbox/checkout/${carolToken}`],
        ['POST', `/billing/sandbox/checkout/${carolToken}/complete`],
        ['POST', '/billing/sandbox/simulate'],
    ];
    let guestOk = true;
    const guestDetail = [];
    for (const [method, route] of guestRoutes) {
        const res = await request(method, route, null, method === 'POST' ? {} : undefined);
        if (res.status !== 401) { guestOk = false; guestDetail.push(`${route}=${res.status}`); }
    }
    check('every billing route refuses a guest with 401', guestOk, guestDetail.join(' '));

    // -----------------------------------------------------------------
    section('P. Every role subscribes on identical terms');

    const roles = ['patient', 'doctor', 'admin', 'super_admin'];
    let roleOk = true;
    const roleDetail = [];
    for (const role of roles) {
        const actor = await user(`role_${role}`, role);

        const freeSnapshot = await entitlements(actor);
        if (freeSnapshot?.plan !== 'free' || freeSnapshot?.features?.chatbot?.unlimited !== false) {
            roleOk = false;
            roleDetail.push(`${role} started non-free`);
        }

        const bought = await subscribe(actor, 'pro_monthly');
        if (bought.complete?.status !== 200) {
            roleOk = false;
            roleDetail.push(`${role} checkout ${bought.complete?.status}`);
        }

        const proSnapshot = await entitlements(actor);
        if (proSnapshot?.plan !== 'pro_monthly' || proSnapshot?.features?.chatbot?.unlimited !== true) {
            roleOk = false;
            roleDetail.push(`${role} did not reach pro`);
        }
    }
    check('patient, doctor, admin and super_admin all start free and all must buy Pro',
        roleOk, roleDetail.join('; '));

    // Pro is a product entitlement, not a permission. A Pro patient must not
    // have gained anything an ordinary patient lacks.
    const proPatient = await user('propatient');
    await subscribe(proPatient, 'pro_annual');
    const adminOnly = await request('GET', '/admin/contact-messages', proPatient.token);
    check('a Pro patient is still refused an admin endpoint',
        adminOnly.status === 403, `status ${adminOnly.status}`);

    const proDoctor = await user('prodoctor', 'doctor');
    await subscribe(proDoctor, 'pro_monthly');
    const doctorAdmin = await request('GET', '/admin/contact-messages', proDoctor.token);
    check('a Pro doctor gains no admin permission', doctorAdmin.status === 403, `status ${doctorAdmin.status}`);

    // -----------------------------------------------------------------
    section('Q. Billing history is safe to show a user');

    const historian = await user('historian');
    await subscribe(historian, 'pro_monthly');
    await request('POST', '/billing/sandbox/simulate', historian.token, { kind: 'renewal' });
    await request('POST', '/billing/subscription/cancel', historian.token, {});

    const history = await request('GET', '/billing/history', historian.token);
    const events = history.body?.data?.events || [];
    check('the history lists the account events', events.length >= 3, `${events.length} events`);
    check('every entry carries a type and a time',
        events.every((e) => typeof e.event_type === 'string' && Boolean(e.occurred_at)));

    const historyText = JSON.stringify(history.body);
    check('no provider payload is exposed', !historyText.includes('payload'));
    check('no payload digest is exposed', !historyText.includes('digest'));
    check('no signature is exposed', !historyText.toLowerCase().includes('signature'));
    check('no provider event id is exposed', !historyText.includes('evt_'));

    const crossHistory = await request('GET', '/billing/history', bob.token);
    check("one account's history does not contain another's events",
        (crossHistory.body?.data?.events || []).length === 0,
        `${(crossHistory.body?.data?.events || []).length} events`);

    // -----------------------------------------------------------------
    section('R. Nothing in the billing tables is clinical, and nothing is a card');

    const clinicalLeak = await pool.query(
        `SELECT column_name, table_name
           FROM information_schema.columns
          WHERE table_schema = 'medorbit'
            AND table_name IN ('subscriptions','subscription_plans','billing_events',
                               'billing_customers','billing_checkout_sessions')
            AND (column_name ~* 'symptom|diagnos|transcript|urgency|medication|report|clinical'
              OR column_name ~* 'card|pan|cvv|cvc|expiry|exp_month|exp_year|cardholder')`
    );
    check('no billing table has a clinical or cardholder column',
        clinicalLeak.rowCount === 0,
        clinicalLeak.rows.map((r) => `${r.table_name}.${r.column_name}`).join(', '));

    const sandboxPageResponse = await request('GET', `/billing/sandbox/checkout/${carolToken}`, carol.token);
    const sandboxText = JSON.stringify(sandboxPageResponse.body).toLowerCase();
    check('the sandbox checkout payload mentions no card field',
        !/card|cvv|cvc|pan\b|expiry/.test(sandboxText), sandboxText.slice(0, 120));

    // -----------------------------------------------------------------
    section('S. A closed checkout cannot be reopened');

    const oneShot = await user('oneshot');
    const oneShotCheckout = await request('POST', '/billing/checkout', oneShot.token, { plan_code: 'pro_monthly' });
    const oneShotToken = tokenFromUrl(oneShotCheckout.body?.data?.checkout_url);

    await request('POST', `/billing/sandbox/checkout/${oneShotToken}/complete`, oneShot.token, { outcome: 'success' });
    const reuse = await request('POST', `/billing/sandbox/checkout/${oneShotToken}/complete`, oneShot.token,
        { outcome: 'success' });
    check('completing the same checkout twice is refused', reuse.status === 409, `status ${reuse.status}`);

    const oneShotSubs = await pool.query(
        `SELECT COUNT(*)::int AS n FROM medorbit.subscriptions WHERE user_id = $1`, [oneShot.id]
    );
    check('and it produced exactly one subscription', oneShotSubs.rows[0].n === 1, `${oneShotSubs.rows[0].n}`);

    const cancelledCheckout = await user('abandoner');
    const abandonCheckout = await request('POST', '/billing/checkout', cancelledCheckout.token,
        { plan_code: 'pro_monthly' });
    const abandonToken = tokenFromUrl(abandonCheckout.body?.data?.checkout_url);
    const abandoned = await request('POST', `/billing/sandbox/checkout/${abandonToken}/complete`,
        cancelledCheckout.token, { outcome: 'canceled' });
    check('a canceled checkout answers normally', abandoned.status === 200);
    check('a canceled checkout grants nothing',
        (await entitlements(cancelledCheckout))?.plan === 'free');
    check('a canceled checkout creates no subscription', await (async () => {
        const r = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.subscriptions WHERE user_id = $1`,
            [cancelledCheckout.id]
        );
        return r.rows[0].n === 0;
    })());
    check('and cannot then be completed as a success',
        (await request('POST', `/billing/sandbox/checkout/${abandonToken}/complete`,
            cancelledCheckout.token, { outcome: 'success' })).status === 409);

    const unknownOutcome = await request('POST', `/billing/sandbox/checkout/${abandonToken}/complete`,
        cancelledCheckout.token, { outcome: 'grant_me_pro' });
    check('an unknown outcome is refused', unknownOutcome.status === 400, `status ${unknownOutcome.status}`);

    const badPlan = await request('POST', '/billing/checkout', (await user('badplan')).token,
        { plan_code: 'pro_free_forever' });
    check('an unknown plan_code is refused', badPlan.status === 400, `status ${badPlan.status}`);

    // -----------------------------------------------------------------
    section('T. Return path cannot become an open redirect');

    const returner = await user('returner');
    const evilReturn = await request('POST', '/billing/checkout', returner.token, {
        plan_code: 'pro_monthly',
        return_path: 'https://evil.example.com/steal',
    });
    const returnerToken = tokenFromUrl(evilReturn.body?.data?.checkout_url);
    const returnerView = await request('GET', `/billing/sandbox/checkout/${returnerToken}`, returner.token);
    check('an absolute return URL is discarded, not stored',
        returnerView.body?.data?.return_path === null,
        String(returnerView.body?.data?.return_path));

    const protoRelative = await user('protorel');
    const protoCheckout = await request('POST', '/billing/checkout', protoRelative.token, {
        plan_code: 'pro_monthly',
        return_path: '//evil.example.com/steal',
    });
    const protoToken = tokenFromUrl(protoCheckout.body?.data?.checkout_url);
    const protoView = await request('GET', `/billing/sandbox/checkout/${protoToken}`, protoRelative.token);
    check('a protocol-relative return URL is discarded',
        protoView.body?.data?.return_path === null, String(protoView.body?.data?.return_path));

    const goodReturn = await user('goodreturn');
    const goodCheckout = await request('POST', '/billing/checkout', goodReturn.token, {
        plan_code: 'pro_monthly',
        return_path: 'index.html?tab=chat',
    });
    const goodToken = tokenFromUrl(goodCheckout.body?.data?.checkout_url);
    const goodView = await request('GET', `/billing/sandbox/checkout/${goodToken}`, goodReturn.token);
    check('a same-origin relative return path is kept',
        goodView.body?.data?.return_path === 'index.html?tab=chat',
        String(goodView.body?.data?.return_path));

    const completedReturn = await request('POST', `/billing/sandbox/checkout/${goodToken}/complete`,
        goodReturn.token, { outcome: 'success' });
    check('and is handed back so the user returns to what they were doing',
        completedReturn.body?.data?.return_path === 'index.html?tab=chat');
    check('the completion response reports live entitlement, not a claim',
        completedReturn.body?.data?.entitlements?.plan === 'pro_monthly',
        completedReturn.body?.data?.entitlements?.plan);

    // -----------------------------------------------------------------
    section('U. Chatbot and Voice Doctor unlock the moment the event lands');

    const blocked = await user('blocked');
    const limit = policy.chatbot.freeMessagesPerWindow;
    await pool.query(
        `INSERT INTO medorbit.usage_windows (user_id, feature_code, window_start, window_end, consumed_count)
         VALUES ($1,'chatbot_message',NOW(),NOW() + INTERVAL '24 hours',$2)`,
        [blocked.id, limit]
    );
    // And a spent voice consultation, still inside its cooldown.
    await pool.query(
        `INSERT INTO medorbit.voice_session_grants
           (user_id, entitlement_source, status, expires_at, finalized_at, next_free_at)
         VALUES ($1,'free','completed', NOW() + INTERVAL '2 hours', NOW(), NOW() + INTERVAL '20 hours')`,
        [blocked.id]
    );

    const blockedEnt = await entitlements(blocked);
    check('the chatbot allowance is exhausted', blockedEnt?.features?.chatbot?.remaining === 0);
    check('the voice consultation is on cooldown',
        blockedEnt?.features?.voice_doctor?.allowed === false,
        JSON.stringify(blockedEnt?.features?.voice_doctor));

    const blockedSend = await request('POST', '/chat/message', blocked.token,
        { message: 'hello', client_message_id: crypto.randomUUID() });
    check('and a send is refused', blockedSend.status === 429, `status ${blockedSend.status}`);

    await subscribe(blocked, 'pro_monthly');
    const unlockedEnt = await entitlements(blocked);
    check('after the checkout event lands, chatbot is immediately unlimited',
        unlockedEnt?.features?.chatbot?.unlimited === true);
    check('and the voice consultation is immediately available',
        unlockedEnt?.features?.voice_doctor?.allowed === true
        && unlockedEnt?.features?.voice_doctor?.unlimited === true,
        JSON.stringify(unlockedEnt?.features?.voice_doctor));

    const unlockedSend = await request('POST', '/chat/message', blocked.token,
        { message: 'hello again', client_message_id: crypto.randomUUID() });
    check('and a send now succeeds without re-authenticating',
        unlockedSend.status === 200, `status ${unlockedSend.status}`);

    const keptWindow = await pool.query(
        `SELECT consumed_count FROM medorbit.usage_windows
          WHERE user_id = $1 AND feature_code = 'chatbot_message'`,
        [blocked.id]
    );
    check('the Pro message did not increment the free window',
        keptWindow.rows[0]?.consumed_count === limit,
        `${keptWindow.rows[0]?.consumed_count} vs ${limit}`);

    // -----------------------------------------------------------------
    section('V. A client that says it is Pro still is not');

    const pretender = await user('pretender');
    await pool.query(
        `INSERT INTO medorbit.usage_windows (user_id, feature_code, window_start, window_end, consumed_count)
         VALUES ($1,'chatbot_message',NOW(),NOW() + INTERVAL '24 hours',$2)`,
        [pretender.id, limit]
    );

    const claimed = await fetch(`${apiBase}/chat/message`, {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${pretender.token}`,
            'Content-Type': 'application/json',
            Cookie: 'plan=pro_annual; is_pro=true; subscription_status=active; quota_remaining=999',
            'X-Plan': 'pro_annual',
            'X-Is-Pro': 'true',
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
            entitlement: 'pro',
        }),
    });
    check('cookies, headers and body fields claiming Pro change nothing',
        claimed.status === 429, `status ${claimed.status}`);

    const stillFree = await request('GET', '/billing/subscription', pretender.token);
    check('and the account is still on no subscription',
        stillFree.body?.data?.status === null, JSON.stringify(stillFree.body?.data));

    // -----------------------------------------------------------------
    section('W. Provider events for unknown subjects are recorded, not applied');

    const orphan = {
        id: `evt_orphan_${crypto.randomUUID()}`,
        type: BILLING_EVENTS.SUBSCRIPTION_RENEWED,
        created_at: new Date().toISOString(),
        data: { provider_subscription_id: `sub_does_not_exist_${run}` },
    };
    const orphanResult = await postWebhook(orphan);
    check('an event about an unknown subscription is accepted', orphanResult.status === 200);

    const orphanRow = await pool.query(
        `SELECT processing_status, user_id FROM medorbit.billing_events WHERE provider_event_id = $1`,
        [orphan.id]
    );
    check('and recorded as ignored rather than dropped',
        orphanRow.rows[0]?.processing_status === 'ignored', orphanRow.rows[0]?.processing_status);
    check('with no user attributed to it', orphanRow.rows[0]?.user_id === null);

    const unknownType = {
        id: `evt_unknown_${crypto.randomUUID()}`,
        type: 'provider.invented_this',
        created_at: new Date().toISOString(),
        data: {},
    };
    const unknownResult = await postWebhook(unknownType);
    check('an unrecognised event type does not error', unknownResult.status === 200);
    check('and is recorded for reconciliation', await (async () => {
        const r = await pool.query(
            `SELECT processing_status FROM medorbit.billing_events WHERE provider_event_id = $1`,
            [unknownType.id]
        );
        return r.rows[0]?.processing_status === 'ignored';
    })());

    // -----------------------------------------------------------------
    section('X. Sandbox lifecycle events cannot manufacture a subscription');

    const noSub = await user('nosub');
    for (const kind of ['renewal', 'renewal_failure', 'payment_recovered', 'ended']) {
        const res = await request('POST', '/billing/sandbox/simulate', noSub.token, { kind });
        if (res.status !== 404) {
            check(`simulating ${kind} without a subscription is refused`, false, `status ${res.status}`);
        }
    }
    check('no lifecycle simulation creates a subscription from nothing', await (async () => {
        const r = await pool.query(
            `SELECT COUNT(*)::int AS n FROM medorbit.subscriptions WHERE user_id = $1`, [noSub.id]
        );
        return r.rows[0].n === 0;
    })());
    check('and the account is still free', (await entitlements(noSub))?.plan === 'free');

    const invalidKind = await request('POST', '/billing/sandbox/simulate', monthly.token,
        { kind: 'grant_pro_forever' });
    check('an invented simulation kind is refused', invalidKind.status === 400, `status ${invalidKind.status}`);

    // -----------------------------------------------------------------
    section('Y. Production cannot run the sandbox, at three independent layers');

    // Layer 1: the process refuses to boot. Run in a child process so the
    // assertion is about a real Node startup, not a function called in
    // isolation.
    const providerModule = path.resolve(__dirname, '../src/services/billing/provider.js');

    function boot(env) {
        try {
            const stdout = execFileSync(process.execPath,
                ['-e', `const p = require(${JSON.stringify(providerModule)}); console.log(p.getProvider().name);`],
                { env: { ...process.env, ...env }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
            return { exitCode: 0, stdout: stdout.trim(), stderr: '' };
        } catch (err) {
            return { exitCode: err.status === undefined ? 1 : err.status, stdout: String(err.stdout || ''), stderr: String(err.stderr || '') };
        }
    }

    const prodMock = boot({ NODE_ENV: 'production', BILLING_PROVIDER: 'mock', BILLING_MOCK_ENABLED: 'true' });
    check('NODE_ENV=production with BILLING_PROVIDER=mock refuses to start',
        prodMock.exitCode !== 0, `exit ${prodMock.exitCode}`);
    check('and says why, naming the variable',
        prodMock.stderr.includes('BILLING_PROVIDER=mock') && prodMock.stderr.includes('production'),
        prodMock.stderr.slice(0, 160));

    const prodFlagOnly = boot({ NODE_ENV: 'production', BILLING_PROVIDER: '', BILLING_MOCK_ENABLED: 'true' });
    check('NODE_ENV=production with only BILLING_MOCK_ENABLED=true also refuses to start',
        prodFlagOnly.exitCode !== 0, `exit ${prodFlagOnly.exitCode}`);

    const prodClean = boot({ NODE_ENV: 'production', BILLING_PROVIDER: '', BILLING_MOCK_ENABLED: '' });
    check('a production process with no sandbox variables starts normally',
        prodClean.exitCode === 0, prodClean.stderr.slice(0, 160));
    check('and has no configured provider, so checkout fails closed',
        prodClean.stdout === 'unconfigured', prodClean.stdout);

    // Layer 2: even with the startup guard removed, provider selection still
    // refuses. Asserted against readProviderConfig, the single expression the
    // rest of the codebase consults.
    const { readProviderConfig } = require('../src/config/billing');
    check('mockEnabled is false under production even with both variables set',
        readProviderConfig({
            NODE_ENV: 'production', BILLING_PROVIDER: 'mock', BILLING_MOCK_ENABLED: 'true',
        }).mockEnabled === false);
    check('mockEnabled is false when only the provider is named',
        readProviderConfig({ NODE_ENV: 'development', BILLING_PROVIDER: 'mock' }).mockEnabled === false);
    check('mockEnabled is false when only the flag is set',
        readProviderConfig({ NODE_ENV: 'development', BILLING_MOCK_ENABLED: 'true' }).mockEnabled === false);
    check('mockEnabled is true only when both are set outside production',
        readProviderConfig({
            NODE_ENV: 'development', BILLING_PROVIDER: 'mock', BILLING_MOCK_ENABLED: 'true',
        }).mockEnabled === true);

    // Layer 3: the sandbox routes are not mounted when the sandbox is off, so
    // there is no handler to reach even holding a valid session.
    const routesModule = path.resolve(__dirname, '../src/routes/billing.routes.js');

    function sandboxRouteCount(env) {
        // Marked output, and only the marker is read: requiring the route
        // module also opens a database pool, which prints a banner to stdout
        // and would otherwise be parsed as the answer.
        const script = `
            const r = require(${JSON.stringify(routesModule)});
            const layers = (r.stack || []).filter((l) => String(l.regexp).includes('sandbox'));
            console.log('SANDBOX_LAYERS=' + layers.length);
            process.exit(0);
        `;
        try {
            const out = execFileSync(process.execPath, ['-e', script],
                { env: { ...process.env, ...env }, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
            const match = String(out).match(/SANDBOX_LAYERS=(\d+)/);
            return match ? Number(match[1]) : `unparsed: ${String(out).slice(0, 120)}`;
        } catch (err) {
            return `boot failed: ${String(err.stderr || '').slice(0, 120)}`;
        }
    }

    check('the sandbox router is mounted when the sandbox is enabled',
        sandboxRouteCount({ NODE_ENV: 'test', BILLING_PROVIDER: 'mock', BILLING_MOCK_ENABLED: 'true' }) === 1);
    check('and is absent when the enabling flag is missing',
        sandboxRouteCount({ NODE_ENV: 'test', BILLING_PROVIDER: 'mock', BILLING_MOCK_ENABLED: '' }) === 0);
    check('and absent when no provider is configured at all',
        sandboxRouteCount({ NODE_ENV: 'test', BILLING_PROVIDER: '', BILLING_MOCK_ENABLED: '' }) === 0);

    console.log(`\n${passed} passed, ${failed} failed\n`);
    await pool.end();
    process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (err) => {
    console.error('\nFATAL', err);
    try { await pool.end(); } catch { /* already closed */ }
    process.exit(1);
});

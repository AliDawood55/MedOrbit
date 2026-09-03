/**
 * Global authentication gate — backend half.
 *
 * Hiding HTML pages is not security. This asserts the API side of the same
 * policy: product data cannot be read by calling the API directly, the
 * endpoints authentication itself depends on stay reachable, and none of the
 * existing role restrictions were loosened on the way.
 *
 * Section F is the counterweight to all of that: admin invitation acceptance
 * needs a session and nothing more, because the invited account is not an
 * admin yet. The gate must classify that page as authenticated-only, and the
 * backend — not the page — is what keeps the wrong account out.
 *
 * Requires the docker test stack (see helpers/test-environment.js):
 *   npm run test:auth-gate:docker
 */
const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const run = Date.now();
let passed = 0;
let failed = 0;
const ids = {};

function check(name, ok, detail = '') {
    if (ok) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
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

async function user(key, role, overrides = {}) {
    ids[key] = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.users
           (id,email,password_hash,role,is_active,email_verified,authorization_version,deleted_at)
         VALUES ($1,$2,'test-only',$3,$4,$5,$6,$7)`,
        [
            ids[key],
            `authgate_${key}_${run}@medorbit.test`,
            role,
            overrides.isActive !== false,
            overrides.emailVerified !== false,
            overrides.authorizationVersion || 1,
            overrides.deletedAt || null,
        ]
    );
    return ids[key];
}

/**
 * Endpoints that were reachable anonymously before the guest policy and must
 * not be any more. Each is product data, not authentication infrastructure.
 */
const NOW_PROTECTED = [
    ['GET', '/clinics', 'clinic directory'],
    ['GET', '/clinics/nearby?lat=32.22&lng=35.26', 'nearby clinics'],
    ['GET', `/clinics/${crypto.randomUUID()}`, 'clinic detail'],
    ['GET', '/doctors', 'doctor directory'],
    ['GET', `/doctors/${crypto.randomUUID()}`, 'doctor profile'],
    ['GET', `/doctors/${crypto.randomUUID()}/availability`, 'doctor availability'],
    ['GET', `/doctors/${crypto.randomUUID()}/clinics`, "doctor's clinics"],
    ['GET', `/doctors/${crypto.randomUUID()}/posts`, "doctor's posts"],
    ['GET', `/doctors/${crypto.randomUUID()}/reviews`, 'doctor reviews'],
    ['GET', '/feed/posts', 'health feed'],
    ['GET', '/specialties', 'specialty list'],
    ['GET', `/specialties/${crypto.randomUUID()}`, 'specialty detail'],
    ['GET', '/appointments/available-slots', 'appointment slots'],
    ['GET', '/recommendations/doctors', 'doctor recommendations'],
    ['GET', '/health/events', 'outbox/Kafka telemetry'],
    ['POST', '/chat/message', 'AI chatbot', { message: 'hello' }],
    ['POST', '/ai/triage', 'AI symptom triage', { symptoms: ['headache'] }],
    ['POST', '/contact', 'contact form', { subject: 'hi', message: 'hello there' }],
];

/**
 * Endpoints that must stay reachable without a session, and why. Anything not
 * on this list is expected to require authentication.
 */
const STAYS_PUBLIC = [
    ['POST', '/auth/login', 'sign in', { email: `nobody_${run}@medorbit.test`, password: 'wrong-password' }],
    ['POST', '/auth/forgot-password', 'password recovery', { email: `nobody_${run}@medorbit.test` }],
    ['POST', '/auth/resend-verification', 'email verification', { email: `nobody_${run}@medorbit.test` }],
    ['GET', '/config', 'Google client id the sign-in button needs'],
    ['GET', '/health', 'infrastructure health check'],
    ['GET', '/feedback/stats', 'the one aggregate the public Home page renders'],
];

(async () => {
    try {
        console.log('\nGlobal authentication gate — backend policy\n');

        await user('patient', 'patient');
        await user('doctor', 'doctor');
        await user('admin', 'admin');
        await user('super', 'super_admin');
        await user('disabled', 'patient', { isActive: false });
        await user('unverified', 'patient', { emailVerified: false });
        await user('deleted', 'patient', { deletedAt: new Date().toISOString() });

        const patientToken = jwt(ids.patient, 'patient');
        const doctorToken = jwt(ids.doctor, 'doctor');
        const adminToken = jwt(ids.admin, 'admin');
        const superToken = jwt(ids.super, 'super_admin');
        await pool.query(
            `INSERT INTO medorbit.feedback
                (user_id, overall_rating, category_chatbot, category_clinics, comment, would_recommend)
             VALUES ($1, 5, 4, 5, 'Auth-gate test feedback', true)`,
            [ids.patient],
        );

        // ---------------------------------------------------------------
        // A. Product data is no longer anonymous
        // ---------------------------------------------------------------
        console.log('\n  A. Previously anonymous product endpoints');
        for (const [method, route, label, body] of NOW_PROTECTED) {
            const res = await request(method, route, null, body);
            check(`guest -> ${method} ${route} (${label}) is 401`,
                res.status === 401, `got ${res.status}`);
        }

        // Authenticating is enough to read the directory again — the policy is
        // "needs an account", not "needs a special role".
        const dirRes = await request('GET', '/doctors', patientToken);
        check('authenticated patient -> GET /doctors is 200', dirRes.status === 200, `got ${dirRes.status}`);
        const feedRes = await request('GET', '/feed/posts', patientToken);
        check('authenticated patient -> GET /feed/posts is 200', feedRes.status === 200, `got ${feedRes.status}`);
        const clinicRes = await request('GET', '/clinics', patientToken);
        check('authenticated patient -> GET /clinics is 200', clinicRes.status === 200, `got ${clinicRes.status}`);
        const specRes = await request('GET', '/specialties', patientToken);
        check('authenticated patient -> GET /specialties is 200', specRes.status === 200, `got ${specRes.status}`);

        // ---------------------------------------------------------------
        // B. Authentication infrastructure still works
        // ---------------------------------------------------------------
        console.log('\n  B. Endpoints that must remain public');
        for (const [method, route, label, body] of STAYS_PUBLIC) {
            const res = await request(method, route, null, body);
            check(`guest -> ${method} ${route} (${label}) is not 401`,
                res.status !== 401, `got ${res.status}`);
        }

        const configRes = await request('GET', '/config', null);
        check('GET /config returns the googleClientId field the button reads',
            configRes.status === 200 && configRes.body?.data && 'googleClientId' in configRes.body.data);

        // ---------------------------------------------------------------
        // C. Home's public aggregate exposes no identifiable users
        // ---------------------------------------------------------------
        console.log('\n  C. Home feedback aggregate');
        const statsGuest = await request('GET', '/feedback/stats', null);
        check('guest -> GET /feedback/stats is 200', statsGuest.status === 200, `got ${statsGuest.status}`);
        check('guest sees the aggregates Home renders',
            !!statsGuest.body?.data &&
            'total' in statsGuest.body.data &&
            'ratingDistribution' in statsGuest.body.data &&
            'categoryAverages' in statsGuest.body.data);
        check('guest is NOT given the list of users who left feedback',
            statsGuest.body?.data && !('users' in statsGuest.body.data),
            JSON.stringify(Object.keys(statsGuest.body?.data || {})));

        const statsAuthed = await request('GET', '/feedback/stats', patientToken);
        check('authenticated caller still receives the users list',
            statsAuthed.status === 200 && Array.isArray(statsAuthed.body?.data?.users));

        const reviewGuest = await request('GET', `/feedback/reviews/${ids.patient}`, null);
        check('guest cannot open an individual feedback review', reviewGuest.status === 401, `got ${reviewGuest.status}`);
        const reviewAuthed = await request('GET', `/feedback/reviews/${ids.patient}`, doctorToken);
        check('authenticated caller can open submitted review details only',
            reviewAuthed.status === 200 && reviewAuthed.body?.data?.reviews?.[0]?.overallRating === 5,
            `got ${reviewAuthed.status}`);

        // ---------------------------------------------------------------
        // D. A token is not a session — the server decides
        // ---------------------------------------------------------------
        console.log('\n  D. Session validity is decided server-side');
        check('garbage bearer token -> 401',
            (await request('GET', '/users/me', 'fake-token')).status === 401);
        check('structurally valid but unsigned token -> 401',
            (await request('GET', '/users/me', 'a.b.c')).status === 401);
        check('token for a deleted user -> 401',
            (await request('GET', '/users/me', jwt(ids.deleted, 'patient'))).status === 401);
        check('token for a disabled user -> 401',
            (await request('GET', '/users/me', jwt(ids.disabled, 'patient'))).status === 401);
        check('token for an unverified user -> 401',
            (await request('GET', '/users/me', jwt(ids.unverified, 'patient'))).status === 401);
        check('token with a stale authorizationVersion -> 401',
            (await request('GET', '/users/me', jwt(ids.patient, 'patient', 99))).status === 401);
        check('role claimed in the token does not grant admin access',
            (await request('GET', '/dashboard/stats', jwt(ids.patient, 'admin'))).status === 403,
            'a patient minting an admin claim must be resolved back to patient server-side');

        const meRes = await request('GET', '/users/me', patientToken);
        check('a valid session resolves GET /users/me (the gate\'s probe) with 200',
            meRes.status === 200, `got ${meRes.status}`);

        // ---------------------------------------------------------------
        // E. Authorization was not weakened by authentication
        // ---------------------------------------------------------------
        console.log('\n  E. Role restrictions preserved');
        check('patient -> admin analytics is 403',
            (await request('GET', '/dashboard/stats', patientToken)).status === 403);
        check('doctor -> admin analytics is 403',
            (await request('GET', '/dashboard/stats', doctorToken)).status === 403);
        check('admin -> admin analytics is 200',
            (await request('GET', '/dashboard/stats', adminToken)).status === 200);
        check('super_admin -> admin analytics is 200',
            (await request('GET', '/dashboard/stats', superToken)).status === 200);

        check('patient -> admin contact messages is 403',
            (await request('GET', '/admin/contact-messages', patientToken)).status === 403);
        check('doctor -> admin social moderation is 403',
            (await request('GET', '/admin/social/posts', doctorToken)).status === 403);
        check('admin -> super-admin invitations is 403',
            (await request('GET', '/admin/invitations', adminToken)).status === 403);
        check('super_admin -> super-admin invitations is 200',
            (await request('GET', '/admin/invitations', superToken)).status === 200);

        check('patient -> doctor-only patient list is 403',
            (await request('GET', '/doctors/me/patients', patientToken)).status === 403);
        check('doctor -> patient-only records timeline is 403',
            (await request('GET', '/patients/me/records', doctorToken)).status === 403);

        check('guest -> admin analytics is 401, not 403',
            (await request('GET', '/dashboard/stats', null)).status === 401,
            'an anonymous caller is unauthenticated, not merely unauthorised');

        // Newly protected operational telemetry is admin-only, not just
        // authenticated.
        check('patient -> outbox telemetry is 403',
            (await request('GET', '/health/events', patientToken)).status === 403);
        check('admin -> outbox telemetry is 200',
            (await request('GET', '/health/events', adminToken)).status === 200);

        // ---------------------------------------------------------------
        // F. Invitation acceptance is authenticated, not admin-only
        // ---------------------------------------------------------------
        // The one page whose route metadata is easy to get wrong. The gate
        // classifies admin-invitation-accept.html as PROTECTED and stops
        // there, because POST /admin/invitations/accept requires authenticate
        // and deliberately not authorizeAdmin — an invited account is not an
        // admin yet. What keeps a stranger out is the invitation's own
        // identity check, asserted here, not a role on the page.
        console.log('\n  F. Admin invitation acceptance');

        await user('invitee', 'patient');
        const inviteeEmail = `authgate_invitee_${run}@medorbit.test`;

        check('guest -> POST /admin/invitations/accept is 401',
            (await request('POST', '/admin/invitations/accept', null, { token: 'anything' })).status === 401,
            'the page needs a session, which is exactly what the gate enforces');

        const issued = await request('POST', '/admin/invitations', superToken, { email: inviteeEmail });
        check('super_admin -> issue an invitation is 201',
            issued.status === 201, JSON.stringify(issued.body));

        const acceptanceUrl = issued.body?.data?.acceptance_url || '';
        const invitationId = issued.body?.data?.invitation?.id;
        const rawToken = acceptanceUrl ? new URL(acceptanceUrl).searchParams.get('token') : null;
        check('the invitation link targets admin-invitation-accept.html with the token',
            acceptanceUrl.includes('/admin-invitation-accept.html?token=') && !!rawToken,
            acceptanceUrl);

        // The invited account is an ordinary patient at this point — the state
        // the accept page has to work in.
        const beforeRole = (await pool.query(
            'SELECT role FROM medorbit.users WHERE id=$1', [ids.invitee])).rows[0].role;
        check('the invited account is not an admin before accepting',
            beforeRole === 'patient', beforeRole);

        const stranger = await request('POST', '/admin/invitations/accept', patientToken, { token: rawToken });
        check('unrelated authenticated user -> invitation is rejected with 403',
            stranger.status === 403, `got ${stranger.status}`);
        check('the rejected caller gains no role from trying',
            (await pool.query('SELECT role FROM medorbit.users WHERE id=$1', [ids.patient])).rows[0].role === 'patient');

        check('authenticated caller with a bogus token -> 400, never a promotion',
            (await request('POST', '/admin/invitations/accept', patientToken, { token: 'not-a-real-token' })).status === 400);

        const inviteeToken = jwt(ids.invitee, 'patient');
        const accepted = await request('POST', '/admin/invitations/accept', inviteeToken, { token: rawToken });
        check('authenticated invited non-admin user -> reaches the acceptance flow',
            accepted.status === 200, JSON.stringify(accepted.body));

        const promoted = (await pool.query(
            'SELECT role, authorization_version FROM medorbit.users WHERE id=$1', [ids.invitee])).rows[0];
        check('acceptance promotes the invited account to admin',
            promoted.role === 'admin', promoted.role);
        check('the pre-acceptance token no longer works — the user signs in again',
            (await request('GET', '/users/me', inviteeToken)).status === 401,
            'the role change bumps authorization_version, which retires the old token');

        const promotedToken = jwt(ids.invitee, promoted.role, promoted.authorization_version);
        check('the promotion is real: the new admin can read admin analytics',
            (await request('GET', '/dashboard/stats', promotedToken)).status === 200);

        check('a used invitation cannot be replayed',
            (await request('POST', '/admin/invitations/accept', promotedToken, { token: rawToken })).status === 409);

        // Accepting makes you an admin — it does not make you a super_admin.
        check('guest -> super-admin invitation management is 401',
            (await request('GET', '/admin/invitations', null)).status === 401);
        check('the newly promoted admin still cannot list invitations',
            (await request('GET', '/admin/invitations', promotedToken)).status === 403);
        check('the newly promoted admin still cannot issue invitations',
            (await request('POST', '/admin/invitations', promotedToken, { email: `authgate_x_${run}@medorbit.test` })).status === 403);
        check('the newly promoted admin still cannot revoke invitations',
            (await request('DELETE', `/admin/invitations/${invitationId}`, promotedToken)).status === 403);
        check('patient -> super-admin invitation management is 403',
            (await request('GET', '/admin/invitations', patientToken)).status === 403);
        check('super_admin -> invitation management is still 200',
            (await request('GET', '/admin/invitations', superToken)).status === 200);
    } catch (err) {
        failed += 1;
        console.error('  ✗ suite crashed —', err.message);
    } finally {
        // Invitations and audit rows reference users(id) with no ON DELETE, so
        // they have to go first or the users below silently survive the run.
        const userIds = Object.values(ids);
        await pool.query('DELETE FROM medorbit.feedback WHERE user_id = ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.admin_invitations
             WHERE email LIKE $1
                OR invited_by_user_id = ANY($2::uuid[])
                OR accepted_by_user_id = ANY($2::uuid[])
                OR revoked_by_user_id = ANY($2::uuid[])`,
            [`authgate\\_%\\_${run}@medorbit.test`, userIds]
        ).catch(() => {});
        await pool.query('DELETE FROM medorbit.audit_logs WHERE user_id = ANY($1::uuid[])', [userIds]).catch(() => {});
        for (const id of userIds) {
            await pool.query('DELETE FROM medorbit.users WHERE id=$1', [id]).catch(() => {});
        }
        await pool.end();
        console.log(`\n${passed} passed, ${failed} failed\n`);
        process.exit(failed === 0 ? 0 : 1);
    }
})();

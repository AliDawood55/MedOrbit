// backend/tests/google-auth.test.js
// Google Sign-In service-layer integration test.
// Run: node backend/tests/google-auth.test.js
//
// A real ID token can only come from a live browser + a live Google
// account consenting through Google's own UI — that can't be scripted
// here. So this test monkeypatches OAuth2Client.prototype.verifyIdToken
// to return a fixed payload (bypassing ONLY Google's signature/audience
// verification, which is well-tested third-party code we don't need to
// re-prove). Everything past that point — user lookup, account linking,
// new-user creation, session issuance — is authService.googleLogin()'s
// own code, run for real against the real database.

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const { Pool } = require('pg');
const { OAuth2Client } = require('google-auth-library');

const pool = new Pool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT) || 5432,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: String(process.env.DB_PASSWORD || ''),
    max: 5,
    idleTimeoutMillis: 10000,
    connectionTimeoutMillis: 2000,
});
pool.on('connect', async (client) => {
    await client.query('SET search_path TO medorbit, public');
});

let mockPayload = null;
OAuth2Client.prototype.verifyIdToken = async function () {
    if (!mockPayload) throw new Error('no mock payload set for this call');
    return { getPayload: () => mockPayload };
};

const authService = require('../src/services/auth.service');
const { hashPassword } = require('../src/utils/password');

let passed = 0;
let failed = 0;
function assert(name, condition, detail) {
    if (condition) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.log(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
}

function fakeReq() {
    return { ip: '127.0.0.1', headers: { 'user-agent': 'google-auth-test' }, body: {} };
}

async function getUser(email) {
    const client = await pool.connect();
    try {
        const r = await client.query(
            'SELECT id, email, role, email_verified, google_id, password_hash FROM users WHERE email=$1',
            [email]
        );
        return r.rows[0] || null;
    } finally {
        client.release();
    }
}

async function countSessions(userId) {
    const client = await pool.connect();
    try {
        const r = await client.query(
            'SELECT COUNT(*)::int AS cnt FROM user_sessions WHERE user_id=$1 AND revoked_at IS NULL',
            [userId]
        );
        return r.rows[0].cnt;
    } finally {
        client.release();
    }
}

async function cleanup(email) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query('DELETE FROM user_sessions WHERE user_id=(SELECT id FROM users WHERE email=$1)', [email]);
        await client.query('DELETE FROM patients WHERE user_id=(SELECT id FROM users WHERE email=$1)', [email]);
        await client.query('DELETE FROM user_profiles WHERE user_id=(SELECT id FROM users WHERE email=$1)', [email]);
        await client.query('DELETE FROM users WHERE email=$1', [email]);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function run() {
    const newEmail = `gtest_new_${Date.now()}@medorbit.test`;
    const existingEmail = `gtest_existing_${Date.now()}@medorbit.test`;
    const existingPassword = 'ExistingPass@123';
    const googleSub = `g-sub-${Date.now()}`;

    console.log('\n========================================');
    console.log('  Google Sign-In service tests');
    console.log('========================================\n');

    try {
        // ---- A: brand new Google user ----
        console.log('[A] New Google user');
        mockPayload = {
            sub: googleSub, email: newEmail, email_verified: true,
            given_name: 'Test', family_name: 'Googler', name: 'Test Googler',
            picture: 'https://example.com/pic.png'
        };
        const resA = await authService.googleLogin('fake-token-a', fakeReq());
        assert('Returns access+refresh tokens', !!resA.accessToken && !!resA.refreshToken);
        assert('Returned user email matches', resA.user.email === newEmail);

        const dbUserA = await getUser(newEmail);
        assert('User row created', !!dbUserA);
        assert('email_verified=true (Google already verified)', dbUserA?.email_verified === true);
        assert('google_id stored', dbUserA?.google_id === googleSub, `got ${dbUserA?.google_id}`);
        assert('password_hash is null (no local password)', dbUserA?.password_hash === null);
        assert('role=patient', dbUserA?.role === 'patient');
        assert('Session row created', (await countSessions(dbUserA.id)) === 1);

        // ---- B: returning Google user (same sub, second call) ----
        console.log('\n[B] Returning Google user');
        const resB = await authService.googleLogin('fake-token-a-again', fakeReq());
        assert('Same user id returned (no duplicate account)', resB.user.id === resA.user.id);
        assert('Second session added, still one user', (await countSessions(dbUserA.id)) === 2);

        // ---- C: existing email/password account signs in with same Gmail -> link ----
        console.log('\n[C] Link existing email/password account (not duplicate)');
        const passwordHash = await hashPassword(existingPassword);
        const client = await pool.connect();
        let existingUserId;
        try {
            const ins = await client.query(
                `INSERT INTO users (email, password_hash, role, email_verified) VALUES ($1,$2,'patient',true) RETURNING id`,
                [existingEmail, passwordHash]
            );
            existingUserId = ins.rows[0].id;
            await client.query(
                `INSERT INTO user_profiles (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en) VALUES ($1,'أ','ب','A','B')`,
                [existingUserId]
            );
            await client.query(`INSERT INTO patients (user_id) VALUES ($1)`, [existingUserId]);
        } finally {
            client.release();
        }

        const googleSubForExisting = `g-sub-existing-${Date.now()}`;
        mockPayload = {
            sub: googleSubForExisting, email: existingEmail, email_verified: true,
            given_name: 'Existing', family_name: 'User', name: 'Existing User'
        };
        const resC = await authService.googleLogin('fake-token-c', fakeReq());
        assert('Links to the SAME existing user id', resC.user.id === existingUserId);

        const dbUserC = await getUser(existingEmail);
        assert('google_id linked onto existing account', dbUserC?.google_id === googleSubForExisting);
        assert('Original password_hash untouched', dbUserC?.password_hash === passwordHash);

        const dupCheck = await pool.query('SELECT COUNT(*)::int AS cnt FROM users WHERE email=$1', [existingEmail]);
        assert('Exactly one user row for this email (no duplicate)', dupCheck.rows[0].cnt === 1);

        // ---- D: unverified Google email rejected ----
        console.log('\n[D] Unverified Google email rejected');
        mockPayload = { sub: 'g-sub-unverified', email: 'unverified@medorbit.test', email_verified: false };
        let rejectedD = false;
        try {
            await authService.googleLogin('fake-token-d', fakeReq());
        } catch (err) {
            rejectedD = err.statusCode === 401;
        }
        assert('Unverified Google email rejected with 401', rejectedD);

        // ---- Cleanup ----
        console.log('\n[Cleanup]');
        await cleanup(newEmail);
        await cleanup(existingEmail);
        assert('Test data cleaned up (new user)', !(await getUser(newEmail)));
        assert('Test data cleaned up (existing user)', !(await getUser(existingEmail)));

    } catch (err) {
        console.error('\n⚠️  Test suite error:', err);
        failed++;
        try { await cleanup(newEmail); } catch { /* ignore */ }
        try { await cleanup(existingEmail); } catch { /* ignore */ }
    } finally {
        await pool.end();
    }

    console.log('\n========================================');
    console.log(`  ✓ Passed: ${passed}   ✗ Failed: ${failed}`);
    console.log('========================================\n');
    process.exit(failed > 0 ? 1 : 0);
}

run();

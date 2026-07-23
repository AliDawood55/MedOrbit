// backend/tests/saved-places.test.js
// GET /api/users/me/saved-places — ownership isolation test
// Run: node backend/tests/saved-places.test.js

const http = require('http');
const { Pool } = require('pg');
const path = require('path');

require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const API_BASE = 'http://127.0.0.1:3001/api';

const pool = new Pool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT) || 5432,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: String(process.env.DB_PASSWORD || ''),
    max: 5,
});
pool.on('connect', async (client) => {
    await client.query('SET search_path TO medorbit, public');
});

function apiRequest(method, path, body, headers = {}) {
    return new Promise((resolve, reject) => {
        const url = new URL(API_BASE + path);
        const bodyStr = body ? JSON.stringify(body) : null;
        const options = {
            method,
            hostname: url.hostname,
            port: url.port,
            path: url.pathname + (url.search || ''),
            headers: {
                'Content-Type': 'application/json',
                ...(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {}),
                ...headers,
            },
        };
        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', (c) => (data += c));
            res.on('end', () => {
                try { resolve({ status: res.statusCode, body: JSON.parse(data) }); }
                catch { resolve({ status: res.statusCode, body: { error: { message: data } } }); }
            });
        });
        req.on('error', reject);
        req.setTimeout(10000, () => { req.destroy(); reject(new Error('timeout')); });
        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

let passed = 0, failed = 0;
function assert(name, cond, detail) {
    if (cond) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.log(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
}

async function registerVerifiedUser(email, password) {
    await apiRequest('POST', '/auth/register', {
        email, password, role: 'patient',
        firstNameAr: 'ا', lastNameAr: 'ب', firstNameEn: 'A', lastNameEn: 'B',
    });
    const client = await pool.connect();
    try {
        await client.query('UPDATE users SET email_verified=true WHERE email=$1', [email]);
    } finally {
        client.release();
    }
    const login = await apiRequest('POST', '/auth/login', { email, password });
    return login.body.data.accessToken;
}

async function cleanup(email) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query(`DELETE FROM saved_places WHERE user_id=(SELECT id FROM users WHERE email=$1)`, [email]);
        await client.query(`DELETE FROM chatbot_conversations WHERE user_id=(SELECT id FROM users WHERE email=$1)`, [email]);
        await client.query(`DELETE FROM user_sessions WHERE user_id=(SELECT id FROM users WHERE email=$1)`, [email]);
        await client.query(`DELETE FROM patients WHERE user_id=(SELECT id FROM users WHERE email=$1)`, [email]);
        await client.query(`DELETE FROM user_profiles WHERE user_id=(SELECT id FROM users WHERE email=$1)`, [email]);
        await client.query(`DELETE FROM users WHERE email=$1`, [email]);
        await client.query('COMMIT');
    } catch (e) {
        await client.query('ROLLBACK');
        throw e;
    } finally {
        client.release();
    }
}

async function run() {
    const ts = Date.now();
    const aliceEmail = `alice_${ts}@medorbit.test`;
    const bobEmail = `bob_${ts}@medorbit.test`;
    const emptyEmail = `empty_${ts}@medorbit.test`;
    const password = 'TestPass@123';

    console.log('\n========================================');
    console.log('  GET /api/users/me/saved-places tests');
    console.log('========================================\n');

    try {
        console.log('[Setup] Creating two users with saved places + one with none');
        const aliceToken = await registerVerifiedUser(aliceEmail, password);
        const bobToken = await registerVerifiedUser(bobEmail, password);
        const emptyToken = await registerVerifiedUser(emptyEmail, password);

        const aliceConv = await apiRequest('POST', '/conversations', { language: 'en' }, { Authorization: `Bearer ${aliceToken}` });
        const bobConv = await apiRequest('POST', '/conversations', { language: 'en' }, { Authorization: `Bearer ${bobToken}` });

        await apiRequest('POST', `/conversations/${aliceConv.body.data.id}/places`, {
            placeName: "Alice's Clinic", placeType: 'clinic', latitude: 32.22, longitude: 35.26
        }, { Authorization: `Bearer ${aliceToken}` });

        await apiRequest('POST', `/conversations/${bobConv.body.data.id}/places`, {
            placeName: "Bob's Pharmacy", placeType: 'pharmacy', latitude: 32.23, longitude: 35.27
        }, { Authorization: `Bearer ${bobToken}` });

        console.log('\n[1] Ownership isolation');
        const aliceRes = await apiRequest('GET', '/users/me/saved-places', null, { Authorization: `Bearer ${aliceToken}` });
        assert('Alice gets 200', aliceRes.status === 200, `got ${aliceRes.status}`);
        assert('Alice sees exactly 1 place', aliceRes.body?.data?.places?.length === 1, `got ${aliceRes.body?.data?.places?.length}`);
        assert('Alice only sees her own place', aliceRes.body?.data?.places?.[0]?.place_name === "Alice's Clinic",
            `got ${aliceRes.body?.data?.places?.[0]?.place_name}`);

        const bobRes = await apiRequest('GET', '/users/me/saved-places', null, { Authorization: `Bearer ${bobToken}` });
        assert('Bob sees exactly 1 place', bobRes.body?.data?.places?.length === 1, `got ${bobRes.body?.data?.places?.length}`);
        assert('Bob only sees his own place', bobRes.body?.data?.places?.[0]?.place_name === "Bob's Pharmacy",
            `got ${bobRes.body?.data?.places?.[0]?.place_name}`);

        console.log('\n[2] No token -> 401');
        const noAuthRes = await apiRequest('GET', '/users/me/saved-places');
        assert('Returns 401 without a token', noAuthRes.status === 401, `got ${noAuthRes.status}`);

        console.log('\n[3] Empty state');
        const emptyRes = await apiRequest('GET', '/users/me/saved-places', null, { Authorization: `Bearer ${emptyToken}` });
        assert('User with no places gets 200', emptyRes.status === 200, `got ${emptyRes.status}`);
        assert('Returns empty array, not an error', Array.isArray(emptyRes.body?.data?.places) && emptyRes.body.data.places.length === 0,
            `got ${JSON.stringify(emptyRes.body?.data)}`);

        console.log('\n[Cleanup]');
        await cleanup(aliceEmail);
        await cleanup(bobEmail);
        await cleanup(emptyEmail);
        console.log('  Cleanup complete');

    } catch (err) {
        console.error('\n⚠️  Test suite error:', err);
        failed++;
        try { await cleanup(aliceEmail); } catch { /* ignore */ }
        try { await cleanup(bobEmail); } catch { /* ignore */ }
        try { await cleanup(emptyEmail); } catch { /* ignore */ }
    } finally {
        await pool.end();
    }

    console.log('\n========================================');
    console.log(`  ✓ Passed: ${passed}   ✗ Failed: ${failed}`);
    console.log('========================================\n');
    process.exit(failed > 0 ? 1 : 0);
}

run();

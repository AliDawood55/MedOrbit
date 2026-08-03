// backend/tests/auth.test.js
// Standalone authentication integration test
// Docker: docker compose exec -T backend node tests/auth.test.js

const http = require('http');
const { Pool } = require('pg');
const path = require('path');

// Load root .env
require('dotenv').config({ path: path.resolve(__dirname, '../../.env'), quiet: true });

const API_BASE = process.env.AUTH_TEST_API_BASE || 'http://127.0.0.1:3001/api';

// Database pool for cleanup — must use same schema as backend
const pool = new Pool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT) || 5432,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: String(process.env.DB_PASSWORD || ''),
    max: 5,
    idleTimeoutMillis: 10000,
    connectionTimeoutMillis: 2000,
    options: '-c search_path=medorbit,public',
});

// =============================================
// HTTP helper — no external dependencies
// =============================================
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
            res.on('data', (chunk) => (data += chunk));
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, body: JSON.parse(data) });
                } catch {
                    resolve({ status: res.statusCode, body: { error: { message: data } } });
                }
            });
        });

        req.on('error', reject);
        req.setTimeout(10000, () => { req.destroy(); reject(new Error('Request timeout')); });

        if (bodyStr) req.write(bodyStr);
        req.end();
    });
}

// =============================================
// Database cleanup helper
// =============================================
async function cleanupUser(email) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query("DELETE FROM medorbit.email_queue WHERE recipient_email = $1", [email]);
        await client.query("DELETE FROM medorbit.password_reset_tokens WHERE user_id = (SELECT id FROM medorbit.users WHERE email = $1)", [email]);
        await client.query("DELETE FROM medorbit.email_verification_tokens WHERE user_id = (SELECT id FROM medorbit.users WHERE email = $1)", [email]);
        await client.query("DELETE FROM medorbit.user_sessions WHERE user_id = (SELECT id FROM medorbit.users WHERE email = $1)", [email]);
        await client.query("DELETE FROM medorbit.patients WHERE user_id = (SELECT id FROM medorbit.users WHERE email = $1)", [email]);
        await client.query("DELETE FROM medorbit.user_profiles WHERE user_id = (SELECT id FROM medorbit.users WHERE email = $1)", [email]);
        await client.query("DELETE FROM medorbit.users WHERE email = $1", [email]);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function verifyUserInDb(email) {
    const client = await pool.connect();
    try {
        const result = await client.query(
            "SELECT id, email, email_verified, role FROM medorbit.users WHERE email = $1",
            [email]
        );
        return result.rows[0] || null;
    } finally {
        client.release();
    }
}

async function countActiveTokens(email, table) {
    const consumedColumns = {
        email_verification_tokens: 'verified_at',
        password_reset_tokens: 'used_at',
    };
    const consumedColumn = consumedColumns[table];
    if (!consumedColumn) throw new Error(`Unsupported token table: ${table}`);
    const client = await pool.connect();
    try {
        const result = await client.query(
            `SELECT COUNT(*) as cnt FROM medorbit.${table} t
             JOIN medorbit.users u ON u.id = t.user_id
             WHERE u.email = $1 AND t.${consumedColumn} IS NULL AND t.expires_at > NOW()`,
            [email]
        );
        return parseInt(result.rows[0].cnt, 10);
    } finally {
        client.release();
    }
}

// =============================================
// Test runner
// =============================================
let passed = 0;
let failed = 0;

function assert(name, condition, detail) {
    if (condition) {
        passed++;
        console.log(`  ✓ ${name}`);
    } else {
        failed++;
        console.log(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

// =============================================
// Main test suite
// =============================================
async function runTests() {
    const testEmail = `testuser_${Date.now()}@medorbit.test`;
    const testPass = 'TestPass@123';
    let accessToken = null;
    let refreshToken = null;

    console.log('\n========================================');
    console.log('  MedOrbit Auth Integration Tests');
    console.log('========================================\n');

    try {
        // =============================================
        // 1. REGISTER
        // =============================================
        console.log('[1] REGISTER');

        let r = await apiRequest('POST', '/auth/register', {
            email: testEmail,
            password: testPass,
            role: 'patient',
            firstNameAr: 'اختبار',
            lastNameAr: 'مستخدم',
            firstNameEn: 'Test',
            lastNameEn: 'User',
            phone: '+970-59-1234567',
            gender: 'male',
        });
        assert('Register new user returns 201', r.status === 201, `Got ${r.status}`);
        const userId = r.body?.data?.id;
        console.log(`    User ID: ${userId}`);

        // Verify user in database
        const dbUser = await verifyUserInDb(testEmail);
        assert('User saved in database', !!dbUser, 'User not found in DB');
        assert('email_verified is false', dbUser && dbUser.email_verified === false, `Got ${dbUser?.email_verified}`);

        // Verify verification token stored
        const tokenCount = await countActiveTokens(testEmail, 'email_verification_tokens');
        assert('Verification token stored in DB', tokenCount >= 1, `Found ${tokenCount} tokens`);

        // Duplicate email
        r = await apiRequest('POST', '/auth/register', {
            email: testEmail, password: testPass, role: 'patient',
            firstNameAr: 'x', lastNameAr: 'x', firstNameEn: 'x', lastNameEn: 'x',
        });
        assert('Duplicate email rejected', r.status === 400, `Got ${r.status}`);

        // Weak password
        r = await apiRequest('POST', '/auth/register', {
            email: `weak_${Date.now()}@test.com`, password: 'weak', role: 'patient',
            firstNameAr: 'x', lastNameAr: 'x', firstNameEn: 'x', lastNameEn: 'x',
        });
        assert('Weak password rejected', r.status === 400, `Got ${r.status}`);

        // =============================================
        // 2. EMAIL VERIFICATION
        // =============================================
        console.log('\n[2] EMAIL VERIFICATION');

        r = await apiRequest('POST', '/auth/login', { email: testEmail, password: testPass });
        assert('Login blocked for unverified account',
            r.status === 400 && r.body?.error?.message === 'Please verify your email before logging in',
            `Got: ${r.body?.error?.message}`);

        // Manually verify via DB
        const vClient = await pool.connect();
        try {
            await vClient.query("UPDATE medorbit.users SET email_verified = true WHERE email = $1", [testEmail]);
            await vClient.query(
                "UPDATE medorbit.email_verification_tokens SET verified_at = NOW() WHERE user_id = (SELECT id FROM medorbit.users WHERE email = $1) AND verified_at IS NULL",
                [testEmail]
            );
        } finally {
            vClient.release();
        }

        const dbUserAfter = await verifyUserInDb(testEmail);
        assert('email_verified updated to true', dbUserAfter && dbUserAfter.email_verified === true, `Got ${dbUserAfter?.email_verified}`);

        // =============================================
        // 3. LOGIN
        // =============================================
        console.log('\n[3] LOGIN');

        r = await apiRequest('POST', '/auth/login', { email: testEmail, password: 'WrongPass1@' });
        assert('Wrong password returns generic error',
            r.status === 400 && r.body?.error?.message === 'Invalid credentials',
            `Got: ${r.body?.error?.message}`);

        r = await apiRequest('POST', '/auth/login', { email: testEmail, password: testPass });
        assert('Login succeeds with correct password', r.status === 200, `Got ${r.status}`);
        assert('Access token returned', !!r.body?.data?.accessToken, 'Missing access token');
        assert('Refresh token returned', !!r.body?.data?.refreshToken, 'Missing refresh token');
        assert('User data returned', !!r.body?.data?.user, 'Missing user data');
        accessToken = r.body.data.accessToken;
        refreshToken = r.body.data.refreshToken;

        // =============================================
        // 4. JWT
        // =============================================
        console.log('\n[4] JWT');

        r = await apiRequest('GET', '/users/me', null, { Authorization: `Bearer ${accessToken}` });
        assert('Access token works on protected route', r.status !== 401, `Got status ${r.status}`);

        r = await apiRequest('POST', '/auth/refresh', { refreshToken });
        assert('Refresh token rotation returns new tokens',
            r.status === 200 && !!r.body?.data?.refreshToken,
            `Got status ${r.status}`);
        const oldRefreshToken = refreshToken;
        accessToken = r.body.data.accessToken;
        refreshToken = r.body.data.refreshToken;

        r = await apiRequest('POST', '/auth/refresh', { refreshToken: oldRefreshToken });
        assert('Old refresh token rejected after rotation', r.status === 400, `Got ${r.status}`);

        // =============================================
        // 5. LOGOUT
        // =============================================
        console.log('\n[5] LOGOUT');

        r = await apiRequest('POST', '/auth/logout', { refreshToken });
        assert('Logout succeeds', r.status === 200, `Got ${r.status}`);

        r = await apiRequest('POST', '/auth/refresh', { refreshToken });
        assert('Refresh after logout fails', r.status === 400, `Got ${r.status}`);

        // =============================================
        // 6. FORGOT PASSWORD
        // =============================================
        console.log('\n[6] FORGOT PASSWORD');

        r = await apiRequest('POST', '/auth/forgot-password', { email: testEmail });
        assert('Forgot password request succeeds', r.status === 200, `Got ${r.status}`);

        r = await apiRequest('POST', '/auth/forgot-password', { email: `nonexistent_${Date.now()}@test.com` });
        assert('No email enumeration (returns success for missing email)', r.status === 200, `Got ${r.status}`);

        const resetTokenCount = await countActiveTokens(testEmail, 'password_reset_tokens');
        assert('Password reset token stored in DB', resetTokenCount >= 1, `Found ${resetTokenCount} tokens`);

        // =============================================
        // 7. RESET PASSWORD
        // =============================================
        console.log('\n[7] RESET PASSWORD');

        r = await apiRequest('POST', '/auth/reset-password', { token: 'invalidtoken123', newPassword: 'NewPass@123' });
        assert('Invalid reset token rejected',
            r.status === 400 && r.body?.error?.message === 'Invalid or expired token',
            `Got: ${r.body?.error?.message}`);

        r = await apiRequest('POST', '/auth/reset-password', { token: 'sometoken', newPassword: 'weak' });
        assert('Weak password rejected on reset', r.status === 400, `Got ${r.status}`);

        // =============================================
        // 8. LOGIN AGAIN (verify still works)
        // =============================================
        console.log('\n[8] LOGIN AGAIN');

        r = await apiRequest('POST', '/auth/login', { email: testEmail, password: testPass });
        assert('Login still works after tests', r.status === 200 && !!r.body?.data?.accessToken, `Got ${r.status}`);
        accessToken = r.body.data.accessToken;
        refreshToken = r.body.data.refreshToken;

        // =============================================
        // 9. CHANGE PASSWORD
        // =============================================
        console.log('\n[9] CHANGE PASSWORD');

        r = await apiRequest('POST', '/auth/change-password', {
            currentPassword: testPass,
            newPassword: 'NewPass@456',
        });
        assert('Change password requires authentication', r.status === 401, `Got ${r.status}`);

        r = await apiRequest('POST', '/auth/change-password', {
            currentPassword: testPass,
            newPassword: 'NewPass@456',
        }, { Authorization: `Bearer ${accessToken}` });
        assert('Change password succeeds', r.status === 200, `Got ${r.status}`);

        r = await apiRequest('POST', '/auth/login', { email: testEmail, password: testPass });
        assert('Old password rejected after change', r.status === 400, `Got ${r.status}`);

        r = await apiRequest('POST', '/auth/login', { email: testEmail, password: 'NewPass@456' });
        assert('New password works', r.status === 200 && !!r.body?.data?.accessToken, `Got ${r.status}`);

        r = await apiRequest('POST', '/auth/refresh', { refreshToken });
        assert('Old refresh token revoked after password change', r.status === 400, `Got ${r.status}`);

        // =============================================
        // 10. CLEANUP
        // =============================================
        console.log('\n[10] CLEANUP');
        await cleanupUser(testEmail);
        const deletedUser = await verifyUserInDb(testEmail);
        assert('Test user deleted from database', !deletedUser, 'User still exists');
        console.log('    Cleanup complete');

    } catch (err) {
        console.error('\n⚠️  Test suite error:', err.message);
        failed++;
        // Attempt cleanup even on failure
        try { await cleanupUser(testEmail); } catch { /* ignore */ }
    } finally {
        await pool.end();
    }

    // =============================================
    // RESULTS
    // =============================================
    console.log('\n========================================');
    console.log('  RESULTS');
    console.log('========================================');
    console.log(`  ✓ Passed: ${passed}`);
    console.log(`  ✗ Failed: ${failed}`);
    console.log('========================================\n');

    process.exit(failed > 0 ? 1 : 0);
}

runTests();

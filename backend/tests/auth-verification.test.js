// Focused integration tests for registration and dual-mode email verification.
// Docker: docker compose exec -T backend npm run test:auth-verification
// Run beside the backend so HTTP and direct DB assertions use the same database.

const crypto = require('crypto');
const http = require('http');
const { Pool } = require('pg');
const { apiBase: API_BASE, poolConfig } = require('./helpers/test-environment');

const password = 'TestPass@123';

const pool = new Pool({
    ...poolConfig,
});

function request(pathname, body) {
    return new Promise((resolve, reject) => {
        const url = new URL(API_BASE + pathname);
        const payload = JSON.stringify(body);
        const req = http.request({
            method: 'POST',
            hostname: url.hostname,
            port: url.port,
            path: url.pathname,
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(payload)
            }
        }, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, body: JSON.parse(data) });
                } catch {
                    resolve({ status: res.statusCode, body: null });
                }
            });
        });

        req.setTimeout(10000, () => req.destroy(new Error('Request timeout')));
        req.on('error', reject);
        req.end(payload);
    });
}

function registrationBody(email) {
    return {
        email,
        password,
        role: 'patient',
        firstNameAr: 'Test',
        lastNameAr: 'User',
        firstNameEn: 'Test',
        lastNameEn: 'User',
        gender: 'male'
    };
}

async function getVerificationDelivery(email) {
    const result = await pool.query(
        `SELECT body_text
         FROM medorbit.email_queue
         WHERE recipient_email=$1 AND subject='Verify your MedOrbit account'
         ORDER BY created_at DESC
         LIMIT 1`,
        [email]
    );
    const text = result.rows[0]?.body_text || '';
    return {
        otp: text.match(/verification code is:\s*(\d{6})/i)?.[1],
        linkToken: text.match(/[?&](?:token|verify)=([a-f0-9]{64})/i)?.[1]
    };
}

async function setTokenExpired(token, email) {
    if (!token) throw new Error('OTP missing from queued verification email');
    const tokenHash = crypto
        .createHmac('sha256', process.env.JWT_SECRET)
        .update(`email-verification-otp:${email}:${token}`)
        .digest('hex');
    await pool.query(
        `UPDATE medorbit.email_verification_tokens SET expires_at=NOW()-INTERVAL '1 minute' WHERE token_hash=$1`,
        [tokenHash]
    );
}

async function isVerified(email) {
    const result = await pool.query('SELECT email_verified FROM medorbit.users WHERE email=$1', [email]);
    return result.rows[0]?.email_verified === true;
}

async function verificationEmailCount(email) {
    const result = await pool.query(
        `SELECT COUNT(*)::int AS count FROM medorbit.email_queue
         WHERE recipient_email=$1 AND subject='Verify your MedOrbit account'`,
        [email]
    );
    return result.rows[0].count;
}

async function cleanup(email) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query('DELETE FROM medorbit.email_queue WHERE recipient_email=$1', [email]);
        await client.query('DELETE FROM medorbit.email_verification_tokens WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [email]);
        await client.query('DELETE FROM medorbit.user_sessions WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [email]);
        await client.query('DELETE FROM medorbit.patients WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [email]);
        await client.query('DELETE FROM medorbit.user_profiles WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [email]);
        await client.query('DELETE FROM medorbit.users WHERE email=$1', [email]);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  PASS ${name}`);
        return;
    }
    failed += 1;
    console.error(`  FAIL ${name}${detail ? `: ${detail}` : ''}`);
}

async function run() {
    const suffix = `${Date.now()}_${crypto.randomInt(1000, 9999)}`;
    const baseEmail = `auth_base_${suffix}@medorbit.test`;
    const otpEmail = `auth_otp_${suffix}@medorbit.test`;
    const expiredEmail = `auth_expired_${suffix}@medorbit.test`;
    const linkEmail = `auth_link_${suffix}@medorbit.test`;
    const unknownEmail = `auth_unknown_${suffix}@medorbit.test`;
    const emails = [baseEmail, otpEmail, expiredEmail, linkEmail, unknownEmail];

    try {
        let response = await request('/auth/register', registrationBody(baseEmail));
        check('valid registration', response.status === 201 && response.body?.data?.email === baseEmail, `status ${response.status}`);

        response = await request('/auth/register', registrationBody('not-an-email'));
        check('invalid email', response.status === 400 && response.body?.error?.code === 'VALIDATION_ERROR', `status ${response.status}`);

        response = await request('/auth/register', registrationBody(baseEmail));
        check('duplicate email', response.status === 400 && response.body?.error?.code === 'VALIDATION_ERROR', `status ${response.status}`);

        response = await request('/auth/register', registrationBody(otpEmail));
        const otpDelivery = await getVerificationDelivery(otpEmail);
        check('OTP registration delivery', response.status === 201 && /^\d{6}$/.test(otpDelivery.otp || ''), `status ${response.status}`);

        response = await request('/auth/login', { email: otpEmail, password: 'WrongPass@123' });
        check(
            'wrong password remains generic for unverified account',
            response.status === 400 && response.body?.error?.code === 'INVALID_CREDENTIALS',
            `status ${response.status}`
        );

        response = await request('/auth/login', { email: unknownEmail, password: 'WrongPass@123' });
        check(
            'unknown email remains generic',
            response.status === 400 && response.body?.error?.code === 'INVALID_CREDENTIALS',
            `status ${response.status}`
        );

        response = await request('/auth/verify-email', { token: otpDelivery.otp, email: otpEmail });
        check('correct OTP', response.status === 200 && await isVerified(otpEmail), `status ${response.status}`);

        response = await request('/auth/verify-email', { token: otpDelivery.otp, email: otpEmail });
        check('reused OTP', response.status === 409 && response.body?.error?.code === 'VERIFICATION_TOKEN_USED', `status ${response.status}`);

        response = await request('/auth/verify-email', { token: '000000', email: otpEmail });
        check('wrong OTP', response.status === 400 && response.body?.error?.code === 'INVALID_VERIFICATION_TOKEN', `status ${response.status}`);

        await request('/auth/register', registrationBody(expiredEmail));
        const expiredDelivery = await getVerificationDelivery(expiredEmail);
        await setTokenExpired(expiredDelivery.otp, expiredEmail);
        response = await request('/auth/verify-email', { token: expiredDelivery.otp, email: expiredEmail });
        check('expired OTP', response.status === 410 && response.body?.error?.code === 'VERIFICATION_TOKEN_EXPIRED', `status ${response.status}`);

        response = await request('/auth/resend-verification', { email: unknownEmail });
        check('resend unknown email is generic', response.status === 200 && response.body?.data === null, `status ${response.status}`);

        const queueCountBefore = await verificationEmailCount(otpEmail);
        response = await request('/auth/resend-verification', { email: otpEmail });
        const queueCountAfter = await verificationEmailCount(otpEmail);
        check(
            'resend already verified email is generic',
            response.status === 200 && response.body?.data === null && queueCountAfter === queueCountBefore,
            `status ${response.status}`
        );

        await request('/auth/register', registrationBody(linkEmail));
        const linkDelivery = await getVerificationDelivery(linkEmail);
        response = await request('/auth/verify-email', { token: linkDelivery.linkToken });
        check('existing link-token compatibility', response.status === 200 && await isVerified(linkEmail), `status ${response.status}`);

        let rateLimited = false;
        for (let attempt = 0; attempt < 11 && !rateLimited; attempt += 1) {
            response = await request('/auth/verify-email', { token: `invalid-${suffix}-${attempt}` });
            rateLimited = response.status === 429 && response.body?.error?.code === 'RATE_LIMITED';
        }
        check('verification rate limiting', rateLimited);
    } finally {
        for (const email of emails) {
            await cleanup(email);
        }
        await pool.end();
    }

    console.log(`\nPassed: ${passed}; Failed: ${failed}`);
    process.exitCode = failed === 0 ? 0 : 1;
}

run().catch((err) => {
    console.error(`Auth verification test failed: ${err.message}`);
    process.exitCode = 1;
});

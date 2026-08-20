const crypto = require('crypto');
const http = require('http');
const jwt = require('jsonwebtoken');
const { Pool } = require('pg');
const { OAuth2Client } = require('google-auth-library');
const { apiBase: API_BASE, poolConfig } = require('./helpers/test-environment');
const { hashPassword } = require('../src/utils/password');

let googlePayload = null;
OAuth2Client.prototype.verifyIdToken = async function verifyIdToken() {
    return { getPayload: () => googlePayload };
};
const authService = require('../src/services/auth.service');

const pool = new Pool(poolConfig);
const password = 'S1aTestPass@123';
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  PASS ${name}`);
    } else {
        failed += 1;
        console.error(`  FAIL ${name}${detail ? `: ${detail}` : ''}`);
    }
}

function request(method, pathname, body = null, accessToken = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(API_BASE + pathname);
        const payload = body == null ? null : JSON.stringify(body);
        const req = http.request({
            method,
            hostname: url.hostname,
            port: url.port,
            path: url.pathname + url.search,
            headers: {
                'Content-Type': 'application/json',
                ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {}),
                ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
            },
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
        req.on('error', reject);
        req.setTimeout(10000, () => req.destroy(new Error('Request timeout')));
        if (payload) req.write(payload);
        req.end();
    });
}

function registrationBody(email, roleMarker) {
    const body = {
        email,
        password,
        firstNameAr: 'Test',
        lastNameAr: 'User',
        firstNameEn: 'Test',
        lastNameEn: 'User',
        gender: 'male',
    };
    if (roleMarker !== undefined) body.role = roleMarker;
    return body;
}

async function createUser(email, role = 'patient', options = {}) {
    const passwordHash = await hashPassword(options.password || password);
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const result = await client.query(
            `INSERT INTO medorbit.users
             (email, password_hash, role, email_verified, is_active, deleted_at, google_id)
             VALUES ($1,$2,$3,true,$4,$5,$6)
             RETURNING id, authorization_version`,
            [email, passwordHash, role, options.isActive ?? true, options.deletedAt || null, options.googleId || null]
        );
        const user = result.rows[0];
        await client.query(
            `INSERT INTO medorbit.user_profiles
             (user_id, first_name_ar, last_name_ar, first_name_en, last_name_en)
             VALUES ($1,'Test','User','Test','User')`,
            [user.id]
        );
        if (role === 'patient') await client.query('INSERT INTO medorbit.patients (user_id) VALUES ($1)', [user.id]);
        if (role === 'doctor') await client.query('INSERT INTO medorbit.doctors (user_id) VALUES ($1)', [user.id]);
        await client.query('COMMIT');
        return user;
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function login(email, loginPassword = password) {
    return request('POST', '/auth/login', { email, password: loginPassword, platform: 'test' });
}

async function cleanup(emails) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query(
            `DELETE FROM medorbit.audit_logs
             WHERE user_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))
                OR entity_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))`,
            [emails]
        );
        await client.query('DELETE FROM medorbit.email_queue WHERE recipient_email=ANY($1)', [emails]);
        await client.query('DELETE FROM medorbit.password_reset_tokens WHERE user_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))', [emails]);
        await client.query('DELETE FROM medorbit.email_verification_tokens WHERE user_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))', [emails]);
        await client.query('DELETE FROM medorbit.user_sessions WHERE user_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))', [emails]);
        await client.query('DELETE FROM medorbit.doctors WHERE user_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))', [emails]);
        await client.query('DELETE FROM medorbit.patients WHERE user_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))', [emails]);
        await client.query('DELETE FROM medorbit.user_profiles WHERE user_id IN (SELECT id FROM medorbit.users WHERE email=ANY($1))', [emails]);
        await client.query('DELETE FROM medorbit.users WHERE email=ANY($1)', [emails]);
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function runTests() {
    const suffix = `${Date.now()}_${crypto.randomInt(1000, 9999)}`;
    const email = (label) => `s1a_${label}_${suffix}@medorbit.test`;
    const emails = [
        'reg_patient', 'reg_omitted', 'reg_doctor', 'reg_admin', 'reg_super',
        'patient', 'doctor', 'inactive', 'deleted', 'role', 'admin', 'super',
        'deactivate', 'reset', 'google_mismatch', 'google_new',
    ].map(email);

    try {
        let response = await request('POST', '/auth/register', registrationBody(email('reg_patient'), 'patient'));
        check('public patient registration succeeds', response.status === 201 && response.body?.data?.role === 'patient');

        response = await request('POST', '/auth/register', registrationBody(email('reg_omitted')));
        check('omitted public role creates patient', response.status === 201 && response.body?.data?.role === 'patient');

        for (const role of ['doctor', 'admin', 'super_admin']) {
            response = await request('POST', '/auth/register', registrationBody(email(`reg_${role === 'super_admin' ? 'super' : role}`), role));
            check(`public ${role} registration fails closed`, response.status === 400 && response.body?.error?.code === 'INVALID_ROLE');
        }

        await createUser(email('patient'));
        response = await login(email('patient'));
        check('normal patient login succeeds', response.status === 200);
        const patientTokens = response.body.data;
        const accessClaims = jwt.decode(patientTokens.accessToken);
        const refreshClaims = jwt.decode(patientTokens.refreshToken);
        check('access token has explicit claims', accessClaims.type === 'access' && Number.isInteger(accessClaims.authorizationVersion) && accessClaims.iss === 'medorbit-api');
        check('refresh token has explicit claims', refreshClaims.type === 'refresh' && Number.isInteger(refreshClaims.authorizationVersion) && refreshClaims.jti);

        response = await request('GET', '/users/me', null, patientTokens.refreshToken);
        check('refresh token rejected by authenticate', response.status === 401);
        response = await request('POST', '/auth/refresh', { refreshToken: patientTokens.accessToken });
        check('access token rejected by refresh', response.status === 400 && response.body?.error?.code === 'INVALID_TOKEN');

        const storedSession = await pool.query(
            `SELECT refresh_token_hash FROM medorbit.user_sessions
             WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)
             ORDER BY created_at DESC LIMIT 1`,
            [email('patient')]
        );
        const expectedHash = crypto.createHash('sha256').update(patientTokens.refreshToken).digest('hex');
        check('refresh token stored only as deterministic hash', storedSession.rows[0]?.refresh_token_hash === expectedHash);

        await createUser(email('inactive'));
        let inactiveLogin = await login(email('inactive'));
        await pool.query(`UPDATE medorbit.users SET is_active=false WHERE email=$1`, [email('inactive')]);
        response = await request('GET', '/users/me', null, inactiveLogin.body.data.accessToken);
        check('inactive user cannot authenticate', response.status === 401);
        response = await request('POST', '/auth/refresh', { refreshToken: inactiveLogin.body.data.refreshToken });
        check('inactive user cannot refresh', response.status === 400);

        await createUser(email('deleted'));
        const deletedLogin = await login(email('deleted'));
        await pool.query(`UPDATE medorbit.users SET deleted_at=NOW(), is_active=false WHERE email=$1`, [email('deleted')]);
        response = await request('GET', '/users/me', null, deletedLogin.body.data.accessToken);
        check('deleted user cannot authenticate', response.status === 401);
        response = await request('POST', '/auth/refresh', { refreshToken: deletedLogin.body.data.refreshToken });
        check('deleted user cannot refresh', response.status === 400);

        const roleUser = await createUser(email('role'));
        const roleLogin = await login(email('role'));
        const initialVersion = roleUser.authorization_version;
        await pool.query(`UPDATE medorbit.users SET role='doctor' WHERE email=$1`, [email('role')]);
        const roleState = await pool.query(
            `SELECT authorization_version,
                    (SELECT COUNT(*)::int FROM medorbit.user_sessions WHERE user_id=u.id AND revoked_at IS NULL) AS active_sessions
             FROM medorbit.users u WHERE email=$1`,
            [email('role')]
        );
        response = await request('GET', '/users/me', null, roleLogin.body.data.accessToken);
        check('role change invalidates existing access token', response.status === 401 && roleState.rows[0].authorization_version === initialVersion + 1);
        response = await request('POST', '/auth/refresh', { refreshToken: roleLogin.body.data.refreshToken });
        check('role change revokes refresh sessions', response.status === 400 && roleState.rows[0].active_sessions === 0);

        await createUser(email('doctor'), 'doctor');
        response = await login(email('doctor'));
        check('legitimate existing doctor login succeeds', response.status === 200 && response.body?.data?.user?.role === 'doctor');

        await createUser(email('admin'), 'admin');
        const adminLogin = await login(email('admin'));
        await createUser(email('deactivate'));
        const deactivateLogin = await login(email('deactivate'));
        response = await request('PUT', `/admin/users/${(await pool.query('SELECT id FROM medorbit.users WHERE email=$1', [email('deactivate')])).rows[0].id}/deactivate`, {}, adminLogin.body.data.accessToken);
        check('deactivate response excludes password hash', response.status === 200 && !JSON.stringify(response.body).includes('password_hash'));
        const deactivatedAccess = await request('GET', '/users/me', null, deactivateLogin.body.data.accessToken);
        check('deactivate invalidates access immediately', deactivatedAccess.status === 401);

        const audit = await pool.query(
            `SELECT old_values, new_values FROM medorbit.audit_logs
             WHERE entity_id=(SELECT id FROM medorbit.users WHERE email=$1)
               AND action='USER_DEACTIVATED'
             ORDER BY created_at DESC LIMIT 1`,
            [email('deactivate')]
        );
        check('new audit snapshots exclude password hash', audit.rows.length === 1 && !JSON.stringify(audit.rows[0]).includes('password_hash'));

        const adminUsers = await request('GET', '/admin/users', null, adminLogin.body.data.accessToken);
        check('admin user responses exclude credential fields', adminUsers.status === 200 && !/password_hash|refresh_token|token_hash/.test(JSON.stringify(adminUsers.body)));

        const roleTargetId = (await pool.query('SELECT id FROM medorbit.users WHERE email=$1', [email('patient')])).rows[0].id;
        response = await request('PUT', `/admin/users/${roleTargetId}/role`, { role: 'admin' }, adminLogin.body.data.accessToken);
        check('ordinary admin cannot promote admin', response.status === 403);
        response = await request('PUT', `/admin/users/${roleTargetId}/role`, { role: 'super_admin' }, adminLogin.body.data.accessToken);
        check('ordinary admin cannot promote super_admin', response.status === 403);

        const superUser = await createUser(email('super'), 'super_admin');
        response = await request('PUT', `/admin/users/${superUser.id}/deactivate`, {}, adminLogin.body.data.accessToken);
        check('ordinary admin cannot modify super_admin', response.status === 403);

        await createUser(email('reset'));
        const resetLogin = await login(email('reset'));
        await request('POST', '/auth/forgot-password', { email: email('reset') });
        const resetEmail = await pool.query(
            `SELECT body_text FROM medorbit.email_queue
             WHERE recipient_email=$1 AND subject='Reset your MedOrbit password'
             ORDER BY created_at DESC LIMIT 1`,
            [email('reset')]
        );
        const rawResetToken = resetEmail.rows[0]?.body_text?.match(/[?&]reset=([a-f0-9]{64})/i)?.[1];
        response = await request('POST', '/auth/reset-password', { token: rawResetToken, newPassword: 'ResetPass@456' });
        const resetAccess = await request('GET', '/users/me', null, resetLogin.body.data.accessToken);
        const resetRefresh = await request('POST', '/auth/refresh', { refreshToken: resetLogin.body.data.refreshToken });
        check('password reset succeeds and invalidates access', response.status === 200 && resetAccess.status === 401);
        check('password reset revokes all refresh sessions', resetRefresh.status === 400);

        await createUser(email('google_mismatch'), 'patient', { googleId: `original-${suffix}` });
        googlePayload = {
            sub: `different-${suffix}`,
            email: email('google_mismatch').toUpperCase(),
            email_verified: true,
            given_name: 'Mismatch',
            family_name: 'User',
        };
        let mismatchRejected = false;
        try {
            await authService.googleLogin('mock-token', { ip: '127.0.0.1', headers: {}, body: {} });
        } catch (err) {
            mismatchRejected = err.code === 'GOOGLE_IDENTITY_MISMATCH';
        }
        check('Google provider-subject mismatch is rejected', mismatchRejected);

        googlePayload = {
            sub: `new-${suffix}`,
            email: email('google_new').toUpperCase(),
            email_verified: true,
            given_name: 'Google',
            family_name: 'Patient',
        };
        const googleNew = await authService.googleLogin('mock-token', { ip: '127.0.0.1', headers: {}, body: {} });
        const googleRow = await pool.query('SELECT role FROM medorbit.users WHERE email=$1', [email('google_new')]);
        check('new Google user remains patient', googleNew.user.role === 'patient' && googleRow.rows[0]?.role === 'patient');
    } finally {
        await cleanup(emails);
        await pool.end();
    }

    console.log(`\nS1A auth hardening: ${passed} passed; ${failed} failed`);
    process.exitCode = failed === 0 ? 0 : 1;
}

runTests().catch(async (err) => {
    console.error(err);
    try { await pool.end(); } catch {}
    process.exitCode = 1;
});

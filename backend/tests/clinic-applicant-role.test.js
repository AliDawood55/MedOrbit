// Clinic applicant lifecycle boundary test.
// Runs only against the disposable Docker test database.
const crypto = require('crypto');
const http = require('http');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');

const pool = new Pool(poolConfig);
const email = `clinic-w1-${crypto.randomUUID()}@example.test`;
let failures = 0;

function check(label, condition) {
  if (condition) console.log(`  PASS ${label}`);
  else { console.error(`  FAIL ${label}`); failures += 1; }
}

function request(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const url = new URL(apiBase + path);
    const payload = body ? JSON.stringify(body) : null;
    const req = http.request({
      method, hostname: url.hostname, port: url.port,
      path: url.pathname + url.search,
      headers: {
        'Content-Type': 'application/json',
        ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
    }, (res) => {
      let text = '';
      res.on('data', (chunk) => { text += chunk; });
      res.on('end', () => {
        try { resolve({ status: res.statusCode, body: JSON.parse(text) }); }
        catch { resolve({ status: res.statusCode, body: {} }); }
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function cleanup() {
  await pool.query(`DELETE FROM medorbit.audit_logs
    WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)`, [email]);
  await pool.query(`DELETE FROM medorbit.notifications
    WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)`, [email]);
  await pool.query('DELETE FROM medorbit.clinics WHERE owner_user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [email]);
  await pool.query('DELETE FROM medorbit.users WHERE email=$1', [email]);
}

async function main() {
  try {
    const registered = await request('POST', '/auth/register', {
      email, password: 'ClinicPass1!', role: 'clinic',
      firstNameAr: 'Clinic', lastNameAr: 'Account',
      firstNameEn: 'Clinic', lastNameEn: 'Account',
    });
    check('clinic registration is accepted', registered.status === 201);

    const account = await pool.query(
      `SELECT u.id,u.role,u.email_verified,
        EXISTS(SELECT 1 FROM medorbit.patients p WHERE p.user_id=u.id) AS is_patient
       FROM medorbit.users u WHERE u.email=$1`, [email]);
    check('new applicant has clinic role and no patient record',
      account.rows.length === 1 && account.rows[0].role === 'clinic' && !account.rows[0].is_patient);

    await pool.query('UPDATE medorbit.users SET email_verified=true WHERE email=$1', [email]);
    const login = await request('POST', '/auth/login', { email, password: 'ClinicPass1!' });
    const token = login.body?.data?.accessToken;
    check('verified clinic can sign in as pending applicant',
      login.status === 200 && login.body?.data?.user?.clinic_account_status === 'needs_application' && !!token);

    const submitted = await request('POST', '/clinic-applications', {
      name_ar: 'Clinic Arab', name_en: 'Clinic English',
      address_ar: 'Address Arab', address_en: 'Address English',
      city: 'Nablus', phone: '+970599999999', registration_number: 'W1-REG-1',
      type: 'clinic', services: ['general_medicine'],
    }, token);
    check('verified clinic can submit its own application', submitted.status === 201);

    const profile = await request('GET', '/users/me', null, token);
    check('session reports pending clinic approval state',
      profile.status === 200 && profile.body?.data?.clinic_account_status === 'pending');

    const workspace = await request('GET', '/clinics/me', null, token);
    check('pending clinic is denied workspace access',
      workspace.status === 403 && workspace.body?.error?.code === 'CLINIC_APPROVAL_REQUIRED');
  } finally {
    await cleanup();
    await pool.end();
  }
  if (failures) process.exitCode = 1;
  console.log(`\nClinic applicant role checks: ${failures ? 'failed' : 'passed'}`);
}

main().catch(async (error) => {
  console.error(error);
  await cleanup().catch(() => {});
  await pool.end();
  process.exitCode = 1;
});

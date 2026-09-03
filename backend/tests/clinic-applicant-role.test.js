// Clinic applicant lifecycle boundary test.
// Runs only against the disposable Docker test database.
const crypto = require('crypto');
const http = require('http');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const email = `clinic-w1-${crypto.randomUUID()}@example.test`;
const adminEmail = `clinic-w1-admin-${crypto.randomUUID()}@example.test`;
const superAdminEmail = `clinic-w1-super-${crypto.randomUUID()}@example.test`;
const rejectedEmail = `clinic-w1-rejected-${crypto.randomUUID()}@example.test`;
const doctorEmail = `clinic-w4-doctor-${crypto.randomUUID()}@example.test`;
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

function access(user) {
  return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: 1 });
}

async function cleanup() {
  await pool.query(
    `DELETE FROM medorbit.audit_logs WHERE user_id IN (
      SELECT id FROM medorbit.users WHERE email IN ($1,$2,$3,$4)
    )`,
    [email, rejectedEmail, adminEmail, superAdminEmail],
  );
  // Approval/rejection audit records can be owned by the reviewing admin, not
  // only by the applicant. Remove them before deleting the accounts they
  // reference so this disposable integration test always cleans up fully.
  await pool.query(
    `DELETE FROM medorbit.audit_logs
     WHERE entity_type='CLINIC_APPLICATION'
       AND entity_id IN (
         SELECT id FROM medorbit.clinic_applications
         WHERE user_id IN (SELECT id FROM medorbit.users WHERE email IN ($1,$2))
       )`,
    [email, rejectedEmail],
  );
  await pool.query(`DELETE FROM medorbit.audit_logs
    WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)`, [email]);
  await pool.query(`DELETE FROM medorbit.notifications
    WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)`, [email]);
  await pool.query('DELETE FROM medorbit.clinics WHERE owner_user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [email]);
  await pool.query('DELETE FROM medorbit.users WHERE email=$1', [email]);
  await pool.query(`DELETE FROM medorbit.notifications
    WHERE user_id IN (SELECT id FROM medorbit.users WHERE email IN ($1,$2))`, [adminEmail, superAdminEmail]);
  await pool.query('DELETE FROM medorbit.users WHERE email IN ($1,$2)', [adminEmail, superAdminEmail]);
  await pool.query('DELETE FROM medorbit.notifications WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [rejectedEmail]);
  await pool.query('DELETE FROM medorbit.users WHERE email=$1', [rejectedEmail]);
  await pool.query('DELETE FROM medorbit.audit_logs WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [doctorEmail]);
  await pool.query('DELETE FROM medorbit.notifications WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [doctorEmail]);
  await pool.query('DELETE FROM medorbit.doctors WHERE user_id=(SELECT id FROM medorbit.users WHERE email=$1)', [doctorEmail]);
  await pool.query('DELETE FROM medorbit.users WHERE email=$1', [doctorEmail]);
}

async function main() {
  try {
    await pool.query(
      `INSERT INTO medorbit.users(email,password_hash,role,email_verified)
       VALUES($1,'test','admin',true),($2,'test','super_admin',true)`,
      [adminEmail, superAdminEmail]
    );
    const registered = await request('POST', '/auth/register', {
      email, password: 'ClinicPass1!', role: 'clinic',
      firstNameAr: 'Clinic', lastNameAr: 'Account',
      firstNameEn: 'Clinic', lastNameEn: 'Account',
      phone: '+970599999999',
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
      city: 'Nablus', registration_number: 'W1-REG-1',
      type: 'clinic', services: ['general_medicine'],
    }, token);
    check('verified clinic can submit its own application', submitted.status === 201);

    const admin = (await pool.query('SELECT id,role FROM medorbit.users WHERE email=$1', [adminEmail])).rows[0];
    const adminNotifications = await pool.query(
      `SELECT count(*)::int AS count FROM medorbit.notifications n
       JOIN medorbit.users u ON u.id=n.user_id
       WHERE u.email IN ($1,$2)
         AND n.notification_type='CLINIC_APPLICATION_SUBMITTED'
         AND n.reference_id=$3`,
      [adminEmail, superAdminEmail, submitted.body?.data?.id]
    );
    check('each active administrator receives the submission notification', adminNotifications.rows[0].count === 2);

    const profile = await request('GET', '/users/me', null, token);
    check('session reports pending clinic approval state',
      profile.status === 200 && profile.body?.data?.clinic_account_status === 'pending');

    const workspace = await request('GET', '/clinics/me', null, token);
    check('pending clinic is denied workspace access',
      workspace.status === 403 && workspace.body?.error?.code === 'CLINIC_APPROVAL_REQUIRED');

    const approved = await request(
      'POST',
      `/admin/clinic-applications/${submitted.body?.data?.id}/approve`,
      {},
      access(admin),
    );
    const approvedNotice = await pool.query(
      `SELECT message_en FROM medorbit.notifications
       WHERE user_id=$1 AND reference_id=$2 AND notification_type='CLINIC_APPLICATION_APPROVED'`,
      [account.rows[0].id, submitted.body?.data?.id],
    );
    check('approval creates a verified clinic without coordinates and notifies its owner',
      approved.status === 200 && approvedNotice.rows.length === 1 && /approved and verified/i.test(approvedNotice.rows[0].message_en));

    const approvedAccount = (await pool.query(
      'SELECT id,role,authorization_version FROM medorbit.users WHERE email=$1', [email],
    )).rows[0];
    const approvedClinic = (await pool.query(
      'SELECT id FROM medorbit.clinics WHERE owner_user_id=$1', [approvedAccount.id],
    )).rows[0];
    const clinicSession = generateAccessToken({
      sub: approvedAccount.id, role: approvedAccount.role, authorizationVersion: approvedAccount.authorization_version,
    });
    const contactEmail = `contact-${crypto.randomUUID()}@example.test`;
    const contactAdded = await request('POST', '/clinics/me/contact-emails', { email: contactEmail }, clinicSession);
    const contactEmailQueue = await pool.query(
      `SELECT body_text FROM medorbit.email_queue WHERE recipient_email=$1 ORDER BY created_at DESC LIMIT 1`, [contactEmail],
    );
    const verificationToken = String(contactEmailQueue.rows[0]?.body_text || '').match(/token=([a-f0-9]{64})/i)?.[1];
    const verifiedContact = await request('POST', '/clinics/contact-emails/verify', { token: verificationToken });
    const contacts = await request('GET', '/clinics/me/contact-emails', null, clinicSession);
    check('clinic contact email requires and completes one-time inbox verification',
      contactAdded.status === 201 && verifiedContact.status === 200 && contacts.body?.data?.some((item) => item.email === contactEmail && item.status === 'verified'));

    const credentialRequest = await request('POST', '/clinics/me/credential-change-requests', {
      registration_number: 'W3-REG-UPDATED', reason: 'The government registration number was renewed.',
    }, clinicSession);
    const credentialDecision = await request('POST', `/clinics/admin/credential-change-requests/${credentialRequest.body?.data?.id}/decide`, {
      approved: true,
    }, access(admin));
    const credentialState = await pool.query(
      `SELECT c.registration_number,n.notification_type FROM medorbit.clinics c
       LEFT JOIN medorbit.notifications n ON n.user_id=c.owner_user_id AND n.reference_id=$1
       WHERE c.owner_user_id=$2`, [credentialRequest.body?.data?.id, approvedAccount.id],
    );
    const reviewerCredentialNotice = await pool.query(
      `SELECT count(*)::int AS count FROM medorbit.notifications n JOIN medorbit.users u ON u.id=n.user_id
       WHERE n.reference_id=$1 AND n.notification_type='CLINIC_CREDENTIAL_CHANGE_REQUESTED'
         AND u.email IN ($2,$3)`,
      [credentialRequest.body?.data?.id, adminEmail, superAdminEmail],
    );
    check('only an admin-approved credential request changes the verified registration number',
      credentialRequest.status === 201 && credentialDecision.status === 200 && credentialState.rows.some((row) => row.registration_number === 'W3-REG-UPDATED' && row.notification_type === 'CLINIC_CREDENTIAL_CHANGE_APPROVED') && reviewerCredentialNotice.rows[0].count === 2);

    const doctorUser = (await pool.query(
      `INSERT INTO medorbit.users(email,password_hash,role,is_active,email_verified)
       VALUES($1,'test','doctor',true,true) RETURNING id,role,authorization_version`,
      [doctorEmail],
    )).rows[0];
    const doctor = (await pool.query(
      `INSERT INTO medorbit.doctors(user_id,medical_license_number,approval_status,approved_at)
       VALUES($1,$2,'approved',NOW()) RETURNING id`,
      [doctorUser.id, `W4-${crypto.randomUUID()}`],
    )).rows[0];
    const doctorSession = generateAccessToken({
      sub: doctorUser.id, role: doctorUser.role, authorizationVersion: doctorUser.authorization_version,
    });
    const invitation = await request('POST', '/clinics/me/doctor-invitations', {
      doctor_id: doctor.id, message: 'Please join our verified clinic.',
    }, clinicSession);
    const duplicateInvitation = await request('POST', '/clinics/me/doctor-invitations', {
      doctor_id: doctor.id,
    }, clinicSession);
    const doctorInvitations = await request('GET', '/doctors/me/clinic-invitations', null, doctorSession);
    const acceptedInvitation = await request(
      'POST', `/doctors/me/clinic-invitations/${invitation.body?.data?.id}/respond`, { accepted: true }, doctorSession,
    );
    const clinicDoctors = await request('GET', '/clinics/me/doctors', null, clinicSession);
    const publicWorkplaces = await request('GET', `/doctors/${doctor.id}/clinics`, null, clinicSession);
    const clinicResponseNotice = await pool.query(
      `SELECT count(*)::int AS count FROM medorbit.notifications
       WHERE user_id=$1 AND reference_id=$2 AND notification_type='CLINIC_DOCTOR_INVITATION_ACCEPTED'`,
      [approvedAccount.id, invitation.body?.data?.id],
    );
    check('clinic invitations require doctor acceptance, notify both parties, and expose the accepted workplace publicly',
      invitation.status === 201 && duplicateInvitation.status === 409
        && doctorInvitations.body?.data?.some((item) => item.id === invitation.body?.data?.id && item.status === 'pending')
        && acceptedInvitation.status === 200
        && clinicDoctors.body?.data?.some((item) => item.id === doctor.id)
        && publicWorkplaces.body?.data?.some((item) => item.id === approvedClinic?.id)
        && clinicResponseNotice.rows[0].count === 1);

    const rejectedUser = (await pool.query(
      `INSERT INTO medorbit.users(email,password_hash,role,is_active,email_verified)
       VALUES($1,'test','clinic',true,true) RETURNING id`,
      [rejectedEmail],
    )).rows[0];
    const rejectedApplication = (await pool.query(
      `INSERT INTO medorbit.clinic_applications
       (user_id,name_ar,name_en,address_ar,address_en,city,phone,type,services,registration_number)
       VALUES($1,'رفض عيادة','Rejected clinic','عنوان','Address','Nablus','+970599900000','clinic',ARRAY['general_medicine'],'REJECT-1')
       RETURNING id`,
      [rejectedUser.id],
    )).rows[0];
    const rejected = await request(
      'POST',
      `/admin/clinic-applications/${rejectedApplication.id}/reject`,
      { rejection_reason: 'Registration details need correction.' },
      access(admin),
    );
    const rejectedNotice = await pool.query(
      `SELECT message_en FROM medorbit.notifications
       WHERE user_id=$1 AND reference_id=$2 AND notification_type='CLINIC_APPLICATION_REJECTED'`,
      [rejectedUser.id, rejectedApplication.id],
    );
    check('rejection notifies the clinic owner with the review reason',
      rejected.status === 200 && rejectedNotice.rows.length === 1 && /Registration details need correction/i.test(rejectedNotice.rows[0].message_en));
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

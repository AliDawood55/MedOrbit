const crypto = require('crypto');
const { Pool } = require('pg');
const { spawnSync } = require('child_process');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const run = Date.now();
let passed = 0; let failed = 0;
const ids = {};
function check(name, ok, detail = '') { if (ok) { passed++; console.log(`  ✓ ${name}`); } else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); } }
function jwt(id, role, version = 1) { return generateAccessToken({ sub: id, role, authorizationVersion: version }); }
async function request(method, route, token, body) { const headers = token ? { Authorization: `Bearer ${token}` } : {}; if (body !== undefined) headers['Content-Type'] = 'application/json'; const r = await fetch(`${apiBase}${route}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }); return { status: r.status, body: await r.json() }; }
async function user(key, role = 'patient', opts = {}) { ids[key] = crypto.randomUUID(); await pool.query(`INSERT INTO medorbit.users (id,email,password_hash,role,is_active,email_verified,authorization_version,deleted_at) VALUES ($1,$2,'test-only',$3,$4,$5,1,$6)`, [ids[key], `s1c_${key}_${run}@medorbit.test`, role, opts.active ?? true, opts.verified ?? true, opts.deleted ? new Date() : null]); return ids[key]; }
async function bootstrap(email, extra = {}) {
  const { rows } = await pool.query(`SELECT (pg_control_system()).system_identifier::text AS system_identifier`);
  return spawnSync(process.execPath, ['scripts/bootstrap-super-admin.js'], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      NODE_ENV: 'test',
      MEDORBIT_TEST_ISOLATION: 'docker',
      MEDORBIT_BOOTSTRAP_TEST_MODE: 'true',
      SUPER_ADMIN_BOOTSTRAP_EMAIL: email,
      MEDORBIT_EXPECTED_SYSTEM_IDENTIFIER: rows[0].system_identifier,
      ...extra,
    },
    encoding: 'utf8',
  });
}

(async () => {
  try {
    const ledger = await pool.query(`SELECT version FROM medorbit.schema_migrations WHERE version='004'`);
    check('S1C migration ledger records version', ledger.rows.length === 1);
    await user('bootstrap');
    const bootEmail = `s1c_bootstrap_${run}@medorbit.test`;
    await pool.query('UPDATE medorbit.users SET email=$1 WHERE id=$2', [bootEmail, ids.bootstrap]);
    await pool.query(`INSERT INTO medorbit.user_sessions (user_id,refresh_token_hash,expires_at) VALUES ($1,$2,NOW()+INTERVAL '1 day')`, [ids.bootstrap, crypto.createHash('sha256').update(`bootstrap-session-${run}`).digest('hex')]);
    const oldBootAccess = jwt(ids.bootstrap, 'patient'); const boot = await bootstrap(bootEmail);
    check('eligible bootstrap succeeds', boot.status === 0, boot.stderr);
    let row = (await pool.query('SELECT role,authorization_version FROM medorbit.users WHERE id=$1', [ids.bootstrap])).rows[0];
    check('bootstrap grants super_admin and advances version', row.role === 'super_admin' && row.authorization_version === 2);
    check('bootstrap revokes sessions', (await pool.query('SELECT revoked_at FROM medorbit.user_sessions WHERE user_id=$1', [ids.bootstrap])).rows[0].revoked_at !== null);
    check('bootstrap invalidates old access', (await request('GET', '/admin/users', oldBootAccess)).status === 401);
    check('bootstrap is idempotent', (await bootstrap(bootEmail)).status === 0);
    check('bootstrap rejects localhost/native configuration', (await bootstrap(bootEmail, { DB_HOST: 'localhost' })).status !== 0);

    await user('ordinary', 'admin'); await user('doctor', 'doctor'); await user('invitee'); await user('wrong'); await user('managed');
    const superToken = jwt(ids.bootstrap, 'super_admin', 2); const ordinaryToken = jwt(ids.ordinary, 'admin'); const doctorToken = jwt(ids.doctor, 'doctor'); const patientToken = jwt(ids.wrong, 'patient');
    const adminAndSuperAdminRoutes = [
      '/admin/audit-logs',
      '/admin/notifications/templates',
      '/admin/system-settings',
    ];
    for (const route of adminAndSuperAdminRoutes) {
      check(`patient is denied ${route}`, (await request('GET', route, patientToken)).status === 403);
      check(`doctor is denied ${route}`, (await request('GET', route, doctorToken)).status === 403);
      check(`admin is allowed ${route}`, (await request('GET', route, ordinaryToken)).status === 200);
      check(`super_admin is allowed ${route}`, (await request('GET', route, superToken)).status === 200);
    }
    const unknownClinic = crypto.randomUUID();
    check('patient is denied clinic administration', (await request('PUT', `/clinics/${unknownClinic}`, patientToken, {})).status === 403);
    check('doctor is denied clinic administration', (await request('PUT', `/clinics/${unknownClinic}`, doctorToken, {})).status === 403);
    check('admin reaches clinic administration', (await request('PUT', `/clinics/${unknownClinic}`, ordinaryToken, {})).status === 404);
    check('super_admin reaches clinic administration', (await request('PUT', `/clinics/${unknownClinic}`, superToken, {})).status === 404);
    const singleSettingKey = `s1c_single_setting_${run}`;
    const batchSettingKey = `s1c_batch_setting_${run}`;
    await pool.query(
      `INSERT INTO medorbit.system_settings (setting_key, setting_value, description) VALUES ($1,$2,$3),($4,$5,$6)`,
      [singleSettingKey, JSON.stringify({ enabled: false }), 'S1C single setting', batchSettingKey, JSON.stringify({ mode: 'old' }), 'S1C batch setting']
    );
    const singleSetting = await request('PUT', `/admin/system-settings/${singleSettingKey}`, ordinaryToken, { value: { enabled: true }, requires_restart: true });
    check('admin can update a system setting', singleSetting.status === 200, JSON.stringify(singleSetting.body));
    const singleAudit = await pool.query(
      `SELECT old_values,new_values FROM medorbit.audit_logs WHERE action='SYSTEM_SETTING_UPDATED' AND entity_id=$1 ORDER BY created_at DESC LIMIT 1`,
      [singleSetting.body.data?.id]
    );
    check('single system-setting update has complete audit snapshots', singleAudit.rowCount === 1
      && singleAudit.rows[0].old_values.setting_value.enabled === false
      && singleAudit.rows[0].new_values.setting_value.enabled === true);
    const batchSetting = await request('PUT', '/admin/system-settings', superToken, { settings: [{ key: batchSettingKey, value: { mode: 'new' } }] });
    check('super_admin can batch update system settings', batchSetting.status === 200, JSON.stringify(batchSetting.body));
    const batchAudit = await pool.query(
      `SELECT old_values,new_values FROM medorbit.audit_logs WHERE action='SYSTEM_SETTING_UPDATED' AND entity_id=$1 ORDER BY created_at DESC LIMIT 1`,
      [batchSetting.body.data?.[0]?.id]
    );
    check('batch system-setting update has complete audit snapshots', batchAudit.rowCount === 1
      && batchAudit.rows[0].old_values.setting_value.mode === 'old'
      && batchAudit.rows[0].new_values.setting_value.mode === 'new');
    check('patient cannot create a specialty', (await request('POST', '/specialties', patientToken, { name_ar: 'قلب', name_en: 'Cardiology' })).status === 403);
    check('specialty creation validates bilingual names', (await request('POST', '/specialties', ordinaryToken, { name_ar: '   ', name_en: 'Cardiology' })).status === 400);
    const specialty = await request('POST', '/specialties', ordinaryToken, { name_ar: `تخصص ${run}`, name_en: `Specialty ${run}`, icon: 'heart' });
    const specialtyId = specialty.body.data?.id;
    check('admin can create a specialty', specialty.status === 200 && Boolean(specialtyId), JSON.stringify(specialty.body));
    check('super_admin can update a specialty', (await request('PUT', `/specialties/${specialtyId}`, superToken, { name_en: `Updated specialty ${run}` })).status === 200);
    check('admin can deactivate a specialty', (await request('DELETE', `/specialties/${specialtyId}`, ordinaryToken)).status === 200);
    const specialtyAudits = await pool.query(`SELECT action,old_values,new_values FROM medorbit.audit_logs WHERE entity_type='SPECIALTY' AND entity_id=$1 ORDER BY created_at`, [specialtyId]);
    check('specialty mutations have complete audit events', specialtyAudits.rowCount === 3
      && specialtyAudits.rows[0].action === 'SPECIALTY_CREATED'
      && specialtyAudits.rows[1].old_values.name_en === `Specialty ${run}`
      && specialtyAudits.rows[2].new_values.is_active === false);
    check('patient cannot create a notification template', (await request('POST', '/admin/notifications/templates', patientToken, { name: `blocked-${run}` })).status === 403);
    check('notification template creation validates required fields', (await request('POST', '/admin/notifications/templates', ordinaryToken, { name: `invalid-${run}`, type: 'email' })).status === 400);
    const template = await request('POST', '/admin/notifications/templates', ordinaryToken, {
      name: `s1c-template-${run}`, type: 'email', subject_en: 'Initial subject', subject_ar: 'عنوان', body_html: '<p>Initial body</p>', variables: { name: 'string' },
    });
    const templateId = template.body.data?.id;
    check('admin can create a notification template', template.status === 200 && Boolean(templateId), JSON.stringify(template.body));
    check('super_admin can update a notification template', (await request('PUT', `/admin/notifications/templates/${templateId}`, superToken, { subject_en: 'Updated subject' })).status === 200);
    check('admin can deactivate a notification template', (await request('DELETE', `/admin/notifications/templates/${templateId}`, ordinaryToken)).status === 200);
    const templateAudits = await pool.query(`SELECT action,old_values,new_values FROM medorbit.audit_logs WHERE entity_type='NOTIFICATION_TEMPLATE' AND entity_id=$1 ORDER BY created_at`, [templateId]);
    check('notification-template mutations have complete audit events', templateAudits.rowCount === 3
      && templateAudits.rows[0].action === 'NOTIFICATION_TEMPLATE_CREATED'
      && templateAudits.rows[1].old_values.subject_en === 'Initial subject'
      && templateAudits.rows[2].new_values.is_active === false);
    let create = await request('POST', '/admin/invitations', superToken, { email: `s1c_invitee_${run}@medorbit.test` });
    check('super_admin can create invitation', create.status === 201, JSON.stringify(create.body));
    const link = create.body.data.acceptance_url; const raw = new URL(link).searchParams.get('token');
    const invitationId = create.body.data.invitation.id;
    const stored = (await pool.query('SELECT token_hash FROM medorbit.admin_invitations WHERE id=$1', [invitationId])).rows[0];
    check('token is hash-only and list DTO omits it', stored.token_hash !== raw && !(await request('GET', '/admin/invitations', superToken)).body.data[0].token_hash);
    check('invitation creation is audited', (await pool.query(`SELECT 1 FROM medorbit.audit_logs WHERE action='ADMIN_INVITATION_CREATED' AND entity_id=$1`, [invitationId])).rowCount === 1);
    check('ordinary admin cannot create invitation', (await request('POST', '/admin/invitations', ordinaryToken, { email: 'nope@example.test' })).status === 403);
    check('duplicate active invitation rejected', (await request('POST', '/admin/invitations', superToken, { email: `s1c_invitee_${run}@medorbit.test` })).status === 409);
    check('wrong email cannot accept', (await request('POST', '/admin/invitations/accept', jwt(ids.wrong, 'patient'), { token: raw })).status === 403);
    await pool.query(`INSERT INTO medorbit.user_sessions (user_id,refresh_token_hash,expires_at) VALUES ($1,$2,NOW()+INTERVAL '1 day')`, [ids.invitee, crypto.createHash('sha256').update(`invitee-session-${run}`).digest('hex')]);
    const oldInvitee = jwt(ids.invitee, 'patient'); let accept = await request('POST', '/admin/invitations/accept', oldInvitee, { token: raw });
    check('correct verified account accepts and becomes admin', accept.status === 200 && (await pool.query('SELECT role FROM medorbit.users WHERE id=$1', [ids.invitee])).rows[0].role === 'admin', JSON.stringify(accept.body));
    check('acceptance revokes sessions and invalidates access', (await request('GET', '/admin/users', oldInvitee)).status === 401 && (await pool.query('SELECT revoked_at FROM medorbit.user_sessions WHERE user_id=$1', [ids.invitee])).rows[0].revoked_at !== null);
    check('invitation acceptance is audited', (await pool.query(`SELECT 1 FROM medorbit.audit_logs WHERE action='ADMIN_INVITATION_ACCEPTED' AND entity_id=$1`, [invitationId])).rowCount === 1);
    check('accepted token cannot be reused', (await request('POST', '/admin/invitations/accept', jwt(ids.invitee, 'admin', 2), { token: raw })).status === 409);
    await user('revoke'); const rev = await request('POST', '/admin/invitations', superToken, { email: `s1c_revoke_${run}@medorbit.test` });
    check('super_admin can revoke and ordinary admin cannot', (await request('DELETE', `/admin/invitations/${rev.body.data.invitation.id}`, superToken)).status === 200 && (await request('DELETE', `/admin/invitations/${rev.body.data.invitation.id}`, ordinaryToken)).status === 403);
    check('invitation revocation is audited', (await pool.query(`SELECT 1 FROM medorbit.audit_logs WHERE action='ADMIN_INVITATION_REVOKED' AND entity_id=$1`, [rev.body.data.invitation.id])).rowCount === 1);
    check('revoked token is rejected', (await request('POST', '/admin/invitations/accept', jwt(ids.revoke, 'patient'), { token: new URL(rev.body.data.acceptance_url).searchParams.get('token') })).status === 409);
    check('ordinary admin cannot mutate super_admin', (await request('PUT', `/admin/users/${ids.bootstrap}/deactivate`, ordinaryToken)).status === 403);
    check('super_admin cannot mutate own security state', (await request('PUT', `/admin/users/${ids.bootstrap}/deactivate`, superToken)).status === 403);
    const deactivate = await request('PUT', `/admin/users/${ids.managed}/deactivate`, superToken);
    const reactivate = await request('PUT', `/admin/users/${ids.managed}/reactivate`, superToken);
    check('super_admin can deactivate and reactivate an ordinary user', deactivate.status === 200 && reactivate.status === 200, JSON.stringify({ deactivate, reactivate }));
    const userStateAudits = await pool.query(
      `SELECT action, old_values, new_values FROM medorbit.audit_logs
       WHERE entity_type='USER' AND entity_id=$1 AND action IN ('USER_DEACTIVATED','USER_REACTIVATED')
       ORDER BY created_at`,
      [ids.managed]
    );
    check('user state changes have complete audit snapshots', userStateAudits.rowCount === 2
      && userStateAudits.rows[0].old_values.is_active === true
      && userStateAudits.rows[0].new_values.is_active === false
      && userStateAudits.rows[1].old_values.is_active === false
      && userStateAudits.rows[1].new_values.is_active === true);
    const audit = await pool.query(`SELECT old_values,new_values FROM medorbit.audit_logs WHERE action LIKE 'ADMIN_%' OR action='SUPER_ADMIN_BOOTSTRAPPED'`);
    check('audit snapshots contain no credential material', audit.rows.every(x => !/password_hash|token_hash|google_id|refresh_token/i.test(JSON.stringify(x))));
  } catch (err) { failed++; console.error(err); }
  finally { await pool.end(); console.log(`\nS1C admin foundation: ${passed} passed, ${failed} failed`); process.exitCode = failed ? 1 : 0; }
})();

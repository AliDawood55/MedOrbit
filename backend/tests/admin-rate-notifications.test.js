const crypto = require('crypto');
const express = require('express');
const { Pool } = require('pg');

const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');
const { createGeneralApiLimiter } = require('../src/middleware/rateLimit');

const pool = new Pool(poolConfig);
const marker = `admin_notif_${Date.now()}`;
const createdUsers = [];
const applicationIds = [];
const ids = {};
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  ✓ ${name}`);
    } else {
        failed += 1;
        console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

function access(user, version = 1) {
    return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: version });
}

async function request(method, path, token, body) {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    let responseBody = null;
    try { responseBody = await response.json(); } catch { responseBody = null; }
    return { status: response.status, body: responseBody, headers: response.headers };
}

async function createUser(key, role = 'patient', withPatient = role === 'patient') {
    const user = { id: crypto.randomUUID(), role, email: `${marker}_${key}@medorbit.test` };
    createdUsers.push(user.id);
    await pool.query(
        `INSERT INTO medorbit.users
            (id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES($1,$2,'focused-test-only',$3,true,true,1)`,
        [user.id, user.email, role]
    );
    await pool.query(
        `INSERT INTO medorbit.user_profiles
            (user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
         VALUES($1,'اختبار','إشعار',$2,'Notification')`,
        [user.id, key]
    );
    if (withPatient) {
        user.patientId = crypto.randomUUID();
        await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)', [user.patientId, user.id]);
    }
    return user;
}

async function createDoctor(key) {
    const user = await createUser(key, 'doctor', true);
    user.doctorId = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.doctors
            (id,user_id,medical_license_number,specialty_id,approval_status,approved_at)
         VALUES($1,$2,$3,$4,'approved',NOW())`,
        [user.doctorId, user.id, `${marker}-${key}`, ids.specialty]
    );
    return user;
}

async function submit(user, suffix, extra = {}) {
    const result = await request('POST', '/doctor-applications', access(user), {
        specialty_id: ids.specialty,
        medical_license_number: `${marker}-${suffix}`,
        years_of_experience: 4,
        bio_en: `${marker}-private-clinical-marker`,
        ...extra,
    });
    if (result.status === 201) applicationIds.push(result.body.data.id);
    return result;
}

async function startProbeServer() {
    const app = express();
    app.use(createGeneralApiLimiter({
        windowMs: 60_000,
        authenticatedMax: 2,
        anonymousMax: 2,
        skip: () => false,
    }));
    app.get('/probe', (req, res) => res.json({ success: true }));

    const server = await new Promise((resolve) => {
        const listener = app.listen(0, '127.0.0.1', () => resolve(listener));
    });
    return {
        url: `http://127.0.0.1:${server.address().port}/probe`,
        close: () => new Promise((resolve) => server.close(resolve)),
    };
}

async function cleanup() {
    await pool.query('DROP TRIGGER IF EXISTS admin_notif_test_force_failure ON medorbit.notifications').catch(() => {});
    await pool.query('DROP FUNCTION IF EXISTS medorbit.admin_notif_test_force_failure()').catch(() => {});

    if (applicationIds.length) {
        await pool.query(
            `DELETE FROM medorbit.outbox_events
             WHERE event_type='doctor.application.approved'
               AND aggregate_id=ANY($1::uuid[])`,
            [applicationIds]
        ).catch(() => {});
        await pool.query('DELETE FROM medorbit.notifications WHERE reference_id=ANY($1::uuid[])', [applicationIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.audit_logs WHERE entity_id=ANY($1::uuid[])', [applicationIds]).catch(() => {});
    }
    if (createdUsers.length) {
        await pool.query('DELETE FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctor_applications WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_sessions WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
    }
    if (ids.specialty) {
        await pool.query('DELETE FROM medorbit.specialties WHERE id=$1', [ids.specialty]).catch(() => {});
    }
}

async function residualCounts() {
    const result = {};
    result.users = Number((await pool.query('SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[])', [createdUsers])).rows[0].count);
    result.notifications = applicationIds.length
        ? Number((await pool.query('SELECT count(*) FROM medorbit.notifications WHERE reference_id=ANY($1::uuid[])', [applicationIds])).rows[0].count)
        : 0;
    result.applications = Number((await pool.query('SELECT count(*) FROM medorbit.doctor_applications WHERE user_id=ANY($1::uuid[])', [createdUsers])).rows[0].count);
    result.specialties = ids.specialty
        ? Number((await pool.query('SELECT count(*) FROM medorbit.specialties WHERE id=$1', [ids.specialty])).rows[0].count)
        : 0;
    return result;
}

(async () => {
    let probe = null;
    try {
        console.log('\nAdmin rate-limit and doctor-application notification tests\n');
        check('integration database is medorbit_test', poolConfig.database === 'medorbit_test');

        ids.specialty = crypto.randomUUID();
        await pool.query(
            `INSERT INTO medorbit.specialties(id,name_ar,name_en)
             VALUES($1,'اختبار الإشعارات',$2)`,
            [ids.specialty, marker]
        );
        const applicant = await createUser('applicant');
        const otherPatient = await createUser('other');
        const admin = await createUser('admin', 'admin', false);
        const superAdmin = await createUser('super', 'super_admin', false);
        const ordinaryDoctor = await createDoctor('doctor');
        const approveUser = await createUser('approve');
        const failedUser = await createUser('failed');

        probe = await startProbeServer();
        const probeA = access({ id: crypto.randomUUID(), role: 'admin' });
        const probeB = access({ id: crypto.randomUUID(), role: 'admin' });
        const probeAResults = [];
        for (let i = 0; i < 3; i += 1) probeAResults.push(await fetch(probe.url, { headers: { Authorization: `Bearer ${probeA}` } }));
        check('ordinary authenticated reads remain rate-limited', probeAResults.map((r) => r.status).join(',') === '200,200,429');
        check('distinct signed-in users do not share a bucket', (await fetch(probe.url, { headers: { Authorization: `Bearer ${probeB}` } })).status === 200);
        const anonymousResults = [];
        for (let i = 0; i < 3; i += 1) anonymousResults.push(await fetch(probe.url));
        check('unauthenticated abuse remains IP-limited', anonymousResults.map((r) => r.status).join(',') === '200,200,429');
        const anonymous429Body = await anonymousResults[2].json();
        check(
            '429 response is safe and includes Retry-After',
            anonymous429Body?.success === false &&
            anonymous429Body?.error?.code === 'RATE_LIMITED' &&
            Number(anonymousResults[2].headers.get('retry-after')) > 0
        );
        check('client-supplied fake bearer identity cannot escape the IP bucket', (await fetch(probe.url, { headers: { Authorization: 'Bearer forged-client-id' } })).status === 429);
        await probe.close();
        probe = null;

        const created = await submit(applicant, 'first');
        const firstApplicationId = created.body?.data?.id;
        check('valid doctor application is pending and patient-owned', created.status === 201 && created.body.data.status === 'pending' && created.body.data.user_id === applicant.id, JSON.stringify(created.body));

        const reviewerNotifications = await pool.query(
            `SELECT id,user_id,title_ar,title_en,message_ar,message_en,notification_type,reference_id,reference_type
             FROM medorbit.notifications
             WHERE reference_id=$1 AND notification_type='DOCTOR_APPLICATION_SUBMITTED'
               AND user_id=ANY($2::uuid[])
             ORDER BY user_id`,
            [firstApplicationId, [admin.id, superAdmin.id]]
        );
        check(
            'submission creates exactly one notification per admin and super_admin',
            reviewerNotifications.rowCount === 2 &&
            reviewerNotifications.rows.filter((row) => row.user_id === admin.id).length === 1 &&
            reviewerNotifications.rows.filter((row) => row.user_id === superAdmin.id).length === 1
        );
        const adminNotification = reviewerNotifications.rows.find((row) => row.user_id === admin.id);
        const superNotification = reviewerNotifications.rows.find((row) => row.user_id === superAdmin.id);

        const retry = await submit(applicant, 'first');
        const afterRetryCount = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE reference_id=$1 AND notification_type='DOCTOR_APPLICATION_SUBMITTED'
               AND user_id=ANY($2::uuid[])`,
            [firstApplicationId, [admin.id, superAdmin.id]]
        )).rows[0].count);
        check('network-style retry cannot duplicate the application notification', retry.status === 409 && afterRetryCount === 2);

        const patientInbox = await request('GET', '/notifications', access(otherPatient));
        const patientIdor = await request('PUT', `/notifications/${adminNotification.id}/read`, access(otherPatient));
        check('patient cannot read or mark an admin notification', patientInbox.status === 200 && !patientInbox.body.data.some((item) => item.id === adminNotification.id) && patientIdor.status === 404);
        const doctorInbox = await request('GET', '/notifications', access(ordinaryDoctor));
        const doctorIdor = await request('PUT', `/notifications/${adminNotification.id}/read`, access(ordinaryDoctor));
        check('ordinary doctor cannot read or mark an admin notification', doctorInbox.status === 200 && !doctorInbox.body.data.some((item) => item.id === adminNotification.id) && doctorIdor.status === 404);
        const adminInbox = await request('GET', '/notifications', access(admin));
        const superInbox = await request('GET', '/notifications', access(superAdmin));
        check('admin can read own reviewer notification with safe reference', adminInbox.status === 200 && adminInbox.body.data.some((item) => item.id === adminNotification.id && item.reference_id === firstApplicationId));
        check('super_admin can read own reviewer notification', superInbox.status === 200 && superInbox.body.data.some((item) => item.id === superNotification.id));

        const unreadBefore = await request('GET', '/notifications/unread-count', access(admin));
        const marked = await request('PUT', `/notifications/${adminNotification.id}/read`, access(admin));
        const unreadAfter = await request('GET', '/notifications/unread-count', access(admin));
        check('unread count includes new application notification', unreadBefore.status === 200 && unreadBefore.body.data.count >= 1);
        check('owner mark-read decreases unread count by one', marked.status === 200 && marked.body.data.is_read === true && unreadAfter.body.data.count === unreadBefore.body.data.count - 1);

        const safeNotificationText = JSON.stringify(reviewerNotifications.rows);
        check(
            'reviewer notification contains no secrets, clinical data, applicant email, or license',
            !safeNotificationText.includes(applicant.email) &&
            !safeNotificationText.includes(`${marker}-first`) &&
            !safeNotificationText.includes(`${marker}-private-clinical-marker`) &&
            !/(password|token|credential)/i.test(safeNotificationText)
        );

        const rejected = await request('POST', `/admin/doctor-applications/${firstApplicationId}/reject`, access(admin), { rejection_reason: 'Focused test reason' });
        const rejectionNoticeCount = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='DOCTOR_APPLICATION_REJECTED'`,
            [applicant.id, firstApplicationId]
        )).rows[0].count);
        check('rejection still notifies the applicant transactionally', rejected.status === 200 && rejectionNoticeCount === 1);

        const reapplied = await submit(applicant, 'reapply');
        const reapplyReviewerCount = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE reference_id=$1 AND notification_type='DOCTOR_APPLICATION_SUBMITTED'
               AND user_id=ANY($2::uuid[])`,
            [reapplied.body?.data?.id, [admin.id, superAdmin.id]]
        )).rows[0].count);
        check('legitimate reapplication creates one new reviewer notification per reviewer', reapplied.status === 201 && reapplied.body.data.id !== firstApplicationId && reapplyReviewerCount === 2);

        const beforeFailure = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])`,
            [[admin.id, superAdmin.id]]
        )).rows[0].count);
        await pool.query(`
            CREATE OR REPLACE FUNCTION medorbit.admin_notif_test_force_failure()
            RETURNS trigger LANGUAGE plpgsql AS $$
            BEGIN
                IF NEW.user_id='${admin.id}'::uuid
                   AND NEW.notification_type='DOCTOR_APPLICATION_SUBMITTED'
                   AND EXISTS (
                       SELECT 1 FROM medorbit.doctor_applications
                       WHERE id=NEW.reference_id AND medical_license_number='${marker}-forced-failure'
                   )
                THEN RAISE EXCEPTION 'controlled reviewer notification failure';
                END IF;
                RETURN NEW;
            END $$`);
        await pool.query(`
            CREATE TRIGGER admin_notif_test_force_failure
            BEFORE INSERT ON medorbit.notifications
            FOR EACH ROW EXECUTE FUNCTION medorbit.admin_notif_test_force_failure()`);
        const forcedFailure = await submit(failedUser, 'forced-failure');
        const afterFailure = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])`,
            [[admin.id, superAdmin.id]]
        )).rows[0].count);
        const failedApplicationCount = Number((await pool.query(
            'SELECT count(*) FROM medorbit.doctor_applications WHERE medical_license_number=$1',
            [`${marker}-forced-failure`]
        )).rows[0].count);
        check('failed submission transaction leaves no application or reviewer notification', forcedFailure.status === 500 && failedApplicationCount === 0 && afterFailure === beforeFailure);
        await pool.query('DROP TRIGGER admin_notif_test_force_failure ON medorbit.notifications');
        await pool.query('DROP FUNCTION medorbit.admin_notif_test_force_failure()');

        const approvalApplication = await submit(approveUser, 'approve');
        const unauthorizedApproval = await request('POST', `/admin/doctor-applications/${approvalApplication.body.data.id}/approve`, access(otherPatient), {});
        const oldApplicantToken = access(approveUser);
        const approved = await request('POST', `/admin/doctor-applications/${approvalApplication.body.data.id}/approve`, access(admin), {});
        const approvedState = (await pool.query('SELECT role,authorization_version FROM medorbit.users WHERE id=$1', [approveUser.id])).rows[0];
        const approvalNoticeCount = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='DOCTOR_APPLICATION_APPROVED'`,
            [approveUser.id, approvalApplication.body.data.id]
        )).rows[0].count);
        check('approval remains admin-only and notifies applicant', unauthorizedApproval.status === 403 && approved.status === 200 && approvalNoticeCount === 1);
        check(
            'existing S2 authorization lifecycle remains intact',
            approvedState.role === 'doctor' && approvedState.authorization_version > 1 &&
            Number((await pool.query('SELECT count(*) FROM medorbit.doctors WHERE user_id=$1', [approveUser.id])).rows[0].count) === 1 &&
            (await request('GET', '/doctor-applications/me', oldApplicantToken)).status === 401
        );

        const normalRequests = [];
        for (let i = 0; i < 20; i += 1) {
            normalRequests.push(await request('GET', '/admin/doctor-applications?status=pending', access(admin)));
            normalRequests.push(await request('GET', `/admin/doctor-applications/${reapplied.body.data.id}`, access(admin)));
        }
        check('normal admin list/detail request volume does not return 429', normalRequests.every((result) => result.status === 200));

        const loginAttempts = [];
        for (let i = 0; i < 11; i += 1) {
            loginAttempts.push(await request('POST', '/auth/login', null, {
                email: `${marker}_missing@medorbit.test`, password: 'wrong-password',
            }));
        }
        check(
            'strict IP-based auth limiter still blocks abuse',
            loginAttempts.slice(0, 10).every((result) => result.status !== 429) &&
            loginAttempts[10].status === 429 &&
            loginAttempts[10].body?.error?.code === 'RATE_LIMITED'
        );
    } catch (err) {
        failed += 1;
        console.error(err.stack || err.message);
    } finally {
        if (probe) await probe.close().catch(() => {});
        await cleanup();
        const residue = await residualCounts().catch((err) => ({ error: err.message }));
        console.log('Focused fixture residual counts:', JSON.stringify(residue));
        check('focused fixtures leave zero residual rows', !residue.error && Object.values(residue).every((value) => value === 0), JSON.stringify(residue));
        await pool.end();
        console.log(`\nAdmin rate-limit/notifications: ${passed} passed, ${failed} failed`);
        process.exitCode = failed ? 1 : 0;
    }
})();

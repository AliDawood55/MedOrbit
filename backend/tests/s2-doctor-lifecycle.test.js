const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const run = Date.now();
const marker = `s2t_${run}`;
const ids = {};
const createdUsers = [];
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
}

async function request(method, path, token, body) {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${path}`, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
}

function access(user, version = 1) {
    return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: version });
}

async function createUser(key, role = 'patient', withPatient = role === 'patient') {
    const user = { id: crypto.randomUUID(), role, email: `${marker}_${key}@medorbit.test` };
    createdUsers.push(user.id); ids[key] = user;
    await pool.query(
        `INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES($1,$2,'s2-test-only',$3,true,true,1)`, [user.id, user.email, role]
    );
    await pool.query(
        `INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
         VALUES($1,'اختبار','طبيب',$2,'S2')`, [user.id, key]
    );
    if (withPatient) {
        user.patientId = crypto.randomUUID();
        await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)', [user.patientId, user.id]);
    }
    return user;
}

async function createDoctor(key, options = {}) {
    const user = await createUser(key, 'doctor', options.withPatient !== false);
    user.doctorId = crypto.randomUUID();
    user.license = options.license || `${marker}-${key}-license`;
    await pool.query(
        `INSERT INTO medorbit.doctors
           (id,user_id,medical_license_number,specialty_id,approval_status,approved_at,is_accepting_patients)
         VALUES($1,$2,$3,$4,$5,NOW(),true)`,
        [user.doctorId, user.id, user.license, ids.specialty, options.status || 'approved']
    );
    return user;
}

async function submit(user, suffix, overrides = {}) {
    return request('POST', '/doctor-applications', access(user), {
        specialty_id: ids.specialty,
        medical_license_number: `${marker}-${suffix}`,
        years_of_experience: 5,
        consultation_fee: 50,
        consultation_duration: 30,
        bio_en: 'S2 test application',
        ...overrides,
    });
}

async function cleanup() {
    await pool.query('DROP TRIGGER IF EXISTS s2_test_force_approval_failure ON medorbit.audit_logs').catch(() => {});
    await pool.query('DROP FUNCTION IF EXISTS medorbit.s2_test_force_approval_failure()').catch(() => {});
    if (createdUsers.length) {
        await pool.query(`DELETE FROM medorbit.outbox_events WHERE event_type='doctor.application.approved' AND payload->>'userId'=ANY($1::text[])`, [createdUsers]).catch(() => {});
        await pool.query(`DELETE FROM medorbit.appointment_status_history WHERE appointment_id IN (SELECT a.id FROM medorbit.appointments a JOIN medorbit.patients p ON p.id=a.patient_id WHERE p.user_id=ANY($1::uuid[]))`, [createdUsers]).catch(() => {});
        await pool.query(`DELETE FROM medorbit.appointments WHERE patient_id IN (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[])) OR doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`, [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[]) OR entity_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctor_applications WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctor_clinic_assignments WHERE doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctor_availability WHERE doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_sessions WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
        await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [createdUsers]).catch(() => {});
    }
    if (ids.clinic) await pool.query('DELETE FROM medorbit.clinics WHERE id=$1', [ids.clinic]).catch(() => {});
    if (ids.specialty) await pool.query('DELETE FROM medorbit.specialties WHERE id=$1', [ids.specialty]).catch(() => {});
}

async function residualCounts() {
    const result = {};
    result.users = (await pool.query('SELECT count(*)::int count FROM medorbit.users WHERE id=ANY($1::uuid[])',[createdUsers])).rows[0].count;
    for (const table of ['user_profiles','patients','doctors','doctor_applications','user_sessions','notifications']) {
        result[table] = (await pool.query(`SELECT count(*)::int count FROM medorbit.${table} WHERE user_id=ANY($1::uuid[])`,[createdUsers])).rows[0].count;
    }
    result.audit_logs = (await pool.query('SELECT count(*)::int count FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[])',[createdUsers])).rows[0].count;
    result.appointments = ids.bookingId ? (await pool.query('SELECT count(*)::int count FROM medorbit.appointments WHERE id=$1',[ids.bookingId])).rows[0].count : 0;
    result.doctor_availability = ids.availabilityId ? (await pool.query('SELECT count(*)::int count FROM medorbit.doctor_availability WHERE id=$1',[ids.availabilityId])).rows[0].count : 0;
    result.specialties = (await pool.query('SELECT count(*)::int count FROM medorbit.specialties WHERE id=$1',[ids.specialty])).rows[0].count;
    result.clinics = (await pool.query('SELECT count(*)::int count FROM medorbit.clinics WHERE id=$1',[ids.clinic])).rows[0].count;
    return result;
}

(async () => {
    try {
        ids.specialty = crypto.randomUUID(); ids.clinic = crypto.randomUUID();
        await pool.query(`INSERT INTO medorbit.specialties(id,name_ar,name_en) VALUES($1,'اختبار','${marker}')`, [ids.specialty]);
        await pool.query(
            `INSERT INTO medorbit.clinics(id,name_ar,name_en,address_ar,address_en,latitude,longitude,verification_status)
             VALUES($1,'عيادة اختبار',$2,'عنوان','Address',32.2,35.2,'verified')`, [ids.clinic, marker]
        );

        const applicant = await createUser('applicant');
        const otherPatient = await createUser('other');
        const admin = await createUser('admin', 'admin', false);
        const superAdmin = await createUser('super', 'super_admin', false);
        const existingDoctor = await createDoctor('existing');
        const unrelatedDoctor = await createDoctor('unrelated');

        check('unauthenticated cannot submit', (await request('POST','/doctor-applications',null,{})).status === 401);
        check('doctor cannot submit', (await submit(existingDoctor,'doctor-apply')).status === 403);
        check('admin cannot submit', (await submit(admin,'admin-apply')).status === 403);
        check('super_admin cannot submit', (await submit(superAdmin,'super-apply')).status === 403);
        check('missing license rejected', (await submit(applicant,'missing',{ medical_license_number:'' })).status === 400);
        check('invalid specialty rejected', (await submit(applicant,'bad-specialty',{ specialty_id:crypto.randomUUID() })).status === 400);
        const created = await submit(applicant,'application',{ user_id:otherPatient.id });
        check('verified patient submits and client user_id is ignored', created.status === 201 && created.body.data.user_id === applicant.id, JSON.stringify(created.body));
        const applicationId = created.body.data.id;
        check('duplicate pending rejected', (await submit(applicant,'duplicate')).status === 409);
        const mine = await request('GET','/doctor-applications/me',access(applicant));
        const others = await request('GET','/doctor-applications/me',access(otherPatient));
        check('own status is returned', mine.status === 200 && mine.body.data.some(x => x.id === applicationId));
        check('cross-user application is not returned', others.status === 200 && !others.body.data.some(x => x.id === applicationId));
        check('pending application can withdraw', (await request('POST',`/doctor-applications/${applicationId}/withdraw`,access(applicant),{})).status === 200);
        check('withdrawn application cannot approve', (await request('POST',`/admin/doctor-applications/${applicationId}/approve`,access(admin),{})).status === 404);

        const rejectUser = await createUser('reject');
        const rejectApp = await submit(rejectUser,'reject'); const rejectId = rejectApp.body.data.id;
        check('rejection requires reason', (await request('POST',`/admin/doctor-applications/${rejectId}/reject`,access(admin),{})).status === 400);
        const rejectedResponse=await request('POST',`/admin/doctor-applications/${rejectId}/reject`,access(admin),{rejection_reason:'Insufficient evidence'});
        check('admin rejects and notifies applicant transactionally', rejectedResponse.status === 200 && Number((await pool.query("SELECT count(*) FROM medorbit.notifications WHERE user_id=$1 AND reference_id=$2 AND notification_type='DOCTOR_APPLICATION_REJECTED'",[rejectUser.id,rejectId])).rows[0].count) === 1);
        const rejectedState = (await pool.query('SELECT status FROM medorbit.doctor_applications WHERE id=$1',[rejectId])).rows[0];
        check('rejected user remains patient with no doctor row', rejectedState.status === 'rejected' && (await pool.query('SELECT role FROM medorbit.users WHERE id=$1',[rejectUser.id])).rows[0].role === 'patient' && Number((await pool.query('SELECT count(*) FROM medorbit.doctors WHERE user_id=$1',[rejectUser.id])).rows[0].count) === 0);
        const reapply = await submit(rejectUser,'reapply');
        check('reapplication creates separate history row', reapply.status === 201 && reapply.body.data.id !== rejectId && Number((await pool.query('SELECT count(*) FROM medorbit.doctor_applications WHERE user_id=$1',[rejectUser.id])).rows[0].count) === 2);
        check('rejected application cannot approve', (await request('POST',`/admin/doctor-applications/${rejectId}/approve`,access(admin),{})).status === 404);

        const approveUser = await createUser('approve');
        const approveApp = await submit(approveUser,'approve');
        await pool.query(`INSERT INTO medorbit.user_sessions(user_id,refresh_token_hash,expires_at) VALUES($1,$2,NOW()+INTERVAL '1 day')`, [approveUser.id, crypto.createHash('sha256').update(`${marker}-session`).digest('hex')]);
        const oldApproveToken = access(approveUser);
        const patientApprovalAttempt=await request('POST',`/admin/doctor-applications/${approveApp.body.data.id}/approve`,access(otherPatient),{});
        const patientReviewAttempt=await request('GET','/admin/doctor-applications?status=pending',access(otherPatient));
        const reviewDetail=await request('GET',`/admin/doctor-applications/${approveApp.body.data.id}`,access(admin));
        check('patient cannot review/approve and admin receives safe review detail', patientApprovalAttempt.status === 403 && patientReviewAttempt.status === 403 && reviewDetail.status === 200 && reviewDetail.body.data.applicant?.email === approveUser.email && reviewDetail.body.data.specialty?.name_en === marker && !JSON.stringify(reviewDetail.body.data).includes('password_hash'));
        const approved = await request('POST',`/admin/doctor-applications/${approveApp.body.data.id}/approve`,access(admin),{});
        check('admin approves and notifies applicant transactionally', approved.status === 200 && Number((await pool.query("SELECT count(*) FROM medorbit.notifications WHERE user_id=$1 AND reference_id=$2 AND notification_type='DOCTOR_APPLICATION_APPROVED'",[approveUser.id,approveApp.body.data.id])).rows[0].count) === 1, JSON.stringify(approved.body));
        const approvedUser = (await pool.query('SELECT role,authorization_version FROM medorbit.users WHERE id=$1',[approveUser.id])).rows[0];
        const approvedApp = (await pool.query('SELECT status,approved_doctor_id,reviewed_by_user_id,reviewed_at FROM medorbit.doctor_applications WHERE id=$1',[approveApp.body.data.id])).rows[0];
        check('approval creates exactly one doctor and sets role', approvedUser.role === 'doctor' && Number((await pool.query('SELECT count(*) FROM medorbit.doctors WHERE user_id=$1',[approveUser.id])).rows[0].count) === 1);
        check('approval retains patient persona', Number((await pool.query('SELECT count(*) FROM medorbit.patients WHERE user_id=$1',[approveUser.id])).rows[0].count) === 1);
        check('approval records doctor/reviewer/time', approvedApp.status === 'approved' && approvedApp.approved_doctor_id && approvedApp.reviewed_by_user_id === admin.id && approvedApp.reviewed_at);
        check('approval advances authorization and revokes sessions', approvedUser.authorization_version > 1 && (await pool.query('SELECT revoked_at FROM medorbit.user_sessions WHERE user_id=$1',[approveUser.id])).rows[0].revoked_at);
        check('old applicant token fails immediately', (await request('GET','/doctor-applications/me',oldApproveToken)).status === 401);
        check('duplicate approval rejected', (await request('POST',`/admin/doctor-applications/${approveApp.body.data.id}/approve`,access(admin),{})).status === 404);

        const superUser = await createUser('superapprove'); const superApp = await submit(superUser,'superapprove');
        check('super_admin can approve', (await request('POST',`/admin/doctor-applications/${superApp.body.data.id}/approve`,access(superAdmin),{})).status === 200);

        const duplicateUser = await createUser('duplicate-license');
        const duplicateApp = await submit(duplicateUser,'duplicate-license',{medical_license_number:existingDoctor.license});
        check('duplicate approved medical license rolls approval back', (await request('POST',`/admin/doctor-applications/${duplicateApp.body.data.id}/approve`,access(admin),{})).status === 409 && (await pool.query('SELECT role FROM medorbit.users WHERE id=$1',[duplicateUser.id])).rows[0].role === 'patient');

        const rollbackUser = await createUser('rollback'); const rollbackApp = await submit(rollbackUser,'rollback'); const rollbackId = rollbackApp.body.data.id;
        await pool.query(`CREATE OR REPLACE FUNCTION medorbit.s2_test_force_approval_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.action='DOCTOR_APPLICATION_APPROVED' AND NEW.entity_id='${rollbackId}'::uuid THEN RAISE EXCEPTION 'controlled s2 rollback'; END IF; RETURN NEW; END $$`);
        await pool.query('CREATE TRIGGER s2_test_force_approval_failure BEFORE INSERT ON medorbit.audit_logs FOR EACH ROW EXECUTE FUNCTION medorbit.s2_test_force_approval_failure()');
        check('controlled post-mutation approval failure returns error', (await request('POST',`/admin/doctor-applications/${rollbackId}/approve`,access(admin),{})).status === 500);
        const rollbackState = (await pool.query('SELECT role FROM medorbit.users WHERE id=$1',[rollbackUser.id])).rows[0];
        const rollbackApplication = (await pool.query('SELECT status,approved_doctor_id,reviewed_by_user_id,reviewed_at FROM medorbit.doctor_applications WHERE id=$1',[rollbackId])).rows[0];
        check('rollback restores user/application/doctor state', rollbackState.role === 'patient' && rollbackApplication.status === 'pending' && !rollbackApplication.approved_doctor_id && !rollbackApplication.reviewed_by_user_id && !rollbackApplication.reviewed_at && Number((await pool.query('SELECT count(*) FROM medorbit.doctors WHERE user_id=$1',[rollbackUser.id])).rows[0].count) === 0);
        check('rollback commits no approval audit/notification', Number((await pool.query("SELECT count(*) FROM medorbit.audit_logs WHERE entity_id=$1 AND action='DOCTOR_APPLICATION_APPROVED'",[rollbackId])).rows[0].count) === 0 && Number((await pool.query("SELECT count(*) FROM medorbit.notifications WHERE reference_id=$1 AND notification_type='DOCTOR_APPLICATION_APPROVED'",[rollbackId])).rows[0].count) === 0);
        await pool.query('DROP TRIGGER s2_test_force_approval_failure ON medorbit.audit_logs'); await pool.query('DROP FUNCTION medorbit.s2_test_force_approval_failure()');

        const availabilityId = crypto.randomUUID(); ids.availabilityId=availabilityId; const date='2030-01-15';
        await pool.query(`INSERT INTO medorbit.doctor_availability(id,doctor_id,clinic_id,specific_date,start_time,end_time,slot_duration,is_active) VALUES($1,$2,$3,$4,'10:00','10:30',30,true)`,[availabilityId,existingDoctor.doctorId,ids.clinic,date]);
        const doctorToken = access(existingDoctor);
        check('approved doctor central capability works', (await request('GET','/doctors/me/patients',doctorToken)).status === 200);
        check('approved doctor appears publicly', (await request('GET',`/doctors/${existingDoctor.doctorId}`,null)).status === 200);
        check('approved availability is bookable', (await request('GET',`/appointments/available-slots?doctor_id=${existingDoctor.doctorId}&clinic_id=${ids.clinic}&date=${date}`,null)).body.data.length === 1);
        await pool.query(`INSERT INTO medorbit.user_sessions(user_id,refresh_token_hash,expires_at) VALUES($1,$2,NOW()+INTERVAL '1 day')`,[existingDoctor.id,crypto.createHash('sha256').update(`${marker}-doctor-session`).digest('hex')]);
        const suspended = await request('POST',`/admin/doctor-applications/doctors/${existingDoctor.doctorId}/suspend`,access(admin),{reason:'S2 test'});
        check('admin suspends and notifies approved doctor transactionally', suspended.status === 200 && Number((await pool.query("SELECT count(*) FROM medorbit.notifications WHERE user_id=$1 AND reference_id=$2 AND notification_type='DOCTOR_SUSPENDED'",[existingDoctor.id,existingDoctor.doctorId])).rows[0].count) === 1, JSON.stringify(suspended.body));
        const suspendedUser=(await pool.query('SELECT authorization_version FROM medorbit.users WHERE id=$1',[existingDoctor.id])).rows[0];
        check('suspension advances version and revokes session', suspendedUser.authorization_version > 1 && (await pool.query('SELECT revoked_at FROM medorbit.user_sessions WHERE user_id=$1',[existingDoctor.id])).rows[0].revoked_at);
        check('old doctor token rejected', (await request('GET','/doctors/me/patients',doctorToken)).status === 401);
        const suspendedToken=access(existingDoctor,suspendedUser.authorization_version);
        check('suspended doctor blocked by central capability', (await request('GET','/doctors/me/patients',suspendedToken)).status === 403);
        check('suspended doctor cannot create prescription', (await request('POST','/prescriptions',suspendedToken,{})).status === 403);
        check('suspended doctor cannot manage availability', (await request('POST',`/doctors/${existingDoctor.doctorId}/availability`,suspendedToken,{specific_date:date,start_time:'11:00',end_time:'11:30'})).status === 403);
        check('suspended doctor hidden from public detail', (await request('GET',`/doctors/${existingDoctor.doctorId}`,null)).status === 404);
        const slotsSuspended=await request('GET',`/appointments/available-slots?doctor_id=${existingDoctor.doctorId}&clinic_id=${ids.clinic}&date=${date}`,null);
        check('suspended doctor has no public bookable slots', slotsSuspended.status === 200 && slotsSuspended.body.data.length === 0);
        const booking=await request('POST','/appointments',access(otherPatient),{doctor_id:existingDoctor.doctorId,clinic_id:ids.clinic,scheduled_date:date,start_time:'10:00',end_time:'10:30',duration_minutes:30,appointment_type:'in_person'}); if(booking.status===201)ids.bookingId=booking.body.data.id;
        check('suspended doctor cannot be booked', booking.status === 404 || booking.status === 409 || booking.status === 403, JSON.stringify(booking.body));
        check('suspension retains patient persona', Number((await pool.query('SELECT count(*) FROM medorbit.patients WHERE user_id=$1',[existingDoctor.id])).rows[0].count) === 1);
        const reactivated=await request('POST',`/admin/doctor-applications/doctors/${existingDoctor.doctorId}/reactivate`,access(superAdmin),{});
        check('super_admin reactivates and notifies doctor transactionally', reactivated.status === 200 && Number((await pool.query("SELECT count(*) FROM medorbit.notifications WHERE user_id=$1 AND reference_id=$2 AND notification_type='DOCTOR_REACTIVATED'",[existingDoctor.id,existingDoctor.doctorId])).rows[0].count) === 1);
        const reactivatedVersion=(await pool.query('SELECT authorization_version FROM medorbit.users WHERE id=$1',[existingDoctor.id])).rows[0].authorization_version;
        check('pre-reactivation token remains invalid', (await request('GET','/doctors/me/patients',suspendedToken)).status === 401);
        check('fresh doctor token restores capability', (await request('GET','/doctors/me/patients',access(existingDoctor,reactivatedVersion))).status === 200);
        check('reactivated doctor visible/bookable', (await request('GET',`/doctors/${existingDoctor.doctorId}`,null)).status === 200 && (await request('GET',`/appointments/available-slots?doctor_id=${existingDoctor.doctorId}&clinic_id=${ids.clinic}&date=${date}`,null)).body.data.length === 1);

        check('legacy-style doctor default is approved', (await pool.query('SELECT approval_status FROM medorbit.doctors WHERE id=$1',[unrelatedDoctor.doctorId])).rows[0].approval_status === 'approved');
        check('legacy role/profile retained and no fake application exists', (await pool.query('SELECT role FROM medorbit.users WHERE id=$1',[unrelatedDoctor.id])).rows[0].role === 'doctor' && Number((await pool.query('SELECT count(*) FROM medorbit.user_profiles WHERE user_id=$1',[unrelatedDoctor.id])).rows[0].count) === 1 && Number((await pool.query('SELECT count(*) FROM medorbit.doctor_applications WHERE user_id=$1',[unrelatedDoctor.id])).rows[0].count) === 0);
        check('legacy approved doctor remains public', (await request('GET',`/doctors/${unrelatedDoctor.doctorId}`,null)).status === 200);
    } catch (err) {
        failed++; console.error(err);
    } finally {
        await cleanup();
        const residual = await residualCounts().catch(err => ({ error: err.message }));
        console.log('S2 residual counts:', JSON.stringify(residual));
        check('S2 fixtures leave zero residual rows', !residual.error && Object.values(residual).every(v => v === 0), JSON.stringify(residual));
        await pool.end();
        console.log(`\nS2 focused lifecycle: ${passed} passed, ${failed} failed`);
        process.exitCode = failed ? 1 : 0;
    }
})();

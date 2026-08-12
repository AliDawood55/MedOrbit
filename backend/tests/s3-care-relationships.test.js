const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');
const { compareLegacyRelationship } = require('../src/services/careRelationship.service');

const pool = new Pool(poolConfig);
const run = Date.now();
const marker = `S3${String(run).slice(-7)}`;
const ids = {};
const users = [];
let appointmentSequence = 0;
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
}

function access(user, version = user.version || 1) {
    return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: version });
}

async function request(method, route, token, body) {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${route}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    const contentType = response.headers.get('content-type') || '';
    return {
        status: response.status,
        body: contentType.includes('application/json') ? await response.json() : null,
    };
}

async function createUser(key, role, withPatient = role === 'patient') {
    const user = { id: crypto.randomUUID(), email: `${marker}_${key}@medorbit.test`, role, version: 1 };
    users.push(user.id); ids[key] = user;
    await pool.query(
        `INSERT INTO medorbit.users
           (id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES ($1,$2,'s3-test-only',$3,true,true,1)`,
        [user.id, user.email, role]
    );
    await pool.query(
        `INSERT INTO medorbit.user_profiles
           (user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
         VALUES ($1,'اختبار','علاقة',$2,'S3')`,
        [user.id, key]
    );
    if (withPatient) {
        user.patientId = crypto.randomUUID();
        await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)', [user.patientId, user.id]);
    }
    return user;
}

async function createDoctor(key, withPatientPersona = true) {
    const user = await createUser(key, 'doctor', withPatientPersona);
    user.doctorId = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.doctors
           (id,user_id,medical_license_number,approval_status,approved_at,is_accepting_patients)
         VALUES ($1,$2,$3,'approved',NOW(),true)`,
        [user.doctorId, user.id, `${marker}-${key}-license`]
    );
    return user;
}

async function appointment(key, patientId, doctorId, status, createdOffset = '0 seconds') {
    const id = crypto.randomUUID(); ids[key] = id;
    const appointmentNumber = `${marker}-${String(++appointmentSequence).padStart(2, '0')}`;
    await pool.query(
        `INSERT INTO medorbit.appointments
           (id,appointment_number,patient_id,doctor_id,scheduled_date,start_time,end_time,
            duration_minutes,status,created_at)
         VALUES ($1,$2,$3,$4,CURRENT_DATE + 7,'10:00','10:30',30,$5,NOW()+$6::interval)`,
        [id, appointmentNumber, patientId, doctorId, status, createdOffset]
    );
    return id;
}

async function runBackfillPredicate() {
    await pool.query(
        `WITH ranked_evidence AS (
           SELECT a.doctor_id, a.patient_id, a.id appointment_id,
                  COALESCE(a.created_at,NOW()) evidence_at,
                  ROW_NUMBER() OVER (
                    PARTITION BY a.doctor_id,a.patient_id
                    ORDER BY COALESCE(a.created_at,NOW()),a.id
                  ) evidence_rank
           FROM medorbit.appointments a
           WHERE a.appointment_number LIKE $1
             AND a.status IN ('scheduled','confirmed','in_progress','completed')
         )
         INSERT INTO medorbit.doctor_patient_relationships
           (doctor_id,patient_id,status,source,source_reference_id,started_at)
         SELECT doctor_id,patient_id,'active','appointment',appointment_id,evidence_at
         FROM ranked_evidence e
         WHERE evidence_rank=1
           AND NOT EXISTS (
             SELECT 1 FROM medorbit.doctor_patient_relationships r
             WHERE r.doctor_id=e.doctor_id AND r.patient_id=e.patient_id AND r.status='active'
           )`,
        [`${marker}-%`]
    );
}

async function cleanup() {
    if (!users.length) return;
    await pool.query(`DELETE FROM medorbit.outbox_events WHERE event_type='care.relationship.created' AND aggregate_id IN
        (SELECT id FROM medorbit.doctor_patient_relationships WHERE doctor_id IN
        (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])) OR patient_id IN
        (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[])))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.prescription_items WHERE prescription_id IN
        (SELECT p.id FROM medorbit.prescriptions p JOIN medorbit.patients pt ON pt.id=p.patient_id WHERE pt.user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.prescriptions WHERE patient_id IN
        (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.medical_record_attachments WHERE record_id IN
        (SELECT mr.id FROM medorbit.medical_records mr JOIN medorbit.patients p ON p.id=mr.patient_id WHERE p.user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.medical_records WHERE patient_id IN
        (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[])
        OR entity_id IN (SELECT id FROM medorbit.doctor_patient_relationships WHERE created_by_user_id=ANY($1::uuid[]) OR ended_by_user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.doctor_patient_relationships WHERE doctor_id IN
        (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])) OR patient_id IN
        (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.appointment_status_history WHERE appointment_id IN
        (SELECT id FROM medorbit.appointments WHERE appointment_number LIKE $1)`, [`${marker}-%`]).catch(() => {});
    await pool.query('DELETE FROM medorbit.appointments WHERE appointment_number LIKE $1', [`${marker}-%`]).catch(() => {});
    await pool.query('DELETE FROM medorbit.doctor_availability WHERE doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_sessions WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [users]).catch(() => {});
}

async function residual() {
    return (await pool.query(
        `SELECT
          (SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[]))::int users,
          (SELECT count(*) FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))::int doctors,
          (SELECT count(*) FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))::int patients,
          (SELECT count(*) FROM medorbit.appointments WHERE appointment_number LIKE $2)::int appointments,
          (SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE created_by_user_id=ANY($1::uuid[]) OR ended_by_user_id=ANY($1::uuid[]))::int relationships,
          (SELECT count(*) FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[]))::int audit_logs`,
        [users, `${marker}-%`]
    )).rows[0];
}

(async () => {
    console.log('\nS3 centralized care authorization tests\n');
    try {
        const patient1 = await createUser('patient1', 'patient');
        const patient2 = await createUser('patient2', 'patient');
        const doctor1 = await createDoctor('doctor1');
        const doctor2 = await createDoctor('doctor2');
        const admin = await createUser('admin', 'admin', false);

        const first = await appointment('qualifying-first', patient1.patientId, doctor1.doctorId, 'scheduled', '-2 hours');
        await appointment('qualifying-second', patient1.patientId, doctor1.doctorId, 'completed', '-1 hour');
        await appointment('cancelled-only', patient2.patientId, doctor1.doctorId, 'cancelled');
        await appointment('no-show-only', patient2.patientId, doctor2.doctorId, 'no_show');
        await runBackfillPredicate();

        const ledger = await pool.query("SELECT 1 FROM medorbit.schema_migrations WHERE version='006'");
        check('migration 006 is recorded', ledger.rowCount === 1);
        const backfilled = await pool.query(
            `SELECT * FROM medorbit.doctor_patient_relationships
             WHERE doctor_id=$1 AND patient_id=$2 AND status='active'`,
            [doctor1.doctorId, patient1.patientId]
        );
        check('qualifying appointments backfill one active relationship', backfilled.rowCount === 1);
        check('earliest qualifying appointment is retained as evidence', backfilled.rows[0]?.source_reference_id === first);
        const excluded = await pool.query(
            `SELECT count(*)::int count FROM medorbit.doctor_patient_relationships
             WHERE patient_id=$1`, [patient2.patientId]
        );
        check('cancelled/no-show-only pairs are excluded', excluded.rows[0].count === 0);
        await runBackfillPredicate();
        check('backfill is idempotent', Number((await pool.query(
            'SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1 AND patient_id=$2 AND status=\'active\'',
            [doctor1.doctorId, patient1.patientId])).rows[0].count) === 1);
        const parity = await compareLegacyRelationship(doctor1.doctorId, patient1.patientId, pool);
        check('shadow comparison matches for qualifying history', parity.matches && parity.current);

        const duplicateClient = await pool.connect();
        let duplicateRejected = false;
        try {
            await duplicateClient.query('BEGIN');
            await duplicateClient.query(
                `INSERT INTO medorbit.doctor_patient_relationships
                   (doctor_id,patient_id,status,source) VALUES($1,$2,'active','appointment')`,
                [doctor1.doctorId, patient1.patientId]
            );
        } catch (err) {
            duplicateRejected = err.code === '23505';
        } finally {
            await duplicateClient.query('ROLLBACK').catch(() => {});
            duplicateClient.release();
        }
        check('partial unique index rejects duplicate active relationship', duplicateRejected);

        const recordOwn = crypto.randomUUID();
        const recordOther = crypto.randomUUID();
        await pool.query(
            `INSERT INTO medorbit.medical_records
               (id,record_number,patient_id,doctor_id,appointment_id,diagnosis,is_draft,visible_to_patient)
             VALUES($1,$2,$3,$4,$5,'authored',false,true),
                   ($6,$7,$3,$8,$5,'other author',false,true)`,
            [recordOwn, `${marker}-mr-own`, patient1.patientId, doctor1.doctorId, first,
                recordOther, `${marker}-mr-other`, doctor2.doctorId]
        );
        check('active related doctor reads patient record', (await request('GET', `/medical-records/${recordOther}`, access(doctor1))).status === 200);
        check('unrelated doctor cannot read patient record', (await request('GET', `/medical-records/${recordOwn}`, access(doctor2))).status === 404);
        check('patient remains limited to own records', (await request('GET', `/medical-records/${recordOwn}`, access(patient2))).status === 404);

        const createdRecord = await request('POST', '/medical-records', access(doctor1), {
            appointment_id: first, record_type: 'consultation', diagnosis: 'S3 active relationship',
        });
        check('active relationship plus assigned appointment permits record creation', createdRecord.status === 201, JSON.stringify(createdRecord.body));
        const rx = await request('POST', '/prescriptions', access(doctor1), {
            patient_id: patient1.patientId,
            appointment_id: first,
            items: [{ medication_name_ar: 'دواء', medication_name_en: 'Medicine', dosage: '1', frequency: 'daily', quantity: 1 }],
        });
        check('active relationship plus assigned appointment permits prescription', rx.status === 201, JSON.stringify(rx.body));

        const doctorList = await request('GET', '/doctors/me/patients', access(doctor1));
        check('doctor patient list is relationship-backed', doctorList.status === 200 && doctorList.body.data.some((p) => p.id === patient1.patientId) && !doctorList.body.data.some((p) => p.id === patient2.patientId));
        const patientList = await request('GET', '/patients/me/doctors', access(patient1));
        check('patient treating-doctor list shows active relationships only', patientList.status === 200 && patientList.body.data.some((d) => d.id === doctor1.doctorId));
        check('doctor cannot use another doctor relationship', (await request('POST', `/doctors/me/patients/${patient1.patientId}/relationship/end`, access(doctor2), { reason: 'probe' })).status === 404);

        const ended = await request('POST', `/doctors/me/patients/${patient1.patientId}/relationship/end`, access(doctor1), { reason: 'care completed' });
        check('doctor can end own active relationship without hard delete', ended.status === 200 && ended.body.data.status === 'ended');
        check('ended relationship removes broad record access', (await request('GET', `/medical-records/${recordOther}`, access(doctor1))).status === 404);
        check('record authorship preserves narrow historical read', (await request('GET', `/medical-records/${recordOwn}`, access(doctor1))).status === 200);
        check('ended relationship cannot create a prescription', (await request('POST', '/prescriptions', access(doctor1), {
            patient_id: patient1.patientId, appointment_id: first,
            items: [{ medication_name_en: 'Blocked', dosage: '1', frequency: 'daily', quantity: 1 }],
        })).status === 404);
        check('ended patient disappears from doctor list', !(await request('GET', '/doctors/me/patients', access(doctor1))).body.data.some((p) => p.id === patient1.patientId));

        const reconfirmed = await request('PUT', `/appointments/${first}/confirm`, access(doctor1), {});
        check('qualifying appointment transition ensures a new active relationship', reconfirmed.status === 200 && Number((await pool.query(
            "SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1 AND patient_id=$2 AND status='active'",
            [doctor1.doctorId, patient1.patientId])).rows[0].count) === 1);
        await request('PUT', `/appointments/${first}/confirm`, access(doctor1), {});
        check('duplicate qualifying transition does not duplicate relationship', Number((await pool.query(
            "SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1 AND patient_id=$2 AND status='active'",
            [doctor1.doctorId, patient1.patientId])).rows[0].count) === 1);

        const activeId = (await pool.query(
            "SELECT id FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1 AND patient_id=$2 AND status='active'",
            [doctor1.doctorId, patient1.patientId])).rows[0].id;
        check('admin may inspect relationship metadata', (await request('GET', '/admin/care-relationships?status=active', access(admin))).status === 200);
        check('patient cannot revoke by possessing relationship UUID', (await request('POST', `/admin/care-relationships/${activeId}/revoke`, access(patient1), { reason: 'probe' })).status === 403);
        check('admin relationship inspection does not grant clinical read', (await request('GET', `/medical-records/${recordOwn}`, access(admin))).status === 404);
        const revoked = await request('POST', `/admin/care-relationships/${activeId}/revoke`, access(admin), { reason: 'support revocation' });
        check('admin revocation records lifecycle state', revoked.status === 200 && revoked.body.data.status === 'revoked');
        check('revoked relationship removes broad patient access', (await request('GET', `/doctors/me/patients/${patient1.patientId}`, access(doctor1))).status === 404);
        const events = await pool.query(
            `SELECT action,new_values FROM medorbit.audit_logs
             WHERE user_id=ANY($1::uuid[]) AND action LIKE 'CARE_RELATIONSHIP_%'`, [users]
        );
        check('relationship create/end/revoke events are audited', ['CARE_RELATIONSHIP_CREATED','CARE_RELATIONSHIP_ENDED','CARE_RELATIONSHIP_REVOKED'].every((action) => events.rows.some((row) => row.action === action)));
        check('relationship audits contain no clinical payload', events.rows.every((row) => !JSON.stringify(row).includes('diagnosis')));

        const lifecycle = await appointment('lifecycle-confirm', patient2.patientId, doctor2.doctorId, 'scheduled');
        check('scheduled appointment alone does not create a new relationship', !(await compareLegacyRelationship(doctor2.doctorId, patient2.patientId, pool)).current);
        check('doctor confirmation activates relationship', (await request('PUT', `/appointments/${lifecycle}/confirm`, access(doctor2), {})).status === 200 && (await compareLegacyRelationship(doctor2.doctorId, patient2.patientId, pool)).current);
        const cancelled = await appointment('cancel-before-confirm', patient2.patientId, doctor1.doctorId, 'scheduled');
        await request('PUT', `/appointments/${cancelled}/cancel`, access(patient2), { reason: 'cancelled before acceptance' });
        check('cancel before qualification creates no relationship', Number((await pool.query(
            "SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1 AND patient_id=$2 AND status='active'",
            [doctor1.doctorId, patient2.patientId])).rows[0].count) === 0);

        await pool.query(
            `INSERT INTO medorbit.user_sessions(user_id,refresh_token_hash,expires_at)
             VALUES($1,$2,NOW()+interval '1 day')`, [doctor2.id, crypto.createHash('sha256').update(`${marker}-session`).digest('hex')]
        );
        const suspended = await request('POST', `/admin/doctor-applications/doctors/${doctor2.doctorId}/suspend`, access(admin), { reason: 'S3 precedence test' });
        check('doctor suspension preserves relationship history', suspended.status === 200 && Number((await pool.query(
            'SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1', [doctor2.doctorId])).rows[0].count) > 0);
        const doctor2State = (await pool.query('SELECT authorization_version FROM medorbit.users WHERE id=$1', [doctor2.id])).rows[0];
        check('suspension invalidates old token', (await request('GET', '/doctors/me/patients', access(doctor2))).status === 401);
        check('suspended doctor cannot exercise relationship capability', (await request('GET', '/doctors/me/patients', access(doctor2, doctor2State.authorization_version))).status === 403);
        check('suspension retains patient persona', Number((await pool.query('SELECT count(*) FROM medorbit.patients WHERE user_id=$1', [doctor2.id])).rows[0].count) === 1);

        const counts = await pool.query(
            `SELECT
              (SELECT count(*) FROM medorbit.medical_records WHERE patient_id=ANY($1::uuid[]))::int records,
              (SELECT count(*) FROM medorbit.prescriptions WHERE patient_id=ANY($1::uuid[]))::int prescriptions`,
            [[patient1.patientId, patient2.patientId]]
        );
        check('relationship lifecycle does not delete clinical rows', counts.rows[0].records >= 2 && counts.rows[0].prescriptions >= 1);
    } catch (err) {
        failed++;
        console.error('  ✗ suite error:', err.stack || err.message);
    } finally {
        await cleanup();
        const counts = await residual();
        console.log(`S3 residual counts: ${JSON.stringify(counts)}`);
        check('S3 fixtures leave zero residual rows', Object.values(counts).every((value) => Number(value) === 0));
        await pool.end();
    }
    console.log(`\nS3 care authorization: ${passed} passed, ${failed} failed`);
    if (failed) process.exitCode = 1;
})();

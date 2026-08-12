const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const run = Date.now();
const shortRun = String(run).slice(-6);
const ids = Object.fromEntries([
    'u1', 'u2', 'u3', 'u4', 'p1', 'p2', 'd1', 'd2', 'd3',
    'a1', 'a2', 'a3', 'aConfirm', 'aComplete', 'aCancel', 'aReview',
    'r1', 'r2', 'rx1', 'rx2', 'slot1', 'review1',
].map((key) => [key, crypto.randomUUID()]));

let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed++;
        console.log(`  ✓ ${name}`);
    } else {
        failed++;
        console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

async function request(method, route, token, body, extraHeaders = {}) {
    const headers = { ...extraHeaders };
    if (token) headers.Authorization = `Bearer ${token}`;
    let payload;
    if (body instanceof FormData) {
        payload = body;
    } else if (body !== undefined) {
        headers['Content-Type'] = 'application/json';
        payload = JSON.stringify(body);
    }
    const response = await fetch(`${apiBase}${route}`, { method, headers, body: payload });
    const contentType = response.headers.get('content-type') || '';
    const parsed = contentType.includes('application/json')
        ? await response.json()
        : await response.arrayBuffer();
    return { status: response.status, body: parsed, contentType };
}

function token(userId, role) {
    return generateAccessToken({ sub: userId, role, authorizationVersion: 1 });
}

async function seed() {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        for (const [key, role] of [['u1', 'patient'], ['u2', 'patient'], ['u3', 'doctor'], ['u4', 'doctor']]) {
            await client.query(
                `INSERT INTO medorbit.users
                   (id,email,password_hash,role,is_active,email_verified,authorization_version)
                 VALUES ($1,$2,'test-only',$3,true,true,1)`,
                [ids[key], `s1b_${key}_${run}@medorbit.test`, role]
            );
            await client.query(
                `INSERT INTO medorbit.user_profiles
                   (user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
                 VALUES ($1,'اختبار','سريري',$2,'Clinical')`,
                [ids[key], key]
            );
        }
        await client.query('INSERT INTO medorbit.patients (id,user_id) VALUES ($1,$2),($3,$4)', [ids.p1, ids.u1, ids.p2, ids.u2]);
        await client.query('INSERT INTO medorbit.doctors (id,user_id) VALUES ($1,$2),($3,$4)', [ids.d1, ids.u3, ids.d2, ids.u4]);

        // A third doctor uses an existing verified test user created solely in this suite.
        const u5 = crypto.randomUUID();
        ids.u5 = u5;
        await client.query(
            `INSERT INTO medorbit.users (id,email,password_hash,role,is_active,email_verified,authorization_version)
             VALUES ($1,$2,'test-only','doctor',true,true,1)`,
            [u5, `s1b_u5_${run}@medorbit.test`]
        );
        await client.query(
            `INSERT INTO medorbit.user_profiles (user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
             VALUES ($1,'اختبار','طبيب','Related','Doctor')`, [u5]
        );
        await client.query('INSERT INTO medorbit.doctors (id,user_id) VALUES ($1,$2)', [ids.d3, u5]);

        const appointmentRows = [
            [ids.a1, ids.p1, ids.d1, 'scheduled'],
            [ids.a2, ids.p2, ids.d2, 'scheduled'],
            [ids.a3, ids.p1, ids.d3, 'scheduled'],
            [ids.aConfirm, ids.p1, ids.d1, 'scheduled'],
            [ids.aComplete, ids.p1, ids.d1, 'confirmed'],
            [ids.aCancel, ids.p1, ids.d1, 'scheduled'],
            [ids.aReview, ids.p1, ids.d1, 'completed'],
        ];
        for (const [id, patientId, doctorId, status] of appointmentRows) {
            await client.query(
                `INSERT INTO medorbit.appointments
                   (id,appointment_number,patient_id,doctor_id,scheduled_date,start_time,end_time,duration_minutes,status)
                 VALUES ($1,$2,$3,$4,CURRENT_DATE + 7,'10:00','10:30',30,$5)`,
                [id, `S1B-${id.slice(0, 8)}`, patientId, doctorId, status]
            );
        }
        await client.query(
            `INSERT INTO medorbit.doctor_patient_relationships
               (doctor_id,patient_id,status,source,source_reference_id,started_at)
             VALUES ($1,$2,'active','appointment',$3,NOW()),
                    ($4,$5,'active','appointment',$6,NOW()),
                    ($7,$8,'active','appointment',$9,NOW())`,
            [ids.d1, ids.p1, ids.a1, ids.d2, ids.p2, ids.a2, ids.d3, ids.p1, ids.a3]
        );
        await client.query(
            `INSERT INTO medorbit.medical_records
               (id,record_number,patient_id,doctor_id,appointment_id,record_type,diagnosis,doctor_notes,is_draft,visible_to_patient)
             VALUES ($1,$2,$3,$4,$5,'consultation','own diagnosis','private note',false,true),
                    ($6,$7,$8,$9,$10,'consultation','other diagnosis','other private note',false,true)`,
            [ids.r1, `S1B1-${shortRun}`, ids.p1, ids.d1, ids.a1,
                ids.r2, `S1B2-${shortRun}`, ids.p2, ids.d2, ids.a2]
        );
        await client.query(
            `INSERT INTO medorbit.prescriptions
               (id,prescription_number,patient_id,doctor_id,appointment_id,prescription_date,status,diagnosis)
             VALUES ($1,$2,$3,$4,$5,CURRENT_DATE,'active','own rx'),
                    ($6,$7,$8,$9,$10,CURRENT_DATE,'active','other rx')`,
            [ids.rx1, `S1BR1-${shortRun}`, ids.p1, ids.d1, ids.a1,
                ids.rx2, `S1BR2-${shortRun}`, ids.p2, ids.d2, ids.a2]
        );
        await client.query(
            `INSERT INTO medorbit.prescription_items
               (prescription_id,medication_name_ar,medication_name_en,dosage,frequency,quantity)
             VALUES ($1,'دواء','Medicine','10mg','daily',1),($2,'دواء','Medicine','10mg','daily',1)`,
            [ids.rx1, ids.rx2]
        );
        await client.query(
            `INSERT INTO medorbit.doctor_availability
               (id,doctor_id,day_of_week,start_time,end_time,slot_duration,is_active)
             VALUES ($1,$2,1,'09:00','10:00',30,true)`,
            [ids.slot1, ids.d1]
        );
        await client.query(
            `INSERT INTO medorbit.doctor_reviews
               (id,appointment_id,patient_id,doctor_id,rating,review_text_en,professionalism_rating,treatment_rating,communication_rating,is_visible)
             VALUES ($1,$2,$3,$4,5,'Excellent',5,5,5,true)`,
            [ids.review1, ids.aReview, ids.p1, ids.d1]
        );
        await client.query('COMMIT');
    } catch (err) {
        await client.query('ROLLBACK');
        throw err;
    } finally {
        client.release();
    }
}

async function cleanup() {
    const allUsers = [ids.u1, ids.u2, ids.u3, ids.u4, ids.u5].filter(Boolean);
    const client = await pool.connect();
    let attachmentPaths = [];
    try {
        await client.query('BEGIN');
        await client.query('DELETE FROM medorbit.report_summarizations WHERE user_id=ANY($1::uuid[])', [allUsers]);
        await client.query('DELETE FROM medorbit.symptom_triage_sessions WHERE user_id=ANY($1::uuid[]) OR session_id LIKE $2', [allUsers, `s1b-${run}%`]);
        const attachments = await client.query(
            'SELECT file_path FROM medorbit.medical_record_attachments WHERE uploaded_by=ANY($1::uuid[])',
            [allUsers]
        );
        attachmentPaths = attachments.rows.map((row) => row.file_path);
        await client.query('DELETE FROM medorbit.medical_record_attachments WHERE uploaded_by=ANY($1::uuid[])', [allUsers]);
        await client.query('DELETE FROM medorbit.prescription_items WHERE prescription_id IN (SELECT id FROM medorbit.prescriptions WHERE patient_id=ANY($1::uuid[]))', [[ids.p1, ids.p2]]);
        await client.query('DELETE FROM medorbit.prescriptions WHERE patient_id=ANY($1::uuid[])', [[ids.p1, ids.p2]]);
        await client.query('DELETE FROM medorbit.medical_records WHERE patient_id=ANY($1::uuid[])', [[ids.p1, ids.p2]]);
        await client.query('DELETE FROM medorbit.doctor_reviews WHERE id=$1', [ids.review1]);
        await client.query('DELETE FROM medorbit.doctor_availability WHERE doctor_id=ANY($1::uuid[])', [[ids.d1, ids.d2, ids.d3]]);
        await client.query('DELETE FROM medorbit.doctor_patient_relationships WHERE doctor_id=ANY($1::uuid[])', [[ids.d1, ids.d2, ids.d3]]);
        await client.query("DELETE FROM medorbit.appointment_status_history WHERE appointment_id IN (SELECT id FROM medorbit.appointments WHERE appointment_number LIKE 'S1B-%')");
        await client.query("DELETE FROM medorbit.appointments WHERE appointment_number LIKE 'S1B-%'");
        await client.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])', [allUsers]);
        await client.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [allUsers]);
        await client.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [allUsers]);
        await client.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [allUsers]);
        await client.query('COMMIT');
        for (const filePath of attachmentPaths) {
            await fs.promises.unlink(path.resolve(process.cwd(), filePath)).catch(() => {});
        }
    } catch (err) {
        await client.query('ROLLBACK');
        console.error('Cleanup failed:', err.message);
    } finally {
        client.release();
    }
}

async function main() {
    console.log('\nS1B clinical authorization adversarial tests\n');
    await seed();
    const patient1 = token(ids.u1, 'patient');
    const patient2 = token(ids.u2, 'patient');
    const doctor1 = token(ids.u3, 'doctor');
    const doctor2 = token(ids.u4, 'doctor');
    const doctor3 = token(ids.u5, 'doctor');
    let response;

    try {
        response = await request('GET', `/medical-records/${ids.r1}`, patient1);
        check('patient can read own record', response.status === 200);
        check('patient DTO excludes doctor notes', !('doctor_notes' in (response.body.data || {})));
        response = await request('GET', `/medical-records/${ids.r2}`, patient1);
        check('patient cannot read another patient record', response.status === 404);
        response = await request('GET', '/medical-records', patient1);
        check('patient generic list is own-only', response.status === 200 && response.body.data.every((row) => row.id !== ids.r2));
        response = await request('GET', `/medical-records/${ids.r1}`, doctor3);
        check('appointment-related doctor can read patient record', response.status === 200);
        response = await request('GET', `/medical-records/${ids.r1}`, doctor2);
        check('unrelated doctor cannot read patient record', response.status === 404);
        response = await request('PUT', `/medical-records/${ids.r1}`, doctor2, { diagnosis: 'tampered' });
        check('unrelated doctor cannot update record', response.status === 404);
        response = await request('DELETE', `/medical-records/${ids.r1}`, doctor2);
        check('unrelated doctor cannot delete record', response.status === 404);
        response = await request('POST', '/medical-records', doctor1, { appointment_id: ids.a1, record_type: 'consultation', diagnosis: 'valid' });
        check('assigned doctor can create record', response.status === 201);
        response = await request('POST', '/medical-records', doctor2, { appointment_id: ids.a1, record_type: 'consultation' });
        check('unassigned doctor cannot create from another appointment', response.status === 404);

        const form = new FormData();
        form.append('file', new Blob(['%PDF-safe-test-attachment'], { type: 'application/pdf' }), 'test.pdf');
        response = await request('POST', `/medical-records/${ids.r1}/attachments`, doctor1, form);
        check('attachment upload enforces author ownership before storage', response.status === 201, `got ${response.status}`);
        const attachmentId = response.body.data?.id;
        const forbiddenForm = new FormData();
        forbiddenForm.append('file', new Blob(['%PDF-test'], { type: 'application/pdf' }), 'test.pdf');
        response = await request('POST', `/medical-records/${ids.r1}/attachments`, doctor2, forbiddenForm);
        check('unrelated doctor cannot upload attachment', response.status === 404);
        response = await request('GET', `/medical-records/${ids.r1}/attachments`, patient1);
        check('attachment list inherits patient record authorization', response.status === 200);
        response = await request('GET', `/medical-records/${ids.r1}/attachments`, patient2);
        check('cross-patient attachment list is rejected', response.status === 404);
        response = await request('GET', `/medical-records/${ids.r1}/attachments/${attachmentId}/download`, patient1);
        check('attachment download inherits patient record authorization', response.status === 200 && response.contentType.includes('application/pdf'));
        response = await request('GET', `/medical-records/${ids.r1}/attachments/${attachmentId}/download`, patient2);
        check('cross-patient attachment download is rejected', response.status === 404);

        response = await request('GET', `/prescriptions/${ids.rx1}`, patient1);
        check('patient can read own prescription', response.status === 200);
        response = await request('GET', `/prescriptions/${ids.rx2}`, patient1);
        check('patient cannot read another prescription', response.status === 404);
        response = await request('GET', `/prescriptions/${ids.rx2}/pdf`, patient1);
        check('prescription PDF applies identical ownership', response.status === 404);
        response = await request('GET', `/prescriptions/${ids.rx1}`, doctor3);
        check('related doctor can read authorized prescription', response.status === 200);
        response = await request('GET', `/prescriptions/${ids.rx1}`, doctor2);
        check('unrelated doctor cannot read prescription', response.status === 404);
        response = await request('POST', '/prescriptions', doctor2, {
            patient_id: ids.p1, appointment_id: ids.a1,
            items: [{ medication_name_ar: 'دواء', medication_name_en: 'Medicine', dosage: '1', frequency: 'daily', quantity: 1 }],
        });
        check('doctor cannot prescribe from another doctor appointment', response.status === 404);

        response = await request('PUT', `/appointments/${ids.aConfirm}/confirm`, doctor2, {});
        check('unrelated doctor cannot confirm appointment', response.status === 404);
        response = await request('PUT', `/appointments/${ids.aConfirm}/confirm`, doctor1, {});
        check('assigned doctor can confirm appointment', response.status === 200);
        response = await request('PUT', `/appointments/${ids.aComplete}/complete`, doctor2, {});
        check('unrelated doctor cannot complete appointment', response.status === 404);
        response = await request('PUT', `/appointments/${ids.aComplete}/complete`, doctor1, {});
        check('assigned doctor can complete appointment', response.status === 200);
        response = await request('PUT', `/appointments/${ids.aCancel}/cancel`, patient1, { reason: 'test' });
        check('patient cancellation ownership remains intact', response.status === 200);

        response = await request('PUT', `/doctors/${ids.d1}/availability/${ids.slot1}`, doctor1, { end_time: '10:30' });
        check('doctor can manage own availability', response.status === 200);
        response = await request('PUT', `/doctors/${ids.d1}/availability/${ids.slot1}`, doctor2, { end_time: '11:00' });
        check('doctor cannot mutate another availability', response.status === 404);

        response = await request('GET', `/doctors/${ids.d1}/reviews`);
        const review = response.body.data?.find((row) => row.id === ids.review1) || {};
        check('public review omits patient UUID', response.status === 200 && !('patient_id' in review));
        check('public review omits appointment UUID', !('appointment_id' in review));
        check('public review rating fields remain correct', review.rating === 5 && review.professionalism_rating === 5);

        const aiDirect = 'http://ai-service-test:8001';
        let direct = await fetch(`${aiDirect}/triage`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ symptoms: ['headache'], user_id: ids.u2 }),
        });
        check('direct client cannot persist authenticated-user AI data', direct.status === 403);
        response = await request('POST', '/ai/triage', patient1, { symptoms: ['headache'], user_id: ids.u2, session_id: `s1b-${run}-auth` });
        const persisted = await pool.query(
            'SELECT user_id FROM medorbit.symptom_triage_sessions WHERE id=$1',
            [response.body.id]
        );
        check('caller cannot persist AI data for another user', response.status === 200 && persisted.rows[0]?.user_id === ids.u1);
        response = await request('POST', '/ai/summarize', patient1, { text: 'A sufficiently long clinical report body.', record_id: ids.r2 });
        check('caller cannot summarize inaccessible record', response.status === 404);
        check('authorized caller can use persisted AI flow', persisted.rows[0]?.user_id === ids.u1);
        direct = await fetch(`${aiDirect}/drug-interactions`, {
            method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ medication_names: [] }),
        });
        check('anonymous stateless AI flow remains available', direct.status === 200);
        response = await request('POST', '/ai/triage', null, { symptoms: ['headache'], user_id: ids.u2, session_id: `s1b-${run}-anon` }, {
            'X-MedOrbit-Internal-Token': 'browser-spoof', 'X-MedOrbit-User-Id': ids.u2,
        });
        const anonymousPersisted = await pool.query(
            'SELECT user_id FROM medorbit.symptom_triage_sessions WHERE id=$1', [response.body.id]
        );
        check('browser cannot spoof internal AI identity context', response.status === 200 && anonymousPersisted.rows[0]?.user_id === null);

        response = await request('GET', `/patients/me/medical-records/${ids.r1}`, patient1);
        check('/patients/me medical-record behavior remains green', response.status === 200);
        response = await request('GET', `/doctors/me/patients/${ids.p1}`, doctor1);
        check('/doctors/me/patients behavior remains green', response.status === 200);
        check('test isolation targets medorbit_test', poolConfig.database === 'medorbit_test' && poolConfig.host === 'postgres');
    } finally {
        await cleanup();
        await pool.end();
    }

    console.log(`\nS1B result: ${passed} passed, ${failed} failed\n`);
    if (failed) process.exitCode = 1;
}

main().catch(async (err) => {
    console.error(err);
    await cleanup().catch(() => {});
    await pool.end().catch(() => {});
    process.exitCode = 1;
});

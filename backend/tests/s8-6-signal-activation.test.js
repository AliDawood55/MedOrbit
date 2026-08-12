const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');
const { buildEnvelope } = require('../src/events/eventEnvelope');
const { validateSafeSourceEvent, ALLOWED_SIGNALS } = require('../src/services/recommendationPolicy.service');
const { processRecommendationEnvelope } = require('../src/services/recommendationProjection.service');
const { inspectProductionCoverage, collectSignalCoverage } = require('../scripts/signal-coverage-report');

const pool = new Pool(poolConfig);
const EXPECTED_SIGNALS = Object.freeze([
    'post_view', 'post_like', 'post_unlike', 'post_comment',
    'doctor_profile_view', 'doctor_follow', 'doctor_unfollow', 'search_specialty',
]);
const run = String(Date.now()).slice(-9);
const marker = `s86_${run}`;
const users = [], doctors = [], posts = [], specialties = [];
let triggerName = null, functionName = null, passed = 0, failed = 0;

function check(name, condition, detail = '') {
    if (condition) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
}
function token(user) { return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: 1 }); }
async function request(method, path, auth, body) {
    const headers = auth ? { Authorization: `Bearer ${auth}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
    let data = null; try { data = await response.json(); } catch {}
    return { status: response.status, body: data };
}
async function createSpecialty() {
    const id = crypto.randomUUID(); specialties.push(id);
    await pool.query(`INSERT INTO medorbit.specialties(id,name_ar,name_en,is_active) VALUES($1,'تخصص إشارة',$2,true)`, [id, `Signal ${run}`]);
    return id;
}
async function createUser(key, role = 'patient', patientPersona = true) {
    const user = { id: crypto.randomUUID(), role, email: `${marker}_${key}@medorbit.test` }; users.push(user.id);
    await pool.query(`INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version)
                      VALUES($1,$2,'s86-test',$3,true,true,1)`, [user.id, user.email, role]);
    await pool.query(`INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
                      VALUES($1,'إشارة','اختبار',$2,'Signal')`, [user.id, key]);
    if (patientPersona) {
        user.patientId = crypto.randomUUID();
        await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)', [user.patientId, user.id]);
    }
    return user;
}
async function createDoctor(key, specialtyId) {
    const user = await createUser(key, 'doctor', true); user.doctorId = crypto.randomUUID(); doctors.push(user.doctorId);
    await pool.query(`INSERT INTO medorbit.doctors(id,user_id,medical_license_number,specialty_id,approval_status,approved_at)
                      VALUES($1,$2,$3,$4,'approved',NOW())`, [user.doctorId, user.id, `S86-${run}-${key}`, specialtyId]);
    return user;
}
async function createPost(doctorId, moderationStatus = 'approved') {
    const id = crypto.randomUUID(); posts.push(id);
    await pool.query(`INSERT INTO medorbit.doctor_posts
        (id,doctor_id,title_en,body,category,is_published,status,moderation_status,published_at)
        VALUES($1,$2,'Signal activation','Safe public content','health_tip',true,'published',$3,NOW())`,
    [id, doctorId, moderationStatus]);
    return id;
}
async function eventsFor(userId) {
    return (await pool.query(`SELECT id,event_type,entity_type,entity_id,metadata FROM medorbit.user_events
                             WHERE user_id=$1 ORDER BY occurred_at,id`, [userId])).rows;
}
async function outboxFor(userId) {
    return (await pool.query(`SELECT o.* FROM medorbit.outbox_events o JOIN medorbit.user_events e ON e.id=o.aggregate_id
                             WHERE o.aggregate_type='user_event' AND e.user_id=$1 ORDER BY o.created_at,o.id`, [userId])).rows;
}
async function installOutboxFailure(userId) {
    functionName = `${marker}_fail_outbox`; triggerName = `${marker}_fail_outbox_trigger`;
    await pool.query(`CREATE FUNCTION medorbit.${functionName}() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN IF NEW.payload->>'userId'='${userId}' THEN RAISE EXCEPTION 'S8.6 controlled outbox failure'; END IF; RETURN NEW; END $$`);
    await pool.query(`CREATE TRIGGER ${triggerName} BEFORE INSERT ON medorbit.outbox_events
                      FOR EACH ROW EXECUTE FUNCTION medorbit.${functionName}()`);
}
async function dropOutboxFailure() {
    if (triggerName) await pool.query(`DROP TRIGGER IF EXISTS ${triggerName} ON medorbit.outbox_events`).catch(() => {});
    if (functionName) await pool.query(`DROP FUNCTION IF EXISTS medorbit.${functionName}()`).catch(() => {});
    triggerName = null; functionName = null;
}
async function cleanup() {
    await dropOutboxFailure();
    await pool.query(`DELETE FROM medorbit.processed_events WHERE event_id IN
        (SELECT o.id FROM medorbit.outbox_events o JOIN medorbit.user_events e ON e.id=o.aggregate_id WHERE e.user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query(`DELETE FROM medorbit.outbox_events WHERE aggregate_type='user_event' AND aggregate_id IN
        (SELECT id FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))`, [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_interest_profiles WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.post_comments WHERE user_id=ANY($1::uuid[]) OR post_id=ANY($2::uuid[])', [users, posts]).catch(() => {});
    await pool.query('DELETE FROM medorbit.post_likes WHERE user_id=ANY($1::uuid[]) OR post_id=ANY($2::uuid[])', [users, posts]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_follows WHERE user_id=ANY($1::uuid[]) OR doctor_id=ANY($2::uuid[])', [users, doctors]).catch(() => {});
    await pool.query('DELETE FROM medorbit.doctor_patient_relationships WHERE doctor_id=ANY($1::uuid[])', [doctors]).catch(() => {});
    await pool.query('DELETE FROM medorbit.doctor_posts WHERE id=ANY($1::uuid[])', [posts]).catch(() => {});
    await pool.query('DELETE FROM medorbit.doctors WHERE id=ANY($1::uuid[])', [doctors]).catch(() => {});
    await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.specialties WHERE id=ANY($1::uuid[])', [specialties]).catch(() => {});
}

(async () => {
    console.log('\nS8.6 real signal activation tests\n');
    try {
        const identity = (await pool.query('SELECT current_database() database')).rows[0];
        check('test isolation targets Docker medorbit_test', identity.database.endsWith('_test') && poolConfig.host === 'postgres' && process.env.MEDORBIT_TEST_ISOLATION === 'docker');

        const specialtyId = await createSpecialty();
        const patient = await createUser('patient');
        const other = await createUser('other');
        const rollbackUser = await createUser('rollback');
        const doctor = await createDoctor('doctor', specialtyId);
        const publishedPost = await createPost(doctor.doctorId);
        const hiddenPost = await createPost(doctor.doctorId, 'hidden');
        const auth = token(patient);
        const unsafeSearch = 'my chest hurts which heart doctor do I need';
        const commentBody = `private-comment-${run}`;

        const coverage = inspectProductionCoverage();
        check('all eight canonical signals have production emitters and frontend triggers', coverage.length === 8 && coverage.every(row => row.productionEmitterPresent && row.frontendTriggerPresent && row.backendRoutePresent && row.outboxEmitted && row.testCoveragePresent), JSON.stringify(coverage));
        check('canonical allowlist remains exactly eight signals', Object.keys(ALLOWED_SIGNALS).sort().join(',') === EXPECTED_SIGNALS.slice().sort().join(',') && EXPECTED_SIGNALS.slice().sort().join(',') === coverage.map(row => row.signal).sort().join(','));

        const like = await request('POST', `/feed/posts/${publishedPost}/like`, auth, { user_id: other.id, email: other.email });
        const duplicateLike = await request('POST', `/feed/posts/${publishedPost}/like`, auth, {});
        const unlike = await request('DELETE', `/feed/posts/${publishedPost}/like`, auth);
        const duplicateUnlike = await request('DELETE', `/feed/posts/${publishedPost}/like`, auth);
        check('like and unlike transitions are retry-safe', like.status === 200 && like.body.data.created && !duplicateLike.body.data.created && unlike.body.data.removed && !duplicateUnlike.body.data.removed);

        const comment = await request('POST', `/feed/posts/${publishedPost}/comments`, auth, { body: commentBody, user_id: other.id });
        const view = await request('POST', `/feed/posts/${publishedPost}/view`, auth, { user_id: other.id });
        const duplicateView = await request('POST', `/feed/posts/${publishedPost}/view`, auth, {});
        check('comment and bounded daily post view succeed', comment.status === 201 && view.body.data.recorded && !duplicateView.body.data.recorded);

        const follow = await request('POST', `/doctors/${doctor.doctorId}/follow`, auth, { user_id: other.id });
        const duplicateFollow = await request('POST', `/doctors/${doctor.doctorId}/follow`, auth, {});
        const unfollow = await request('DELETE', `/doctors/${doctor.doctorId}/follow`, auth);
        const duplicateUnfollow = await request('DELETE', `/doctors/${doctor.doctorId}/follow`, auth);
        const doctorView = await request('POST', `/doctors/${doctor.doctorId}/view`, auth, {});
        const duplicateDoctorView = await request('POST', `/doctors/${doctor.doctorId}/view`, auth, {});
        check('follow/unfollow and doctor view transitions are bounded', follow.body.data.created && !duplicateFollow.body.data.created && unfollow.body.data.removed && !duplicateUnfollow.body.data.removed && doctorView.body.data.recorded && !duplicateDoctorView.body.data.recorded);

        const search = await request('POST', `/recommendations/specialties/${specialtyId}/search`, auth, { user_id: other.id, query: unsafeSearch });
        const duplicateSearch = await request('POST', `/recommendations/specialties/${specialtyId}/search`, auth, { query: unsafeSearch });
        check('normalized specialty search is daily-idempotent', search.status === 200 && search.body.data.recorded && !duplicateSearch.body.data.recorded);

        const events = await eventsFor(patient.id);
        const eventTypes = events.map(row => row.event_type).sort();
        check('all eight real routes emit exactly one canonical signal', eventTypes.join(',') === EXPECTED_SIGNALS.slice().sort().join(','), eventTypes.join(','));
        check('authenticated server identity overrides client identity', events.length === 8 && !(await eventsFor(other.id)).length);
        const searchEvent = events.find(row => row.event_type === 'search_specialty');
        const commentEvent = events.find(row => row.event_type === 'post_comment');
        check('specialty event stores only normalized specialty identity', searchEvent.entity_id === specialtyId && JSON.stringify(searchEvent.metadata) === JSON.stringify({ specialty_id: specialtyId }) && !JSON.stringify(searchEvent).includes(unsafeSearch));
        check('comment signal stores comment id but never comment body', Object.keys(commentEvent.metadata).join(',') === 'comment_id' && !JSON.stringify(commentEvent).includes(commentBody));

        const outbox = await outboxFor(patient.id);
        check('each signal has one transactional outbox event', outbox.length === 8 && outbox.every(row => row.event_type === 'user.interaction.recorded'));
        check('outbox payloads contain only bounded identifiers and signal type', outbox.every(row => Object.keys(row.payload).sort().join(',') === 'eventType,userEventId,userId') && !JSON.stringify(outbox).includes(commentBody) && !JSON.stringify(outbox).includes(unsafeSearch));

        for (const row of outbox) await processRecommendationEnvelope(buildEnvelope(row));
        const profiles = (await pool.query('SELECT interest_type,interest_key FROM medorbit.user_interest_profiles WHERE user_id=$1', [patient.id])).rows;
        check('consumer projection produces only category/specialty dimensions', profiles.length > 0 && profiles.every(row => ['post_category', 'specialty'].includes(row.interest_type)));

        const unsafeKeys = ['diagnosis', 'symptoms', 'message_body', 'email', 'token', 'sdp', 'ice'];
        check('unsafe recommendation metadata is rejected', unsafeKeys.every(key => {
            try { validateSafeSourceEvent({ user_id: patient.id, event_type: 'post_view', entity_type: 'doctor_post', entity_id: publishedPost, metadata: { [key]: 'unsafe' } }); return false; }
            catch { return true; }
        }));

        const beforeFailed = (await eventsFor(patient.id)).length;
        const hiddenView = await request('POST', `/feed/posts/${hiddenPost}/view`, auth, {});
        const hiddenLike = await request('POST', `/feed/posts/${hiddenPost}/like`, auth, {});
        const hiddenComment = await request('POST', `/feed/posts/${hiddenPost}/comments`, auth, { body: 'blocked' });
        const badSpecialty = await request('POST', `/recommendations/specialties/${crypto.randomUUID()}/search`, auth, { query: unsafeSearch });
        check('failed or ineligible actions emit no recommendation signal', hiddenView.status === 404 && hiddenLike.status === 404 && hiddenComment.status === 404 && badSpecialty.status === 404 && (await eventsFor(patient.id)).length === beforeFailed);

        check('doctor follow creates no care relationship', Number((await pool.query(
            'SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1 AND patient_id=$2', [doctor.doctorId, patient.patientId]
        )).rows[0].count) === 0);

        await installOutboxFailure(rollbackUser.id);
        const rollbackResponse = await request('POST', `/feed/posts/${publishedPost}/like`, token(rollbackUser), {});
        await dropOutboxFailure();
        const rollbackState = (await pool.query(`SELECT
            (SELECT count(*) FROM medorbit.post_likes WHERE post_id=$1 AND user_id=$2)::int likes,
            (SELECT count(*) FROM medorbit.user_events WHERE user_id=$2)::int events,
            (SELECT count(*) FROM medorbit.outbox_events o JOIN medorbit.user_events e ON e.id=o.aggregate_id WHERE e.user_id=$2)::int outbox`,
        [publishedPost, rollbackUser.id])).rows[0];
        check('social mutation, signal, and outbox rollback atomically', rollbackResponse.status === 500 && Object.values(rollbackState).every(value => value === 0), JSON.stringify(rollbackState));

        const coverageReport = await collectSignalCoverage(pool);
        check('read-only signal coverage report sees all activation paths', coverageReport.allActivated && coverageReport.signals.length === 8);
    } catch (error) {
        failed++; console.error('  ✗ suite error:', error.stack || error.message);
    } finally {
        await cleanup();
        const residue = (await pool.query(`SELECT
            (SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[]))::int users,
            (SELECT count(*) FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[]))::int profiles,
            (SELECT count(*) FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))::int patients,
            (SELECT count(*) FROM medorbit.doctors WHERE id=ANY($2::uuid[]))::int doctors,
            (SELECT count(*) FROM medorbit.doctor_posts WHERE id=ANY($3::uuid[]))::int posts,
            (SELECT count(*) FROM medorbit.post_likes WHERE user_id=ANY($1::uuid[]))::int likes,
            (SELECT count(*) FROM medorbit.post_comments WHERE user_id=ANY($1::uuid[]))::int comments,
            (SELECT count(*) FROM medorbit.user_follows WHERE user_id=ANY($1::uuid[]))::int follows,
            (SELECT count(*) FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))::int events,
            (SELECT count(*) FROM medorbit.user_interest_profiles WHERE user_id=ANY($1::uuid[]))::int interest_profiles,
            (SELECT count(*) FROM medorbit.specialties WHERE id=ANY($4::uuid[]))::int specialties`,
        [users, doctors, posts, specialties])).rows[0];
        check('S8.6 fixtures leave zero residue', Object.values(residue).every(value => value === 0), JSON.stringify(residue));
        console.log(`S8.6 residual counts: ${JSON.stringify(residue)}`);
        console.log(`\nS8.6 signal activation: ${passed} passed, ${failed} failed`);
        await pool.end(); if (failed) process.exitCode = 1;
    }
})();

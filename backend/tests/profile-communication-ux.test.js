const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { io: socketClient } = require('socket.io-client');

const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const marker = `PX${String(Date.now()).slice(-9)}`;
const users = [];
let fixtureSpecialtyId = null;
let passed = 0;
let failed = 0;

function check(number, name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  ✓ ${number}. ${name}`);
    } else {
        failed += 1;
        console.error(`  ✗ ${number}. ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

function token(user) {
    return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: 1 });
}

async function request(method, route, auth = null, body = undefined) {
    const headers = auth ? { Authorization: `Bearer ${auth}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${route}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    let payload = null;
    try { payload = await response.json(); } catch {}
    return { status: response.status, body: payload, headers: response.headers };
}

async function createUser(key, role = 'patient', { patient = role === 'patient', discoverable = false } = {}) {
    const user = { id: crypto.randomUUID(), role, email: `${marker}_${key}@medorbit.test` };
    users.push(user.id);
    await pool.query(
        `INSERT INTO medorbit.users
           (id,email,password_hash,role,is_active,email_verified,authorization_version,preferred_language)
         VALUES($1,$2,'profile-ux-test',$3,true,true,1,'en')`,
        [user.id, user.email, role]
    );
    const profile = await pool.query(
        `INSERT INTO medorbit.user_profiles
           (user_id,first_name_ar,last_name_ar,first_name_en,last_name_en,city,allow_doctor_messages)
         VALUES($1,'اختبار',$2,$3,'Profile','Nablus',$4)
         RETURNING public_profile_id`,
        [user.id, key, key, discoverable]
    );
    user.publicProfileId = profile.rows[0].public_profile_id;
    if (patient) {
        user.patientId = crypto.randomUUID();
        await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)', [user.patientId, user.id]);
    }
    return user;
}

async function createDoctor(key, specialtyId, status = 'approved') {
    const user = await createUser(key, 'doctor', { patient: false });
    user.doctorId = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.doctors
           (id,user_id,medical_license_number,specialty_id,approval_status,approved_at,
            professional_bio_ar,professional_bio_en,sub_specialty,years_of_experience)
         VALUES($1,$2,$3,$4,$5,NOW(),'سيرة قديمة','Legacy bio','Cardiology',8)`,
        [user.doctorId, user.id, `${marker}-${key}`, specialtyId, status]
    );
    return user;
}

function connect(authToken) {
    return socketClient(apiBase.replace(/\/api$/, ''), {
        auth: { token: authToken }, transports: ['websocket'], forceNew: true,
        reconnection: false, timeout: 2500,
    });
}

function connected(socket) {
    return new Promise((resolve) => {
        socket.once('connect', () => resolve(true));
        socket.once('connect_error', () => resolve(false));
    });
}

function subscribe(socket, id) {
    return new Promise((resolve) => socket.emit('conversation.subscribe', { conversation_id: id }, resolve));
}

function waitEvent(socket, event, timeout = 2500) {
    return new Promise((resolve) => {
        const timer = setTimeout(() => resolve(null), timeout);
        socket.once(event, (value) => { clearTimeout(timer); resolve(value); });
    });
}

function readFrontend(relative) {
    return fs.readFileSync(path.resolve(__dirname, '../../frontend', relative), 'utf8');
}

async function cleanup() {
    await pool.query(
        `DELETE FROM medorbit.outbox_events
         WHERE aggregate_id IN (SELECT id FROM medorbit.direct_messages WHERE sender_user_id=ANY($1::uuid[]))`,
        [users]
    ).catch(() => {});
    await pool.query(
        `DELETE FROM medorbit.audit_logs
         WHERE user_id=ANY($1::uuid[])
            OR entity_id IN (SELECT id FROM medorbit.contact_messages WHERE subject LIKE $2)
            OR entity_id IN (
              SELECT conversation_id FROM medorbit.conversation_members WHERE user_id=ANY($1::uuid[])
            )`,
        [users, `${marker}%`]
    ).catch(() => {});
    await pool.query('DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.contact_messages WHERE subject LIKE $1', [`${marker}%`]).catch(() => {});
    await pool.query(
        `DELETE FROM medorbit.direct_conversations
         WHERE id IN (SELECT conversation_id FROM medorbit.conversation_members WHERE user_id=ANY($1::uuid[]))`,
        [users]
    ).catch(() => {});
    await pool.query(
        `DELETE FROM medorbit.doctor_patient_relationships
         WHERE doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))
            OR patient_id IN (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))`,
        [users]
    ).catch(() => {});
    await pool.query(
        `DELETE FROM medorbit.user_follows
         WHERE user_id=ANY($1::uuid[])
            OR doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`,
        [users]
    ).catch(() => {});
    await pool.query('DELETE FROM medorbit.doctor_applications WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_sessions WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
    await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [users]).catch(() => {});
    if (fixtureSpecialtyId) {
        await pool.query('DELETE FROM medorbit.specialties WHERE id=$1', [fixtureSpecialtyId]).catch(() => {});
    }
}

async function residualCounts() {
    return (await pool.query(
        `SELECT
           (SELECT count(*) FROM medorbit.users WHERE id=ANY($1::uuid[]))::int AS users,
           (SELECT count(*) FROM medorbit.contact_messages WHERE subject LIKE $2)::int AS contacts,
           (SELECT count(*) FROM medorbit.conversation_members WHERE user_id=ANY($1::uuid[]))::int AS members,
           (SELECT count(*) FROM medorbit.direct_messages WHERE sender_user_id=ANY($1::uuid[]))::int AS messages,
           (SELECT count(*) FROM medorbit.notifications WHERE user_id=ANY($1::uuid[]))::int AS notifications,
           (SELECT count(*) FROM medorbit.user_events WHERE user_id=ANY($1::uuid[]))::int AS events,
           (SELECT count(*) FROM medorbit.doctor_applications WHERE user_id=ANY($1::uuid[]))::int AS applications`,
        [users, `${marker}%`]
    )).rows[0];
}

(async () => {
    console.log('\nProfile + text communication + contact + call-removal focused tests\n');
    const sockets = [];
    try {
        let specialty = (await pool.query('SELECT id FROM medorbit.specialties ORDER BY id LIMIT 1')).rows[0];
        if (!specialty) {
            fixtureSpecialtyId = crypto.randomUUID();
            specialty = (await pool.query(
                `INSERT INTO medorbit.specialties(id,name_ar,name_en,is_active)
                 VALUES($1,'اختصاص اختبار','Profile Test Specialty',true) RETURNING id`,
                [fixtureSpecialtyId]
            )).rows[0];
        }

        const patient = await createUser('Patient');
        const patientTwo = await createUser('PatientTwo', 'patient', { discoverable: true });
        const patientThree = await createUser('PatientThree', 'patient', { discoverable: true });
        const doctor = await createDoctor('Doctor', specialty.id);
        const doctorTwo = await createDoctor('DoctorTwo', specialty.id);
        const suspended = await createDoctor('Suspended', specialty.id, 'suspended');
        const admin = await createUser('Admin', 'admin', { patient: false });
        const superAdmin = await createUser('Super', 'super_admin', { patient: false });

        await pool.query('INSERT INTO medorbit.user_follows(user_id,doctor_id) VALUES($1,$2),($3,$2)', [patient.id, doctor.doctorId, patientTwo.id]);
        const applicationId = crypto.randomUUID();
        await pool.query(
            `INSERT INTO medorbit.doctor_applications
               (id,user_id,specialty_id,medical_license_number,bio_ar,bio_en,status,
                reviewed_by_user_id,reviewed_at,approved_doctor_id)
             VALUES($1,$2,$3,$4,'سيرة الطلب','Application history','approved',$5,NOW(),$6)`,
            [applicationId, doctor.id, specialty.id, `${marker}-application`, admin.id, doctor.doctorId]
        );

        let response = await request('GET', `/doctors/${doctor.doctorId}`);
        check(1, 'approved doctor public profile loads', response.status === 200 && response.body?.data?.doctor?.id === doctor.doctorId, JSON.stringify(response.body));
        check(2, 'unapproved/suspended doctor handled safely', (await request('GET', `/doctors/${suspended.doctorId}`)).status === 404);
        check(3, 'follower count is correct', Number(response.body.data.doctor.follower_count) === 2);
        check(4, 'patient identities not leaked through follower count', !JSON.stringify(response.body).includes(patient.email) && !('followers' in response.body.data.doctor));

        response = await request('PUT', '/doctors/me/profile', token(doctor), { professionalHeadline: 'Trusted heart care', bio: 'Canonical profile', areasOfExpertise: [' Heart Care ', 'heart care', 'Hypertension'], professionalInterests: ['Prevention', 'prevention'], languagesSpoken: ['Arabic', 'English'] });
        check(5, 'doctor can edit own public profile', response.status === 200 && response.body?.data?.professional_headline === 'Trusted heart care');
        check(6, 'doctor cannot edit another doctor profile', (await request('PUT', `/doctors/${doctor.doctorId}`, token(doctorTwo), { yearsOfExperience: 99 })).status === 403);
        check(7, 'canonical one-field bio works', response.body?.data?.professional_bio === 'Canonical profile' && response.body.data.professional_bio_ar === response.body.data.professional_bio_en);
        response = await request('PUT', '/doctors/me/profile', token(doctor), { bio: 'سيرة عربية موثوقة' });
        check(8, 'Arabic bio works', response.body?.data?.professional_bio === 'سيرة عربية موثوقة');
        response = await request('PUT', '/doctors/me/profile', token(doctor), { bio: 'Evidence-based cardiology' });
        check(9, 'English bio works', response.body?.data?.professional_bio === 'Evidence-based cardiology');
        const mixedBio = 'خبرة Cardiology موثوقة 2026';
        response = await request('PUT', '/doctors/me/profile', token(doctor), { bio: `  ${mixedBio}  ` });
        check(10, 'mixed Unicode bio works', response.body?.data?.professional_bio === mixedBio);
        const application = (await pool.query('SELECT bio_ar,bio_en FROM medorbit.doctor_applications WHERE id=$1', [applicationId])).rows[0];
        check(11, 'application history not overwritten by public profile edit', application.bio_ar === 'سيرة الطلب' && application.bio_en === 'Application history');
        check(12, 'expertise tags bounded/normalized', response.status === 200 && (await request('GET', '/doctors/me/profile', token(doctor))).body.data.areas_of_expertise.length === 2);
        check(13, 'interests bounded/normalized', (await request('GET', '/doctors/me/profile', token(doctor))).body.data.professional_interests.length === 1);
        await pool.query(`UPDATE medorbit.doctors SET professional_bio_ar='قديم عربي',professional_bio_en='Legacy English' WHERE id=$1`, [doctor.doctorId]);
        response = await request('GET', `/doctors/${doctor.doctorId}`);
        check(14, 'legacy bilingual data still renders', response.body?.data?.doctor?.professional_bio_ar === 'قديم عربي' && response.body.data.doctor.professional_bio_en === 'Legacy English');

        response = await request('PUT', '/patients/me/profile', token(patient), { bio: 'Patient social bio', city: 'Ramallah', allowDoctorMessages: true });
        check(15, 'patient can edit own social profile', response.status === 200 && response.body?.data?.bio === 'Patient social bio');
        await request('PUT', '/patients/me/profile', token(patientTwo), { bio: 'Second patient', public_profile_id: patient.publicProfileId });
        check(16, 'patient cannot edit another patient profile', (await request('GET', '/patients/me/profile', token(patient))).body.data.bio === 'Patient social bio');
        const patientProfileText = JSON.stringify((await request('GET', '/patients/me/profile', token(patient))).body);
        check(17, 'public/profile response leaks no clinical data', !/(blood|allerg|diagnos|prescription|appointment|clinical|phone|email)/i.test(patientProfileText));
        check(18, 'anonymous user cannot enumerate patients', (await request('GET', '/patients/discover?search=Patient')).status === 401);
        response = await request('GET', '/patients/discover?search=Patient', token(doctor));
        const discoveryText = JSON.stringify(response.body);
        check(19, 'approved doctor sees only safe discoverable patient data', response.status === 200 && response.body.data.items.some((item) => item.id === patient.publicProfileId) && !/(email|phone|patient_id|medical|appointment)/i.test(discoveryText));
        await request('PUT', '/patients/me/profile', token(patient), { allowDoctorMessages: false });
        response = await request('GET', '/patients/discover?search=Patient', token(doctor));
        check(20, 'privacy preference is enforced', !response.body.data.items.some((item) => item.id === patient.publicProfileId));

        response = await request('POST', '/messages/conversations', token(patient), { counterpartId: doctor.doctorId });
        const patientDoctorConversation = response.body?.data?.id;
        check(21, 'patient → doctor allowed', response.status === 201 && response.body.data.request_status === 'accepted');
        response = await request('POST', '/messages/conversations', token(doctor), { counterpartId: patientTwo.publicProfileId });
        const requestConversation = response.body?.data?.id;
        check(22, 'doctor → patient request allowed', response.status === 201 && response.body.data.request_status === 'pending');
        response = await request('POST', `/messages/conversations/${requestConversation}/accept`, token(patientTwo), {});
        check(23, 'patient accepts request', response.status === 200 && response.body?.data?.request_status === 'accepted', JSON.stringify(response.body));
        response = await request('POST', '/messages/conversations', token(doctor), { counterpartId: patientThree.publicProfileId });
        const declinedConversation = response.body?.data?.id;
        const declined = await request('POST', `/messages/conversations/${declinedConversation}/decline`, token(patientThree), {});
        check(24, 'patient declines request', declined.status === 200 && declined.body?.data?.request_status === 'declined', JSON.stringify(declined.body));
        const duplicateFirst = await request('POST', '/messages/conversations', token(doctorTwo), { counterpartId: patientTwo.publicProfileId });
        const duplicateSecond = await request('POST', '/messages/conversations', token(doctorTwo), { counterpartId: patientTwo.publicProfileId });
        check(25, 'duplicate request prevented', duplicateFirst.body?.data?.id === duplicateSecond.body?.data?.id && duplicateSecond.status === 200);
        response = await request('POST', '/messages/conversations', token(doctor), { counterpartId: doctorTwo.doctorId });
        check(26, 'doctor → doctor allowed', response.status === 201 && response.body.data.conversation_type === 'doctor_doctor' && response.body.data.request_status === 'accepted');
        check(27, 'patient → patient denied', (await request('POST', '/messages/conversations', token(patient), { counterpartId: patientTwo.publicProfileId })).status === 404);
        check(28, 'suspended doctor denied', (await request('POST', '/messages/conversations', token(suspended), { counterpartId: patientTwo.publicProfileId })).status === 403);
        check(29, 'unrelated user cannot read thread', (await request('GET', `/messages/conversations/${patientDoctorConversation}/messages`, token(patientThree))).status === 404);
        check(30, 'admin cannot routinely read thread', (await request('GET', `/messages/conversations/${patientDoctorConversation}/messages`, token(admin))).status === 404);
        const messageSecret = `${marker}-private-message`;
        const clientMessageId = crypto.randomUUID();
        const firstSend = await request('POST', `/messages/conversations/${patientDoctorConversation}/messages`, token(patient), { body: messageSecret, client_message_id: clientMessageId });
        const retrySend = await request('POST', `/messages/conversations/${patientDoctorConversation}/messages`, token(patient), { body: messageSecret, client_message_id: clientMessageId });
        check(31, 'duplicate send retry remains idempotent', firstSend.body?.data?.id === retrySend.body?.data?.id && retrySend.body.data.idempotent === true);
        const relationshipCount = Number((await pool.query('SELECT count(*) FROM medorbit.doctor_patient_relationships WHERE doctor_id=$1 AND patient_id=$2', [doctor.doctorId, patient.patientId])).rows[0].count);
        check(32, 'message does not create care relationship', relationshipCount === 0);
        check(33, 'message does not grant clinical authorization', (await request('GET', `/doctors/me/patients/${patient.patientId}`, token(doctor))).status === 404);
        const messageNotifications = JSON.stringify((await pool.query('SELECT title_ar,title_en,message_ar,message_en FROM medorbit.notifications WHERE user_id=$1', [doctor.id])).rows);
        check(34, 'message body excluded from notifications', !messageNotifications.includes(messageSecret));
        const messageEvents = JSON.stringify((await pool.query('SELECT metadata FROM medorbit.user_events WHERE user_id=$1', [patient.id])).rows);
        const messageOutbox = JSON.stringify((await pool.query('SELECT payload FROM medorbit.outbox_events WHERE aggregate_id=$1', [firstSend.body.data.id])).rows);
        check(35, 'message body excluded from recommendation/outbox', !messageEvents.includes(messageSecret) && !messageOutbox.includes(messageSecret));
        const beforeRead = await request('GET', '/messages/conversations', token(doctor));
        await request('POST', `/messages/conversations/${patientDoctorConversation}/read`, token(doctor), { message_id: firstSend.body.data.id });
        const afterRead = await request('GET', '/messages/conversations', token(doctor));
        check(36, 'unread/read works', beforeRead.body.data.items.find((item) => item.id === patientDoctorConversation).unread_count === 1 && afterRead.body.data.items.find((item) => item.id === patientDoctorConversation).unread_count === 0);

        const contactSecret = `${marker}-contact-private-body`;
        response = await request('POST', '/contact', token(patient), { subject: `${marker} Auth contact`, message: contactSecret });
        const authContactId = response.body?.data?.id;
        check(37, 'authenticated contact submit works', response.status === 201 && authContactId);
        response = await request('POST', '/contact', null, { name: 'Guest Person', email: `${marker}@example.test`, subject: `${marker} Guest contact`, message: 'Guest support message' });
        const guestContactId = response.body?.data?.id;
        check(38, 'guest contact works only if intentionally supported', response.status === 201 && guestContactId);
        const invalidContact = await request('POST', '/contact', null, { name: '', email: 'bad', subject: '', message: '' });
        const oversizedContact = await request('POST', '/contact', null, { name: 'Guest', email: 'guest@example.test', subject: `${marker} Oversized`, message: 'x'.repeat(4001) });
        check(39, 'invalid/oversized input rejected', invalidContact.status === 400 && oversizedContact.status === 400);
        check(40, 'contact creates admin notification', Number((await pool.query(`SELECT count(*) FROM medorbit.notifications WHERE user_id=$1 AND notification_type='NEW_CONTACT_MESSAGE' AND reference_id=$2`, [admin.id, authContactId])).rows[0].count) === 1);
        check(41, 'contact creates super_admin notification', Number((await pool.query(`SELECT count(*) FROM medorbit.notifications WHERE user_id=$1 AND notification_type='NEW_CONTACT_MESSAGE' AND reference_id=$2`, [superAdmin.id, authContactId])).rows[0].count) === 1);
        check(42, 'patient cannot access admin contact inbox', (await request('GET', '/admin/contact-messages', token(patient))).status === 403);
        check(43, 'doctor cannot access admin contact inbox', (await request('GET', '/admin/contact-messages', token(doctor))).status === 403);
        check(44, 'admin can read', (await request('GET', `/admin/contact-messages/${authContactId}`, token(admin))).body?.data?.message === contactSecret);
        check(45, 'super_admin can read', (await request('GET', `/admin/contact-messages/${authContactId}`, token(superAdmin))).status === 200);
        check(46, 'mark read works', (await request('POST', `/admin/contact-messages/${authContactId}/read`, token(admin), {})).body?.data?.status === 'read');
        check(47, 'resolve works', (await request('POST', `/admin/contact-messages/${authContactId}/resolve`, token(superAdmin), {})).body?.data?.status === 'resolved');
        const contactNotificationText = JSON.stringify((await pool.query(`SELECT title_ar,title_en,message_ar,message_en FROM medorbit.notifications WHERE reference_id=$1`, [authContactId])).rows);
        check(48, 'contact message body not placed in generic notification', !contactNotificationText.includes(contactSecret));
        let rateLimited = false;
        for (let index = 0; index < 6 && !rateLimited; index += 1) {
            const attempt = await request('POST', '/contact', null, { name: 'Rate Test', email: 'rate@example.test', subject: `${marker} Rate ${index}`, message: 'Rate-limit proof' });
            rateLimited = attempt.status === 429;
        }
        check(49, 'contact endpoint rate limit works', rateLimited);

        const layoutSource = readFrontend('src/js/layout.js');
        const appointmentSource = readFrontend('src/js/my-appointments.js');
        const frontendProduction = [layoutSource, appointmentSource, readFrontend('src/js/api.js'), readFrontend('src/js/direct-messages.js')].join('\n');
        const backendAppSource = fs.readFileSync(path.resolve(__dirname, '../src/app.js'), 'utf8');
        const realtimeSource = fs.readFileSync(path.resolve(__dirname, '../src/realtime.js'), 'utf8');
        check(50, 'no active Voice Consultation navigation', !/voiceConsultations|video-consultation\.html/i.test(layoutSource));
        check(51, 'no active Video Consultation navigation', !/video-consultation\.html/i.test(layoutSource));
        check(52, 'no active Call Doctor button', !/Call Doctor|Join Call|الانضمام للمكالمة/i.test(frontendProduction));
        check(53, 'no active human getUserMedia flow', !/getUserMedia/i.test(frontendProduction));
        check(54, 'no active human RTCPeerConnection path', !/RTCPeerConnection/i.test(frontendProduction));
        check(55, 'no active human SDP signaling route/event', !/video\.(offer|answer)|\bsdp\b/i.test(`${backendAppSource}\n${realtimeSource}`));
        check(56, 'no active human ICE signaling route/event', !/ice-candidate|iceConfig/i.test(`${backendAppSource}\n${realtimeSource}`));
        check(57, 'no active application STUN dependency', !/WEBRTC_STUN|stun:/i.test(`${backendAppSource}\n${realtimeSource}\n${frontendProduction}`));
        check(58, 'no active application TURN dependency', !/WEBRTC_TURN|turn:/i.test(`${backendAppSource}\n${realtimeSource}\n${frontendProduction}`));
        const doctorSocket = connect(token(doctor));
        sockets.push(doctorSocket);
        const socketReady = await connected(doctorSocket);
        const subscribed = socketReady ? await subscribe(doctorSocket, patientDoctorConversation) : { ok: false };
        const eventPromise = waitEvent(doctorSocket, 'message.created');
        const liveSend = await request('POST', `/messages/conversations/${patientDoctorConversation}/messages`, token(patient), { body: 'Text socket proof', client_message_id: crypto.randomUUID() });
        const liveEvent = await eventPromise;
        check(59, 'text Socket.IO messaging still works', socketReady && subscribed.ok && liveEvent?.id === liveSend.body?.data?.id);

        const doctorUi = readFrontend('src/js/doctor.js');
        const patientUi = readFrontend('src/js/patient-profile.js');
        const directCss = readFrontend('src/css/direct-messages.css');
        const sharedCss = readFrontend('src/css/experience.css');
        const badgeSource = readFrontend('src/js/layout.js');
        check(60, 'Doctor Profile primary CTA order correct', doctorUi.indexOf('doctorMessageBtn') < doctorUi.indexOf('book-appointment.html') && doctorUi.indexOf('book-appointment.html') < doctorUi.indexOf('doctorFollowBtn'));
        check(61, 'Doctor tabs work', ['about','posts','reviews','availability','clinics'].every((tab) => doctorUi.includes(`['${tab}'`) || doctorUi.includes(`data-panel=\"${tab}`)) && doctorUi.includes("addEventListener('click'"));
        check(62, 'Patient profile renders safely', patientUi.includes('textContent') && readFrontend('public/patient-profile.html').includes('patientProfileForm'));
        check(63, 'messaging desktop layout initializes', /grid-template-columns:minmax\(270px,34%\) 1fr/.test(directCss) && frontendProduction.includes('loadConversations'));
        check(64, 'messaging mobile layout initializes', directCss.includes('.messages-thread-open .thread-pane') && directCss.includes('@media(max-width:760px)'));
        check(65, 'notification badge still works', badgeSource.includes("count > 9 ? '9+'") && badgeSource.includes("count === 0"));
        check(66, 'RTL layout works', sharedCss.includes('border-inline-end') && readFrontend('public/doctor.html').includes('dir="rtl"'));
        check(67, 'LTR layout works', readFrontend('src/js/i18n.js').includes("document.documentElement.dir") && readFrontend('src/js/i18n.js').includes("'ltr'"));
        check(68, 'safe user-content rendering', doctorUi.includes('escapeHtml') && readFrontend('src/js/direct-messages.js').includes('body.textContent=message.body'));
        check(69, 'no unsafe innerHTML for profile/message/contact user content', patientUi.includes('textContent') && readFrontend('src/js/contact.js').includes('textContent') && readFrontend('src/js/admin-contact-messages.js').includes('body.textContent=item.message'));
        check(70, 'empty states render correctly', doctorUi.includes('profile-compact-empty') && readFrontend('src/js/direct-messages.js').includes('No conversations yet'));

        const safePatientResponse = JSON.stringify((await request('GET', '/patients/me/profile', token(patient))).body);
        check(71, 'patient profile response contains no PHI', !/(blood|allerg|chronic|diagnos|prescription|appointment|clinical|emergency_contact|insurance)/i.test(safePatientResponse));
        const s8Text = JSON.stringify((await pool.query(`SELECT metadata FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])`, [users])).rows);
        check(72, 'message content does not enter S8', !s8Text.includes(messageSecret) && !s8Text.includes('Text socket proof'));
        const contactEventText = JSON.stringify((await pool.query(`SELECT metadata FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])`, [users])).rows);
        const contactOutboxText = JSON.stringify((await pool.query(`SELECT payload FROM medorbit.outbox_events WHERE payload::text LIKE $1`, [`%${marker}%`])).rows);
        check(73, 'contact content does not enter S8', !contactEventText.includes(contactSecret) && !contactOutboxText.includes(contactSecret));
        check(74, 'profile bio does not enter S8', !s8Text.includes(mixedBio) && !s8Text.includes('Patient social bio'));
        check(75, 'admin contact endpoint IDOR denied', (await request('GET', `/admin/contact-messages/${guestContactId}`, token(patient))).status === 403);
    } catch (err) {
        failed += 1;
        console.error('  ✗ suite error:', err.stack || err.message);
    } finally {
        sockets.forEach((socket) => socket.disconnect());
        await cleanup();
        const residual = await residualCounts();
        console.log(`Focused residual counts: ${JSON.stringify(residual)}`);
        check(76, 'fixture residue zero', Object.values(residual).every((value) => Number(value) === 0));
        await pool.end();
    }
    console.log(`\nFocused profile/communication UX: ${passed} passed, ${failed} failed`);
    process.exit(failed ? 1 : 0);
})();

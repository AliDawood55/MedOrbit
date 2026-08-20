const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const marker = `schedule_${Date.now()}`;
const ids = {
    specialty: crypto.randomUUID(),
    clinic: crypto.randomUUID(),
    users: [],
    conversations: [],
};
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  PASS ${passed + failed}. ${name}`);
    } else {
        failed += 1;
        console.error(`  FAIL ${passed + failed}. ${name}${detail ? ` -- ${detail}` : ''}`);
    }
}

function token(user) {
    return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: 1 });
}

async function request(method, route, authToken, body) {
    const headers = authToken ? { Authorization: `Bearer ${authToken}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${route}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    const contentType = response.headers.get('content-type') || '';
    return {
        status: response.status,
        body: contentType.includes('application/json') ? await response.json() : await response.text(),
    };
}

async function createUser(key, role, withPatient = false, allowDoctorMessages = false) {
    const user = {
        id: crypto.randomUUID(),
        role,
        email: `${marker}_${key}@medorbit.test`,
        publicProfileId: crypto.randomUUID(),
    };
    ids.users.push(user.id);
    await pool.query(
        `INSERT INTO medorbit.users
           (id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES($1,$2,'schedule-test-only',$3,true,true,1)`,
        [user.id, user.email, role]
    );
    await pool.query(
        `INSERT INTO medorbit.user_profiles
           (user_id,first_name_ar,last_name_ar,first_name_en,last_name_en,
            public_profile_id,allow_doctor_messages)
         VALUES($1,'اختبار','جدول',$2,'Schedule',$3,$4)`,
        [user.id, key, user.publicProfileId, allowDoctorMessages]
    );
    if (withPatient) {
        user.patientId = crypto.randomUUID();
        await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)', [user.patientId, user.id]);
    }
    return user;
}

async function createDoctor(key, approvalStatus = 'approved') {
    const user = await createUser(key, 'doctor');
    user.doctorId = crypto.randomUUID();
    user.license = `${marker}-${key}-license`;
    await pool.query(
        `INSERT INTO medorbit.doctors
           (id,user_id,medical_license_number,specialty_id,approval_status,approved_at,
            consultation_duration,consultation_fee,is_accepting_patients)
         VALUES($1,$2,$3,$4,$5,NOW(),30,100,true)`,
        [user.doctorId, user.id, user.license, ids.specialty, approvalStatus]
    );
    return user;
}

async function cleanup() {
    await pool.query('DROP TRIGGER IF EXISTS appointment_notif_test_force_failure ON medorbit.notifications').catch(() => {});
    await pool.query('DROP FUNCTION IF EXISTS medorbit.appointment_notif_test_force_failure()').catch(() => {});
    const users = ids.users;
    if (users.length) {
        await pool.query(
            `UPDATE medorbit.conversation_members SET last_read_message_id=NULL
             WHERE user_id=ANY($1::uuid[])`, [users]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.direct_conversations
             WHERE id IN (SELECT conversation_id FROM medorbit.conversation_members WHERE user_id=ANY($1::uuid[]))`,
            [users]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.appointment_status_history
             WHERE appointment_id IN (
               SELECT a.id FROM medorbit.appointments a
               LEFT JOIN medorbit.patients p ON p.id=a.patient_id
               LEFT JOIN medorbit.doctors d ON d.id=a.doctor_id
               WHERE p.user_id=ANY($1::uuid[]) OR d.user_id=ANY($1::uuid[])
             )`, [users]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.doctor_patient_relationships
             WHERE patient_id IN (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))
                OR doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`,
            [users]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.appointments
             WHERE patient_id IN (SELECT id FROM medorbit.patients WHERE user_id=ANY($1::uuid[]))
                OR doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`,
            [users]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.doctor_applications WHERE user_id=ANY($1::uuid[])
               OR approved_doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`,
            [users]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.doctor_availability
             WHERE doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`,
            [users]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.doctor_clinic_assignments
             WHERE doctor_id IN (SELECT id FROM medorbit.doctors WHERE user_id=ANY($1::uuid[]))`,
            [users]
        ).catch(() => {});
        await pool.query('DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
        await pool.query('DELETE FROM medorbit.outbox_events WHERE payload::text LIKE $1', [`%${marker}%`]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_events WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
        await pool.query('DELETE FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
        await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [users]).catch(() => {});
        await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [users]).catch(() => {});
    }
    await pool.query('DELETE FROM medorbit.clinics WHERE id=$1', [ids.clinic]).catch(() => {});
    await pool.query('DELETE FROM medorbit.specialties WHERE id=$1', [ids.specialty]).catch(() => {});
}

async function residueCount() {
    const users = ids.users;
    const queries = [
        ['users', 'id=ANY($1::uuid[])'],
        ['user_profiles', 'user_id=ANY($1::uuid[])'],
        ['patients', 'user_id=ANY($1::uuid[])'],
        ['doctors', 'user_id=ANY($1::uuid[])'],
        ['doctor_applications', 'user_id=ANY($1::uuid[])'],
        ['notifications', 'user_id=ANY($1::uuid[])'],
        ['user_events', 'user_id=ANY($1::uuid[])'],
    ];
    let total = 0;
    for (const [table, where] of queries) {
        total += (await pool.query(`SELECT count(*)::int count FROM medorbit.${table} WHERE ${where}`, [users])).rows[0].count;
    }
    total += (await pool.query('SELECT count(*)::int count FROM medorbit.clinics WHERE id=$1', [ids.clinic])).rows[0].count;
    total += (await pool.query('SELECT count(*)::int count FROM medorbit.specialties WHERE id=$1', [ids.specialty])).rows[0].count;
    total += (await pool.query('SELECT count(*)::int count FROM medorbit.outbox_events WHERE payload::text LIKE $1', [`%${marker}%`])).rows[0].count;
    return total;
}

(async () => {
    try {
        await pool.query(
            `INSERT INTO medorbit.specialties(id,name_ar,name_en)
             VALUES($1,'جدولة اختبار',$2)`, [ids.specialty, marker]
        );
        await pool.query(
            `INSERT INTO medorbit.clinics
               (id,name_ar,name_en,address_ar,address_en,latitude,longitude,verification_status)
             VALUES($1,'عيادة اختبار',$2,'عنوان','Test address',32.2,35.2,'verified')`,
            [ids.clinic, marker]
        );

        const doctorA = await createDoctor('doctor_a');
        const doctorB = await createDoctor('doctor_b');
        const cliniclessDoctor = await createDoctor('clinicless');
        const suspended = await createDoctor('suspended', 'suspended');
        const patientA = await createUser('patient_a', 'patient', true, true);
        const patientB = await createUser('patient_b', 'patient', true, true);
        const admin = await createUser('admin', 'admin');
        await pool.query(
            `INSERT INTO medorbit.doctor_clinic_assignments(doctor_id,clinic_id,is_primary,is_active)
             VALUES($1,$3,true,true),($2,$3,true,true)`,
            [doctorA.doctorId, doctorB.doctorId, ids.clinic]
        );
        const applicationId = crypto.randomUUID();
        await pool.query(
            `INSERT INTO medorbit.doctor_applications
               (id,user_id,specialty_id,medical_license_number,years_of_experience,
                consultation_fee,consultation_duration,bio_en,status,approved_doctor_id,
                reviewed_at,submitted_at)
             VALUES($1,$2,$3,$4,8,100,30,'Historical reviewed application','approved',$5,NOW(),NOW())`,
            [applicationId, doctorA.id, ids.specialty, doctorA.license, doctorA.doctorId]
        );
        const applicationBefore = (await pool.query(
            'SELECT row_to_json(a)::text value FROM medorbit.doctor_applications a WHERE id=$1',
            [applicationId]
        )).rows[0].value;
        const dates = (await pool.query(
            `SELECT ((CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date+7)::text AS day_off,
                    ((CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date+14)::text AS block_day,
                    ((CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date+9)::text AS special_day,
                    ((CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date+10)::text AS duration_day,
                    ((CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date-1)::text AS past_day,
                    EXTRACT(DOW FROM ((CURRENT_TIMESTAMP AT TIME ZONE 'Africa/Cairo')::date+7))::int AS weekday`
        )).rows[0];
        const doctorToken = token(doctorA);
        const doctorBToken = token(doctorB);
        const cliniclessDoctorToken = token(cliniclessDoctor);
        const suspendedToken = token(suspended);
        const patientAToken = token(patientA);
        const patientBToken = token(patientB);
        const adminToken = token(admin);

        const cliniclessOnline = await request('POST', '/doctors/me/availability', cliniclessDoctorToken, {
            specific_date: dates.special_day,
            start_time: '16:00',
            end_time: '17:00',
            slot_duration: 30,
            is_telemedicine: true,
        });
        const cliniclessRuleId = cliniclessOnline.body?.data?.id;
        check('approved doctor can create online availability without a clinic', cliniclessOnline.status === 201
            && cliniclessRuleId && cliniclessOnline.body.data.clinic_id === null);
        const cliniclessEdited = await request('PUT', `/doctors/me/availability/${cliniclessRuleId}`, cliniclessDoctorToken, {
            end_time: '17:30',
        });
        check('clinicless online availability can be edited', cliniclessEdited.status === 200
            && cliniclessEdited.body?.data?.end_time === '17:30:00'
            && cliniclessEdited.body?.data?.clinic_id === null);
        const cliniclessInPerson = await request('POST', '/doctors/me/availability', cliniclessDoctorToken, {
            specific_date: dates.duration_day, start_time: '08:00', end_time: '09:00',
            slot_duration: 30, is_telemedicine: false,
        });
        const forgedClinic = await request('POST', '/doctors/me/availability', cliniclessDoctorToken, {
            specific_date: dates.duration_day, start_time: '10:00', end_time: '11:00',
            slot_duration: 30, is_telemedicine: true, clinic_id: ids.clinic,
        });
        check('in-person still requires a clinic and supplied clinics remain assignment-checked',
            cliniclessInPerson.status === 400 && cliniclessInPerson.body?.error?.code === 'CLINIC_REQUIRED'
            && forgedClinic.status === 400 && forgedClinic.body?.error?.code === 'CLINIC_NOT_ASSIGNED');
        const cliniclessSlots = await request('GET', `/appointments/available-slots?doctor_id=${cliniclessDoctor.doctorId}&date=${dates.special_day}`, doctorToken);
        const cliniclessBooking = await request('POST', '/appointments', patientBToken, {
            doctor_id: cliniclessDoctor.doctorId,
            scheduled_date: dates.special_day,
            start_time: '16:00:00',
            end_time: '16:30:00',
            duration_minutes: 30,
            appointment_type: 'telemedicine',
        });
        const cliniclessBookingId = cliniclessBooking.body?.data?.id;
        const cliniclessPersisted = cliniclessBookingId ? (await pool.query(
            'SELECT clinic_id,appointment_type FROM medorbit.appointments WHERE id=$1', [cliniclessBookingId]
        )).rows[0] : null;
        check('clinicless online slots remain backend-derived and book with no clinic', cliniclessSlots.status === 200
            && cliniclessSlots.body.data.some((slot) => slot.start_time === '16:00:00' && slot.clinic_id === null)
            && cliniclessBooking.status === 201 && cliniclessPersisted?.clinic_id === null
            && cliniclessPersisted?.appointment_type === 'telemedicine');
        const deleteBookedClinicless = await request('DELETE', `/doctors/me/availability/${cliniclessRuleId}`, cliniclessDoctorToken);
        check('clinicless availability still protects existing appointments', deleteBookedClinicless.status === 409
            && deleteBookedClinicless.body?.error?.code === 'BOOKED_APPOINTMENT_CONFLICT');
        const cancelClinicless = await request('PUT', `/appointments/${cliniclessBookingId}/cancel`, patientBToken, {});
        const deleteClinicless = await request('DELETE', `/doctors/me/availability/${cliniclessRuleId}`, cliniclessDoctorToken);
        check('clinicless online availability can be deleted after its active booking is cancelled',
            cancelClinicless.status === 200 && deleteClinicless.status === 200);

        const weekly = await request('POST', '/doctors/me/availability', doctorToken, {
            day_of_week: dates.weekday,
            start_time: '09:00',
            end_time: '12:00',
            slot_duration: 30,
            clinic_id: ids.clinic,
            is_telemedicine: false,
        });
        const weeklyId = weekly.body?.data?.id;
        check('approved doctor can create weekly availability', weekly.status === 201 && weeklyId, JSON.stringify(weekly.body));

        const second = await request('POST', '/doctors/me/availability', doctorToken, {
            day_of_week: dates.weekday, start_time: '14:00', end_time: '16:00',
            slot_duration: 30, clinic_id: ids.clinic, is_telemedicine: false,
        });
        const secondId = second.body?.data?.id;
        check('doctor can add multiple non-overlapping periods', second.status === 201 && secondId);

        const overlap = await request('POST', '/doctors/me/availability', doctorToken, {
            day_of_week: dates.weekday, start_time: '10:00', end_time: '11:00',
            slot_duration: 30, clinic_id: ids.clinic, is_telemedicine: false,
        });
        check('overlapping periods are rejected', overlap.status === 409 && overlap.body?.error?.code === 'AVAILABILITY_OVERLAP');

        const invalidRange = await request('POST', '/doctors/me/availability', doctorToken, {
            day_of_week: dates.weekday, start_time: '12:00', end_time: '11:00',
            slot_duration: 30, clinic_id: ids.clinic,
        });
        check('invalid start/end is rejected', invalidRange.status === 400 && invalidRange.body?.error?.code === 'INVALID_TIME_RANGE');

        const edited = await request('PUT', `/doctors/me/availability/${secondId}`, doctorToken, {
            start_time: '15:00', end_time: '17:00',
        });
        check('doctor edits own availability', edited.status === 200 && edited.body?.data?.start_time === '15:00:00');

        const deleted = await request('DELETE', `/doctors/me/availability/${secondId}`, doctorToken);
        const deletedCount = (await pool.query('SELECT count(*)::int count FROM medorbit.doctor_availability WHERE id=$1', [secondId])).rows[0].count;
        check('doctor deletes own unbooked availability', deleted.status === 200 && deletedCount === 0);

        const crossEdit = await request('PUT', `/doctors/me/availability/${weeklyId}`, doctorBToken, { start_time: '08:00' });
        const suppliedDoctor = await request('POST', '/doctors/me/availability', doctorBToken, {
            doctor_id: doctorA.doctorId, day_of_week: dates.weekday,
            start_time: '18:00', end_time: '19:00', slot_duration: 30, clinic_id: ids.clinic,
        });
        check('doctor cannot edit another doctor schedule or supply doctor identity', crossEdit.status === 404 && suppliedDoctor.status === 400);

        const patientEdit = await request('POST', '/doctors/me/availability', patientAToken, {});
        const adminEdit = await request('POST', '/doctors/me/availability', adminToken, {});
        check('patient/admin cannot edit doctor schedule', patientEdit.status === 403 && adminEdit.status === 403);

        const suspendedCreate = await request('POST', '/doctors/me/availability', suspendedToken, {
            day_of_week: dates.weekday, start_time: '09:00', end_time: '10:00',
            slot_duration: 30, clinic_id: ids.clinic,
        });
        check('suspended doctor cannot create bookable availability', suspendedCreate.status === 403);

        const dayOff = await request('POST', '/doctors/me/availability', doctorToken, {
            availability_type: 'day_off', specific_date: dates.day_off,
        });
        const dayOffSlots = await request('GET', `/appointments/available-slots?doctor_id=${doctorA.doctorId}&clinic_id=${ids.clinic}&date=${dates.day_off}`, doctorToken);
        check('date-specific day-off removes all slots', dayOff.status === 201 && dayOffSlots.status === 200 && dayOffSlots.body.data.length === 0);

        const block = await request('POST', '/doctors/me/availability', doctorToken, {
            availability_type: 'blocked', specific_date: dates.block_day,
            start_time: '09:30', end_time: '10:00',
        });
        const blockSlots = await request('GET', `/appointments/available-slots?doctor_id=${doctorA.doctorId}&clinic_id=${ids.clinic}&date=${dates.block_day}`, doctorToken);
        check('partial blocked period removes only overlapping slots', block.status === 201
            && blockSlots.body.data.some((slot) => slot.start_time === '09:00:00')
            && !blockSlots.body.data.some((slot) => slot.start_time === '09:30:00'));

        const special = await request('POST', '/doctors/me/availability', doctorToken, {
            availability_type: 'available', specific_date: dates.special_day,
            start_time: '18:00', end_time: '19:00', slot_duration: 30,
            clinic_id: ids.clinic, is_telemedicine: false,
        });
        const specialSlots = await request('GET', `/appointments/available-slots?doctor_id=${doctorA.doctorId}&clinic_id=${ids.clinic}&date=${dates.special_day}`, doctorToken);
        check('special added availability produces bookable slots', special.status === 201
            && specialSlots.body.data.some((slot) => slot.start_time === '18:00:00'));

        const bookingBody = {
            doctor_id: doctorA.doctorId, clinic_id: ids.clinic, scheduled_date: dates.block_day,
            start_time: '09:00:00', end_time: '09:30:00', duration_minutes: 30,
            appointment_type: 'in_person', reason_for_visit: `private-reason-${marker}`,
            notes: `private-notes-${marker}`,
        };
        const booking = await request('POST', '/appointments', patientAToken, bookingBody);
        const bookingId = booking.body?.data?.id;
        const afterBookingSlots = await request('GET', `/appointments/available-slots?doctor_id=${doctorA.doctorId}&clinic_id=${ids.clinic}&date=${dates.block_day}`, doctorToken);
        check('booked slot is excluded from future availability', booking.status === 201 && bookingId
            && !afterBookingSlots.body.data.some((slot) => slot.start_time === '09:00:00'));

        const bookingNotifications = await pool.query(
            `SELECT * FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2
               AND notification_type='APPOINTMENT_BOOKED'
               AND reference_type='APPOINTMENT'`,
            [doctorA.id, bookingId]
        );
        check('booking transaction creates exactly one doctor notification', bookingNotifications.rowCount === 1
            && bookingNotifications.rows[0].is_read === false);
        const doctorUnread = await request('GET', '/notifications/unread-count', doctorToken);
        check('appointment notification is reflected in unread count', doctorUnread.status === 200
            && doctorUnread.body?.data?.count >= 1);
        const bookingRetry = await request('POST', '/appointments', patientAToken, bookingBody);
        const bookingCountAfterRetry = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='APPOINTMENT_BOOKED'`,
            [doctorA.id, bookingId]
        )).rows[0].count);
        check('booking retry cannot duplicate the doctor notification', bookingRetry.status === 409
            && bookingCountAfterRetry === 1);

        const concurrentBody = { ...bookingBody, start_time: '10:00:00', end_time: '10:30:00' };
        const concurrent = await Promise.all([
            request('POST', '/appointments', patientAToken, concurrentBody),
            request('POST', '/appointments', patientBToken, concurrentBody),
        ]);
        check('same slot cannot be double-booked concurrently', concurrent.filter((item) => item.status === 201).length === 1
            && concurrent.filter((item) => item.status === 409).length === 1, JSON.stringify(concurrent.map((item) => item.status)));

        const changedSchedule = await request('PUT', `/doctors/me/availability/${weeklyId}`, doctorToken, { is_telemedicine: true });
        const preservedAfterChange = (await pool.query(
            'SELECT duration_minutes,appointment_type FROM medorbit.appointments WHERE id=$1', [bookingId]
        )).rows[0];
        check('existing appointment is preserved after schedule change', changedSchedule.status === 200
            && preservedAfterChange?.duration_minutes === 30 && preservedAfterChange?.appointment_type === 'in_person');

        const removeBooked = await request('DELETE', `/doctors/me/availability/${weeklyId}`, doctorToken);
        const appointmentStillExists = (await pool.query('SELECT count(*)::int count FROM medorbit.appointments WHERE id=$1', [bookingId])).rows[0].count;
        check('removing availability does not silently delete booked appointment', removeBooked.status === 409
            && removeBooked.body?.error?.code === 'BOOKED_APPOINTMENT_CONFLICT' && appointmentStillExists === 1);

        const invalidDuration = await request('PUT', '/doctors/me/profile', doctorToken, { consultationDuration: 25 });
        const validDuration = await request('PUT', '/doctors/me/profile', doctorToken, { consultationDuration: 45 });
        const durationRule = await request('POST', '/doctors/me/availability', doctorToken, {
            specific_date: dates.duration_day, start_time: '20:00', end_time: '21:30',
            clinic_id: ids.clinic, is_telemedicine: false,
        });
        const originalDuration = (await pool.query('SELECT duration_minutes FROM medorbit.appointments WHERE id=$1', [bookingId])).rows[0].duration_minutes;
        check('appointment duration validation works and affects only new availability', invalidDuration.status === 400
            && validDuration.status === 200 && durationRule.body?.data?.slot_duration === 45 && originalDuration === 30);

        const invalidFee = await request('PUT', '/doctors/me/profile', doctorToken, { consultationFee: -1 });
        const validFee = await request('PUT', '/doctors/me/profile', doctorToken, { consultationFee: 125.5 });
        const protectedLicense = await request('PUT', '/doctors/me/profile', doctorToken, { medicalLicenseNumber: 'forged-license' });
        const doctorAfterFee = (await pool.query('SELECT consultation_fee,medical_license_number FROM medorbit.doctors WHERE id=$1', [doctorA.doctorId])).rows[0];
        check('fee validation works and verified credentials remain protected', invalidFee.status === 400 && validFee.status === 200
            && Number(doctorAfterFee.consultation_fee) === 125.5 && protectedLicense.status === 400
            && doctorAfterFee.medical_license_number === doctorA.license);

        const acceptingOff = await request('PUT', '/doctors/me/profile', doctorToken, { isAcceptingPatients: false });
        const closedSlots = await request('GET', `/appointments/available-slots?doctor_id=${doctorA.doctorId}&clinic_id=${ids.clinic}&date=${dates.special_day}`, doctorToken);
        await request('PUT', '/doctors/me/profile', doctorToken, { isAcceptingPatients: true });
        check('accepting-patients false prevents new booking slots', acceptingOff.status === 200
            && closedSlots.status === 200 && closedSlots.body.data.length === 0);

        const futureSlots = await request('GET', `/appointments/available-slots?doctor_id=${doctorA.doctorId}&clinic_id=${ids.clinic}&date=${dates.special_day}`, doctorToken);
        check('patient sees only valid future bookable slots', futureSlots.status === 200 && futureSlots.body.data.length > 0
            && futureSlots.body.data.every((slot) => slot.scheduled_date === dates.special_day && slot.end_time > slot.start_time));

        const past = await request('GET', `/appointments/available-slots?doctor_id=${doctorA.doctorId}&clinic_id=${ids.clinic}&date=${dates.past_day}`, doctorToken);
        check('patient cannot book a past slot', past.status === 400 && past.body?.error?.code === 'PAST_SLOT');

        const blockedBooking = await request('POST', '/appointments', patientAToken, {
            ...bookingBody, start_time: '09:30:00', end_time: '10:00:00', appointment_type: 'telemedicine',
        });
        check('patient cannot book a blocked slot', blockedBooking.status === 409 && blockedBooking.body?.error?.code === 'SLOT_BUSY');

        const forgedBooking = await request('POST', '/appointments', patientAToken, {
            ...bookingBody, doctor_id: doctorB.doctorId, start_time: '10:30:00', end_time: '11:00:00',
        });
        check('patient cannot book another doctor stale or forged slot', forgedBooking.status === 409 && forgedBooking.body?.error?.code === 'SLOT_BUSY');

        const patientAppointments = await request('GET', '/appointments', patientAToken);
        check('appointment appears for patient', patientAppointments.status === 200
            && patientAppointments.body.data.some((item) => item.id === bookingId));

        const doctorSchedule = await request('GET', '/doctors/me/schedule', doctorToken);
        const doctorAppointment = doctorSchedule.body?.data?.appointments?.find((item) => item.id === bookingId);
        check('appointment appears in doctor schedule with safe patient identity', doctorSchedule.status === 200
            && doctorAppointment?.patient_profile_id === patientA.publicProfileId && !('meeting_link' in doctorAppointment));

        const conversation = await request('POST', '/messages/conversations', doctorToken, {
            counterpartId: patientA.publicProfileId,
        });
        if (conversation.body?.data?.id) ids.conversations.push(conversation.body.data.id);
        check('text-message CTA works without voice or video dependency', [200, 201].includes(conversation.status)
            && conversation.body?.data?.conversation_type === 'patient_doctor');

        const relationships = (await pool.query(
            `SELECT count(*)::int count FROM medorbit.doctor_patient_relationships
             WHERE doctor_id=$1 AND patient_id=ANY($2::uuid[])`,
            [doctorA.doctorId, [patientA.patientId, patientB.patientId]]
        )).rows[0].count;
        check('schedule and booking do not create clinical authorization', relationships === 0);

        const confirmed = await request('PUT', `/appointments/${bookingId}/confirm`, doctorToken, {});
        const confirmationCount = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='APPOINTMENT_CONFIRMED'`,
            [patientA.id, bookingId]
        )).rows[0].count);
        check('doctor confirmation creates exactly one patient notification', confirmed.status === 200
            && confirmationCount === 1);
        const confirmedRetry = await request('PUT', `/appointments/${bookingId}/confirm`, doctorToken, {});
        const confirmationCountAfterRetry = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='APPOINTMENT_CONFIRMED'`,
            [patientA.id, bookingId]
        )).rows[0].count);
        check('confirmation retry cannot duplicate the patient notification', confirmedRetry.status === 200
            && confirmationCountAfterRetry === 1);

        const patientCancelled = await request('PUT', `/appointments/${bookingId}/cancel`, patientAToken, {
            reason: `private-cancellation-${marker}`,
        });
        const patientCancelCount = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='APPOINTMENT_CANCELLED'`,
            [doctorA.id, bookingId]
        )).rows[0].count);
        const patientCancelRetry = await request('PUT', `/appointments/${bookingId}/cancel`, patientAToken, {});
        const patientCancelCountAfterRetry = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='APPOINTMENT_CANCELLED'`,
            [doctorA.id, bookingId]
        )).rows[0].count);
        check('patient cancellation notifies the doctor exactly once', patientCancelled.status === 200
            && patientCancelRetry.status === 404 && patientCancelCount === 1 && patientCancelCountAfterRetry === 1);

        const concurrentWinner = concurrent.find((item) => item.status === 201);
        const doctorCancelledId = concurrentWinner?.body?.data?.id;
        const doctorCancelledPatient = doctorCancelledId ? (await pool.query(
            `SELECT p.user_id FROM medorbit.appointments a
             JOIN medorbit.patients p ON p.id=a.patient_id WHERE a.id=$1`,
            [doctorCancelledId]
        )).rows[0] : null;
        const doctorCancelled = await request('PUT', `/appointments/${doctorCancelledId}/cancel`, doctorToken, {
            reason: 'Schedule changed',
        });
        const doctorCancelCount = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='APPOINTMENT_CANCELLED'`,
            [doctorCancelledPatient?.user_id, doctorCancelledId]
        )).rows[0].count);
        check('doctor cancellation notifies the persisted appointment patient', doctorCancelled.status === 200
            && doctorCancelCount === 1);
        const doctorCancelRetry = await request('PUT', `/appointments/${doctorCancelledId}/cancel`, doctorToken, {});
        const doctorCancelCountAfterRetry = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND reference_id=$2 AND notification_type='APPOINTMENT_CANCELLED'`,
            [doctorCancelledPatient?.user_id, doctorCancelledId]
        )).rows[0].count);
        check('doctor cancellation retry cannot duplicate the patient notification', doctorCancelRetry.status === 404
            && doctorCancelCountAfterRetry === 1);

        const notificationText = JSON.stringify((await pool.query(
            `SELECT title_ar,title_en,message_ar,message_en,notification_type,reference_id,reference_type
             FROM medorbit.notifications WHERE reference_id=$1`, [bookingId]
        )).rows);
        check('appointment notifications contain safe references and no reason notes or secrets',
            !notificationText.includes(`private-reason-${marker}`)
            && !notificationText.includes(`private-notes-${marker}`)
            && !notificationText.includes(`private-cancellation-${marker}`)
            && !/(diagnosis|prescription|medical record|token|email|phone)/i.test(notificationText));

        await pool.query(
            `CREATE OR REPLACE FUNCTION medorbit.appointment_notif_test_force_failure()
             RETURNS trigger LANGUAGE plpgsql AS $$
             BEGIN
               IF NEW.notification_type='APPOINTMENT_BOOKED' THEN
                 RAISE EXCEPTION 'controlled appointment notification failure';
               END IF;
               RETURN NEW;
             END $$`
        );
        await pool.query(
            `CREATE TRIGGER appointment_notif_test_force_failure
             BEFORE INSERT ON medorbit.notifications
             FOR EACH ROW EXECUTE FUNCTION medorbit.appointment_notif_test_force_failure()`
        );
        const appointmentsBeforeFailure = Number((await pool.query(
            `SELECT count(*) FROM medorbit.appointments
             WHERE patient_id=$1 AND doctor_id=$2 AND scheduled_date=$3 AND start_time='10:30:00'`,
            [patientA.patientId, doctorA.doctorId, dates.block_day]
        )).rows[0].count);
        const notificationsBeforeFailure = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND notification_type='APPOINTMENT_BOOKED'`, [doctorA.id]
        )).rows[0].count);
        const failedBooking = await request('POST', '/appointments', patientAToken, {
            ...bookingBody, start_time: '10:30:00', end_time: '11:00:00', appointment_type: 'telemedicine',
        });
        const appointmentsAfterFailure = Number((await pool.query(
            `SELECT count(*) FROM medorbit.appointments
             WHERE patient_id=$1 AND doctor_id=$2 AND scheduled_date=$3 AND start_time='10:30:00'`,
            [patientA.patientId, doctorA.doctorId, dates.block_day]
        )).rows[0].count);
        const notificationsAfterFailure = Number((await pool.query(
            `SELECT count(*) FROM medorbit.notifications
             WHERE user_id=$1 AND notification_type='APPOINTMENT_BOOKED'`, [doctorA.id]
        )).rows[0].count);
        await pool.query('DROP TRIGGER appointment_notif_test_force_failure ON medorbit.notifications');
        await pool.query('DROP FUNCTION medorbit.appointment_notif_test_force_failure()');
        check('notification failure rolls back booking with no orphan appointment or notification',
            appointmentsBeforeFailure === 0 && failedBooking.status === 500 && appointmentsAfterFailure === 0
            && notificationsAfterFailure === notificationsBeforeFailure);

        const signalRows = (await pool.query(
            `SELECT count(*)::int count FROM medorbit.user_events
             WHERE user_id=ANY($1::uuid[])
               AND (event_type ILIKE '%appointment%' OR event_type ILIKE '%availability%' OR event_type ILIKE '%schedule%')`,
            [ids.users]
        )).rows[0].count;
        const outboxRows = (await pool.query(
            `SELECT count(*)::int count FROM medorbit.outbox_events
             WHERE payload::text LIKE $1
               AND (event_type ILIKE '%appointment%' OR event_type ILIKE '%availability%' OR event_type ILIKE '%schedule%')`,
            [`%${marker}%`]
        )).rows[0].count;
        check('no schedule content enters the S8 recommendation system', signalRows === 0 && outboxRows === 0);

        const applicationAfter = (await pool.query(
            'SELECT row_to_json(a)::text value FROM medorbit.doctor_applications a WHERE id=$1',
            [applicationId]
        )).rows[0].value;
        check('historical doctor application remains unchanged', applicationAfter === applicationBefore);

        await cleanup();
        check('fixture residue is zero', await residueCount() === 0);
    } catch (err) {
        console.error(err);
        failed += 1;
        await cleanup().catch(() => {});
    } finally {
        await pool.end();
    }

    console.log(`\nDoctor self-service scheduling: ${passed} passed, ${failed} failed`);
    if (passed + failed !== 46) {
        console.error(`Expected exactly 46 checks, observed ${passed + failed}`);
        process.exit(1);
    }
    process.exit(failed ? 1 : 0);
})();

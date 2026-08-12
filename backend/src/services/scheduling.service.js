const db = require('../config/database');
const env = require('../config/env');
const { notifyAppointmentTransition } = require('./notification.service');

const ALLOWED_DURATIONS = new Set([15, 20, 30, 45, 60]);
const AVAILABILITY_TYPES = new Set(['available', 'blocked', 'day_off']);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/;

class SchedulingError extends Error {
    constructor(message, statusCode = 400, code = 'VALIDATION_ERROR') {
        super(message);
        this.statusCode = statusCode;
        this.code = code;
    }
}

function uuid(value, label) {
    const normalized = String(value || '').trim();
    if (!UUID_RE.test(normalized)) throw new SchedulingError(`${label} is invalid`);
    return normalized.toLowerCase();
}

function dateOnly(value, label = 'Date') {
    const normalized = value instanceof Date && !Number.isNaN(value.getTime())
        ? `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, '0')}-${String(value.getDate()).padStart(2, '0')}`
        : String(value || '').trim();
    if (!DATE_RE.test(normalized)) throw new SchedulingError(`${label} must use YYYY-MM-DD`);
    const parsed = new Date(`${normalized}T00:00:00Z`);
    if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== normalized) {
        throw new SchedulingError(`${label} is invalid`);
    }
    return normalized;
}

function timeOnly(value, label) {
    const normalized = String(value || '').trim();
    if (!TIME_RE.test(normalized)) throw new SchedulingError(`${label} must use HH:mm`);
    return normalized.length === 5 ? `${normalized}:00` : normalized;
}

function timeMinutes(value) {
    const [hours, minutes, seconds = 0] = String(value).split(':').map(Number);
    return (hours * 60) + minutes + (seconds / 60);
}

function minutesTime(value) {
    const whole = Math.round(value);
    return `${String(Math.floor(whole / 60)).padStart(2, '0')}:${String(whole % 60).padStart(2, '0')}:00`;
}

function booleanValue(value, label) {
    if (typeof value !== 'boolean') throw new SchedulingError(`${label} must be boolean`);
    return value;
}

function durationValue(value, fallback = null) {
    const duration = value == null || value === '' ? fallback : Number(value);
    if (!Number.isInteger(duration) || !ALLOWED_DURATIONS.has(duration)) {
        throw new SchedulingError('Duration must be one of 15, 20, 30, 45, or 60 minutes');
    }
    return duration;
}

function availabilityDto(row) {
    return {
        id: row.id,
        clinic_id: row.clinic_id,
        day_of_week: row.day_of_week,
        specific_date: row.specific_date,
        start_time: row.start_time,
        end_time: row.end_time,
        slot_duration: row.slot_duration,
        is_telemedicine: row.is_telemedicine,
        availability_type: row.availability_type,
        is_active: row.is_active,
        created_at: row.created_at,
        updated_at: row.updated_at,
    };
}

async function resolveApprovedDoctor(userId, queryable = db) {
    const result = await queryable.query(
        `SELECT d.id,d.user_id,d.consultation_duration,d.consultation_fee,
                d.is_accepting_patients
         FROM medorbit.doctors d
         JOIN medorbit.users u ON u.id=d.user_id
         WHERE d.user_id=$1 AND d.approval_status='approved'
           AND u.role='doctor' AND u.is_active=true AND u.email_verified=true
           AND u.deleted_at IS NULL`,
        [userId]
    );
    if (!result.rows[0]) {
        throw new SchedulingError('Doctor is not approved for scheduling', 403, 'DOCTOR_NOT_APPROVED');
    }
    return result.rows[0];
}

async function assertAssignedClinic(doctorId, clinicId, queryable = db) {
    const id = uuid(clinicId, 'Clinic');
    const result = await queryable.query(
        `SELECT c.id,c.name_ar,c.name_en,dca.is_primary
         FROM medorbit.doctor_clinic_assignments dca
         JOIN medorbit.clinics c ON c.id=dca.clinic_id
         WHERE dca.doctor_id=$1 AND dca.clinic_id=$2
           AND dca.is_active=true AND c.is_active=true`,
        [doctorId, id]
    );
    if (!result.rows[0]) {
        throw new SchedulingError('Clinic is not assigned to this doctor', 400, 'CLINIC_NOT_ASSIGNED');
    }
    return result.rows[0];
}

async function assertDateRange(value, maxDays, queryable = db) {
    const date = dateOnly(value);
    const result = await queryable.query(
        `SELECT $1::date<(CURRENT_TIMESTAMP AT TIME ZONE $3)::date AS past,
                $1::date>(CURRENT_TIMESTAMP AT TIME ZONE $3)::date+$2::int AS beyond`,
        [date, maxDays, env.scheduling.timeZone]
    );
    if (result.rows[0].past) throw new SchedulingError('Date must not be in the past', 400, 'PAST_DATE');
    if (result.rows[0].beyond) {
        throw new SchedulingError(`Date must be within the next ${maxDays} days`, 400, 'DATE_OUTSIDE_HORIZON');
    }
    return date;
}

function mergedPayload(body, existing = null, doctorDuration = 30) {
    const source = existing ? { ...existing, ...body } : { ...body };
    const type = String(source.availability_type || 'available').trim().toLowerCase();
    if (!AVAILABILITY_TYPES.has(type)) throw new SchedulingError('Invalid availability type');

    if (type === 'day_off') {
        return {
            availabilityType: type,
            dayOfWeek: null,
            specificDate: dateOnly(source.specific_date),
            startTime: '00:00:00',
            endTime: '23:59:59',
            slotDuration: durationValue(doctorDuration, 30),
            clinicId: null,
            isTelemedicine: false,
            isActive: source.is_active == null ? true : booleanValue(source.is_active, 'Active state'),
        };
    }

    const startTime = timeOnly(source.start_time, 'Start time');
    const endTime = timeOnly(source.end_time, 'End time');
    const start = timeMinutes(startTime);
    const end = timeMinutes(endTime);
    if (end <= start) throw new SchedulingError('End time must be after start time', 400, 'INVALID_TIME_RANGE');
    if (end - start > 16 * 60) throw new SchedulingError('Availability period must not exceed 16 hours');

    let dayOfWeek = null;
    let specificDate = null;
    if (source.specific_date) specificDate = dateOnly(source.specific_date);
    if (source.day_of_week !== null && source.day_of_week !== undefined && source.day_of_week !== '') {
        dayOfWeek = Number(source.day_of_week);
        if (!Number.isInteger(dayOfWeek) || dayOfWeek < 0 || dayOfWeek > 6) {
            throw new SchedulingError('Weekday must be between 0 and 6', 400, 'INVALID_WEEKDAY');
        }
    }
    if (type === 'blocked' && !specificDate) {
        throw new SchedulingError('Blocked time requires a specific date');
    }
    if (type === 'available' && ((dayOfWeek == null) === (specificDate == null))) {
        throw new SchedulingError('Choose either a weekday or a specific date');
    }
    if (type === 'blocked') dayOfWeek = null;

    const isTelemedicine = type === 'available'
        ? (source.is_telemedicine == null ? false : booleanValue(source.is_telemedicine, 'Telemedicine state'))
        : false;
    let clinicId = null;
    if (type === 'available' && source.clinic_id) {
        clinicId = uuid(source.clinic_id, 'Clinic');
    } else if (type === 'available' && !isTelemedicine) {
        throw new SchedulingError(
            'Clinic is required for in-person availability',
            400,
            'CLINIC_REQUIRED'
        );
    }

    return {
        availabilityType: type,
        dayOfWeek,
        specificDate,
        startTime,
        endTime,
        slotDuration: type === 'available'
            ? durationValue(source.slot_duration, durationValue(doctorDuration, 30))
            : durationValue(doctorDuration, 30),
        clinicId,
        isTelemedicine,
        isActive: source.is_active == null ? true : booleanValue(source.is_active, 'Active state'),
    };
}

async function lockScope(client, key) {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [key]);
}

async function assertRuleCapacity(doctorId, rule, excludeId, queryable) {
    const result = await queryable.query(
        `SELECT count(*)::int AS count
         FROM medorbit.doctor_availability
         WHERE doctor_id=$1 AND is_active=true AND id<>COALESCE($4::uuid,uuid_nil())
           AND (($2::date IS NOT NULL AND specific_date=$2)
                OR ($2::date IS NULL AND specific_date IS NULL AND day_of_week=$3))`,
        [doctorId, rule.specificDate, rule.dayOfWeek, excludeId]
    );
    if (result.rows[0].count >= 8) {
        throw new SchedulingError('No more than 8 active periods are allowed for one day');
    }
}

async function assertNoRuleConflict(doctorId, rule, excludeId, queryable) {
    const result = await queryable.query(
        `SELECT id,availability_type
         FROM medorbit.doctor_availability
         WHERE doctor_id=$1 AND is_active=true AND id<>COALESCE($7::uuid,uuid_nil())
           AND (($2::date IS NOT NULL AND specific_date=$2)
                OR ($2::date IS NULL AND specific_date IS NULL AND day_of_week=$3))
           AND (
             availability_type='day_off' OR $4='day_off'
             OR (
               availability_type=$4
               AND start_time<$6::time AND end_time>$5::time
             )
           )
         LIMIT 1`,
        [doctorId, rule.specificDate, rule.dayOfWeek, rule.availabilityType,
            rule.startTime, rule.endTime, excludeId]
    );
    if (result.rows[0]) {
        throw new SchedulingError(
            rule.availabilityType === 'available'
                ? 'This time overlaps another availability period.'
                : 'This date already has a conflicting exception.',
            409,
            'AVAILABILITY_OVERLAP'
        );
    }
}

async function bookedConflictCount(doctorId, rule, queryable) {
    const result = await queryable.query(
        `SELECT count(*)::int AS count
         FROM medorbit.appointments
         WHERE doctor_id=$1 AND status NOT IN ('cancelled','no_show')
           AND scheduled_date>=(CURRENT_TIMESTAMP AT TIME ZONE $6)::date
           AND (($2::date IS NOT NULL AND scheduled_date=$2)
                OR ($2::date IS NULL AND EXTRACT(DOW FROM scheduled_date)::int=$3))
           AND start_time<$5::time AND end_time>$4::time`,
        [doctorId, rule.specificDate, rule.dayOfWeek, rule.startTime, rule.endTime,
            env.scheduling.timeZone]
    );
    return result.rows[0].count;
}

async function assertNoBookedConflict(doctorId, rule, queryable) {
    if (await bookedConflictCount(doctorId, rule, queryable)) {
        throw new SchedulingError(
            'An existing appointment uses this time. Manage the appointment before changing availability.',
            409,
            'BOOKED_APPOINTMENT_CONFLICT'
        );
    }
}

async function createAvailability(userId, body) {
    if ('doctor_id' in body || 'doctorId' in body) {
        throw new SchedulingError('Doctor identity is resolved from authentication');
    }
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const doctor = await resolveApprovedDoctor(userId, client);
        const rule = mergedPayload(body, null, doctor.consultation_duration || 30);
        await lockScope(client, `doctor-schedule:${doctor.id}`);
        if (rule.specificDate) await assertDateRange(rule.specificDate, 365, client);
        if (rule.clinicId) await assertAssignedClinic(doctor.id, rule.clinicId, client);
        await assertRuleCapacity(doctor.id, rule, null, client);
        await assertNoRuleConflict(doctor.id, rule, null, client);
        if (rule.availabilityType !== 'available') {
            await assertNoBookedConflict(doctor.id, rule, client);
        }
        const inserted = await client.query(
            `INSERT INTO medorbit.doctor_availability
               (doctor_id,clinic_id,day_of_week,specific_date,start_time,end_time,
                slot_duration,is_telemedicine,availability_type,is_active)
             VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
             RETURNING *`,
            [doctor.id, rule.clinicId, rule.dayOfWeek, rule.specificDate,
                rule.startTime, rule.endTime, rule.slotDuration, rule.isTelemedicine,
                rule.availabilityType, rule.isActive]
        );
        await client.query('COMMIT');
        return availabilityDto(inserted.rows[0]);
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        if (err.code === '23505') {
            throw new SchedulingError('Duplicate availability period', 409, 'AVAILABILITY_OVERLAP');
        }
        throw err;
    } finally {
        client.release();
    }
}

async function loadOwnedRule(client, doctorId, ruleId) {
    const id = uuid(ruleId, 'Availability');
    const result = await client.query(
        `SELECT * FROM medorbit.doctor_availability
         WHERE id=$1 AND doctor_id=$2 FOR UPDATE`,
        [id, doctorId]
    );
    if (!result.rows[0]) throw new SchedulingError('Availability not found', 404, 'NOT_FOUND');
    return result.rows[0];
}

async function updateAvailability(userId, ruleId, body) {
    if ('doctor_id' in body || 'doctorId' in body || 'id' in body) {
        throw new SchedulingError('Ownership fields are not accepted');
    }
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const doctor = await resolveApprovedDoctor(userId, client);
        await lockScope(client, `doctor-schedule:${doctor.id}`);
        const existing = await loadOwnedRule(client, doctor.id, ruleId);
        const rule = mergedPayload(body, existing, doctor.consultation_duration || 30);
        if (rule.specificDate) await assertDateRange(rule.specificDate, 365, client);
        if (rule.clinicId) await assertAssignedClinic(doctor.id, rule.clinicId, client);
        if (rule.isActive) await assertRuleCapacity(doctor.id, rule, existing.id, client);
        if (existing.availability_type === 'available'
            && (body.is_active === false || Object.keys(body).some((key) => (
                ['day_of_week','specific_date','start_time','end_time','clinic_id','availability_type'].includes(key)
            )))) {
            await assertNoBookedConflict(doctor.id, {
                specificDate: existing.specific_date,
                dayOfWeek: existing.day_of_week,
                startTime: existing.start_time,
                endTime: existing.end_time,
            }, client);
        }
        if (rule.availabilityType !== 'available') await assertNoBookedConflict(doctor.id, rule, client);
        await assertNoRuleConflict(doctor.id, rule, existing.id, client);
        const updated = await client.query(
            `UPDATE medorbit.doctor_availability
             SET clinic_id=$1,day_of_week=$2,specific_date=$3,start_time=$4,end_time=$5,
                 slot_duration=$6,is_telemedicine=$7,availability_type=$8,is_active=$9,
                 updated_at=NOW()
             WHERE id=$10 AND doctor_id=$11
             RETURNING *`,
            [rule.clinicId, rule.dayOfWeek, rule.specificDate, rule.startTime,
                rule.endTime, rule.slotDuration, rule.isTelemedicine,
                rule.availabilityType, rule.isActive, existing.id, doctor.id]
        );
        await client.query('COMMIT');
        return availabilityDto(updated.rows[0]);
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        if (err.code === '23505') {
            throw new SchedulingError('Duplicate availability period', 409, 'AVAILABILITY_OVERLAP');
        }
        throw err;
    } finally {
        client.release();
    }
}

async function deleteAvailability(userId, ruleId) {
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const doctor = await resolveApprovedDoctor(userId, client);
        await lockScope(client, `doctor-schedule:${doctor.id}`);
        const existing = await loadOwnedRule(client, doctor.id, ruleId);
        if (existing.availability_type === 'available') {
            await assertNoBookedConflict(doctor.id, {
                specificDate: existing.specific_date,
                dayOfWeek: existing.day_of_week,
                startTime: existing.start_time,
                endTime: existing.end_time,
            }, client);
        }
        await client.query(
            `DELETE FROM medorbit.doctor_availability
             WHERE id=$1 AND doctor_id=$2`,
            [existing.id, doctor.id]
        );
        await client.query('COMMIT');
        return { id: existing.id };
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        throw err;
    } finally {
        client.release();
    }
}

async function getDoctorSchedule(userId) {
    const doctor = await resolveApprovedDoctor(userId);
    const [rules, clinics, appointments] = await Promise.all([
        db.query(
            `SELECT * FROM medorbit.doctor_availability
             WHERE doctor_id=$1
             ORDER BY specific_date NULLS FIRST,day_of_week NULLS LAST,start_time,id`,
            [doctor.id]
        ),
        db.query(
            `SELECT c.id,c.name_ar,c.name_en,dca.is_primary
             FROM medorbit.doctor_clinic_assignments dca
             JOIN medorbit.clinics c ON c.id=dca.clinic_id
             WHERE dca.doctor_id=$1 AND dca.is_active=true AND c.is_active=true
             ORDER BY dca.is_primary DESC,c.name_en,c.id`,
            [doctor.id]
        ),
        db.query(
            `SELECT a.id,a.appointment_number,a.scheduled_date,a.start_time,a.end_time,
                    a.duration_minutes,a.appointment_type,a.status,
                    up.public_profile_id AS patient_profile_id,
                    up.first_name_ar,up.last_name_ar,up.first_name_en,up.last_name_en
             FROM medorbit.appointments a
             JOIN medorbit.patients p ON p.id=a.patient_id
             JOIN medorbit.user_profiles up ON up.user_id=p.user_id
             WHERE a.doctor_id=$1
               AND a.scheduled_date>=(CURRENT_TIMESTAMP AT TIME ZONE $2)::date-INTERVAL '365 days'
             ORDER BY a.scheduled_date,a.start_time,a.id
             LIMIT 250`,
            [doctor.id, env.scheduling.timeZone]
        ),
    ]);
    return {
        doctor: {
            id: doctor.id,
            consultation_duration: doctor.consultation_duration,
            consultation_fee: doctor.consultation_fee,
            is_accepting_patients: doctor.is_accepting_patients,
        },
        booking_horizon_days: env.scheduling.bookingHorizonDays,
        weekly: rules.rows.filter((row) => row.specific_date == null).map(availabilityDto),
        overrides: rules.rows.filter((row) => row.specific_date != null).map(availabilityDto),
        clinics: clinics.rows,
        appointments: appointments.rows,
    };
}

async function getDateState(date, horizonDays, queryable) {
    const selected = dateOnly(date);
    const result = await queryable.query(
        `SELECT $1::date::text AS selected_date,
                (CURRENT_TIMESTAMP AT TIME ZONE $3)::date::text AS today,
                ((CURRENT_TIMESTAMP AT TIME ZONE $3)::date+$2::int)::text AS last_date,
                EXTRACT(DOW FROM $1::date)::int AS weekday,
                CASE WHEN $1::date=(CURRENT_TIMESTAMP AT TIME ZONE $3)::date
                     THEN to_char(CURRENT_TIMESTAMP AT TIME ZONE $3,'HH24:MI:SS') END AS current_time,
                $1::date<(CURRENT_TIMESTAMP AT TIME ZONE $3)::date AS past,
                $1::date>(CURRENT_TIMESTAMP AT TIME ZONE $3)::date+$2::int AS beyond`,
        [selected, horizonDays, env.scheduling.timeZone]
    );
    if (result.rows[0].past) throw new SchedulingError('Cannot book a past date', 400, 'PAST_SLOT');
    if (result.rows[0].beyond) {
        throw new SchedulingError('Date is outside the booking horizon', 400, 'DATE_OUTSIDE_HORIZON');
    }
    return result.rows[0];
}

function overlaps(start, end, period) {
    return start < timeMinutes(period.end_time) && end > timeMinutes(period.start_time);
}

async function listBookableSlots({ doctorId, clinicId, date }, queryable = db) {
    const safeDoctorId = uuid(doctorId, 'Doctor');
    const safeClinicId = clinicId == null || clinicId === '' ? null : uuid(clinicId, 'Clinic');
    const horizon = env.scheduling.bookingHorizonDays;
    const dateState = await getDateState(date, horizon, queryable);
    const doctorResult = await queryable.query(
        `SELECT d.id,d.is_accepting_patients
         FROM medorbit.doctors d
         JOIN medorbit.users u ON u.id=d.user_id
         WHERE d.id=$1 AND d.approval_status='approved' AND d.is_accepting_patients=true
           AND u.role='doctor' AND u.is_active=true AND u.email_verified=true
           AND u.deleted_at IS NULL`,
        [safeDoctorId]
    );
    if (!doctorResult.rows[0]) return [];
    if (safeClinicId) await assertAssignedClinic(safeDoctorId, safeClinicId, queryable);

    const [rules, appointments] = await Promise.all([
        queryable.query(
            `SELECT clinic_id,start_time,end_time,slot_duration,is_telemedicine,
                    availability_type,specific_date,day_of_week
             FROM medorbit.doctor_availability
             WHERE doctor_id=$1 AND is_active=true
               AND (specific_date=$2::date
                    OR (specific_date IS NULL AND day_of_week=$3))
             ORDER BY start_time,end_time,clinic_id NULLS LAST,id`,
            [safeDoctorId, dateState.selected_date, dateState.weekday]
        ),
        queryable.query(
            `SELECT start_time,end_time
             FROM medorbit.appointments
             WHERE doctor_id=$1 AND scheduled_date=$2::date
               AND status NOT IN ('cancelled','no_show')`,
            [safeDoctorId, dateState.selected_date]
        ),
    ]);

    if (rules.rows.some((row) => row.availability_type === 'day_off')) return [];
    const available = rules.rows.filter((row) => {
        if (row.availability_type !== 'available') return false;
        if (safeClinicId) {
            return row.clinic_id === safeClinicId
                || (row.clinic_id == null && Boolean(row.is_telemedicine));
        }
        return row.clinic_id == null && Boolean(row.is_telemedicine);
    });
    const blocked = rules.rows.filter((row) => row.availability_type === 'blocked');
    const booked = appointments.rows;
    const seen = new Set();
    const slots = [];
    for (const window of available) {
        const duration = durationValue(window.slot_duration, 30);
        const first = timeMinutes(window.start_time);
        const end = timeMinutes(window.end_time);
        for (let start = first; start + duration <= end; start += duration) {
            const slotEnd = start + duration;
            if (dateState.current_time && start <= timeMinutes(dateState.current_time)) continue;
            if (blocked.some((period) => overlaps(start, slotEnd, period))) continue;
            if (booked.some((period) => overlaps(start, slotEnd, period))) continue;
            const startTime = minutesTime(start);
            const endTime = minutesTime(slotEnd);
            const key = `${startTime}|${endTime}|${window.is_telemedicine ? 1 : 0}`;
            if (seen.has(key)) continue;
            seen.add(key);
            slots.push({
                clinic_id: window.clinic_id || null,
                scheduled_date: dateState.selected_date,
                start_time: startTime,
                end_time: endTime,
                slot_duration: duration,
                duration_minutes: duration,
                is_telemedicine: Boolean(window.is_telemedicine),
                appointment_type: window.is_telemedicine ? 'telemedicine' : 'in_person',
            });
        }
    }
    return slots.sort((a, b) => a.start_time.localeCompare(b.start_time));
}

function boundedOptionalText(value, maxLength, label) {
    if (value == null || value === '') return null;
    if (typeof value !== 'string') throw new SchedulingError(`${label} must be text`);
    const normalized = value.trim();
    if (normalized.length > maxLength) throw new SchedulingError(`${label} is too long`);
    return normalized || null;
}

async function bookAppointment(userId, body) {
    const doctorId = uuid(body.doctor_id, 'Doctor');
    const scheduledDate = dateOnly(body.scheduled_date, 'Appointment date');
    const startTime = timeOnly(body.start_time, 'Start time');
    const endTime = timeOnly(body.end_time, 'End time');
    const duration = durationValue(body.duration_minutes);
    const appointmentType = String(body.appointment_type || '').trim();
    if (!['in_person', 'telemedicine'].includes(appointmentType)) {
        throw new SchedulingError('Invalid appointment type');
    }
    const clinicId = body.clinic_id == null || body.clinic_id === ''
        ? null
        : uuid(body.clinic_id, 'Clinic');
    if (appointmentType === 'in_person' && !clinicId) {
        throw new SchedulingError(
            'Clinic is required for an in-person appointment',
            400,
            'CLINIC_REQUIRED'
        );
    }
    const reason = boundedOptionalText(body.reason_for_visit, 2000, 'Reason for visit');
    const notes = boundedOptionalText(body.notes, 4000, 'Notes');
    const client = await db.getClient();
    try {
        await client.query('BEGIN');
        const patient = await client.query(
            `SELECT p.id FROM medorbit.patients p
             JOIN medorbit.users u ON u.id=p.user_id
             WHERE p.user_id=$1 AND u.is_active=true AND u.deleted_at IS NULL`,
            [userId]
        );
        if (!patient.rows[0]) throw new SchedulingError('Patient profile not found', 404, 'PATIENT_NOT_FOUND');
        await lockScope(client, `doctor-schedule:${doctorId}`);
        const slots = await listBookableSlots({ doctorId, clinicId, date: scheduledDate }, client);
        const valid = slots.find((slot) => (
            slot.start_time === startTime && slot.end_time === endTime
            && slot.duration_minutes === duration && slot.appointment_type === appointmentType
            && slot.clinic_id === clinicId
        ));
        if (!valid) {
            throw new SchedulingError('Appointment slot is no longer available', 409, 'SLOT_BUSY');
        }
        const result = await client.query(
            `INSERT INTO medorbit.appointments
               (appointment_number,patient_id,doctor_id,clinic_id,scheduled_date,
                start_time,end_time,duration_minutes,appointment_type,status,
                meeting_link,reason_for_visit,notes)
             VALUES('APT-'||upper(substr(replace(uuid_generate_v4()::text,'-',''),1,12)),
                    $1,$2,$3,$4,$5,$6,$7,$8,'scheduled',NULL,$9,$10)
             RETURNING *`,
            [patient.rows[0].id, doctorId, clinicId, scheduledDate, startTime,
                endTime, duration, appointmentType, reason, notes]
        );
        await client.query(
            `INSERT INTO medorbit.appointment_status_history(appointment_id,new_status,changed_by)
             VALUES($1,'scheduled',$2)`,
            [result.rows[0].id, userId]
        );
        await notifyAppointmentTransition(client, result.rows[0].id, 'booked');
        await client.query('COMMIT');
        return result.rows[0];
    } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        if (err.code === '23505' && err.constraint === 'appointments_one_active_doctor_start') {
            throw new SchedulingError('Appointment slot is already booked', 409, 'SLOT_BUSY');
        }
        throw err;
    } finally {
        client.release();
    }
}

module.exports = {
    ALLOWED_DURATIONS,
    SchedulingError,
    resolveApprovedDoctor,
    createAvailability,
    updateAvailability,
    deleteAvailability,
    getDoctorSchedule,
    listBookableSlots,
    bookAppointment,
};

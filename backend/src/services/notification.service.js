async function notifyDoctorApplicationReviewers(client, applicationId) {
    const result = await client.query(
        `INSERT INTO medorbit.notifications
            (user_id, title_ar, title_en, message_ar, message_en,
             notification_type, reference_id, reference_type, channel)
         SELECT u.id,
                'طلب انضمام طبيب جديد',
                'New doctor application',
                'تم إرسال طلب جديد لمراجعة الانضمام كطبيب.',
                'A user submitted an application for doctor review.',
                'DOCTOR_APPLICATION_SUBMITTED',
                $1,
                'DOCTOR_APPLICATION',
                'in_app'
         FROM medorbit.users u
         WHERE u.role IN ('admin', 'super_admin')
           AND u.is_active=true
           AND u.email_verified=true
           AND u.deleted_at IS NULL
           AND NOT EXISTS (
               SELECT 1
               FROM medorbit.notifications n
               WHERE n.user_id=u.id
                 AND n.notification_type='DOCTOR_APPLICATION_SUBMITTED'
                 AND n.reference_type='DOCTOR_APPLICATION'
                 AND n.reference_id=$1
           )
         RETURNING id, user_id`,
        [applicationId]
    );

    return result.rows;
}

const APPOINTMENT_NOTIFICATIONS = Object.freeze({
    booked: {
        recipient: 'doctor',
        type: 'APPOINTMENT_BOOKED',
        titleAr: 'موعد جديد',
        titleEn: 'New appointment',
        messageAr: 'تم حجز موعد جديد. راجع جدول مواعيدك للتفاصيل.',
        messageEn: 'A new appointment was booked. Review your schedule for details.',
    },
    confirmed: {
        recipient: 'patient',
        type: 'APPOINTMENT_CONFIRMED',
        titleAr: 'تم تأكيد الموعد',
        titleEn: 'Appointment confirmed',
        messageAr: 'أكد الطبيب موعدك. راجع صفحة مواعيدك للتفاصيل.',
        messageEn: 'Your doctor confirmed the appointment. Review your appointments for details.',
    },
    cancelled_by_patient: {
        recipient: 'doctor',
        type: 'APPOINTMENT_CANCELLED',
        titleAr: 'تم إلغاء الموعد',
        titleEn: 'Appointment cancelled',
        messageAr: 'ألغى المريض الموعد. راجع جدول مواعيدك للتفاصيل.',
        messageEn: 'The patient cancelled an appointment. Review your schedule for details.',
    },
    cancelled_by_doctor: {
        recipient: 'patient',
        type: 'APPOINTMENT_CANCELLED',
        titleAr: 'تم إلغاء الموعد',
        titleEn: 'Appointment cancelled',
        messageAr: 'ألغى الطبيب موعدك. راجع صفحة مواعيدك للتفاصيل.',
        messageEn: 'Your doctor cancelled the appointment. Review your appointments for details.',
    },
});

async function notifyAppointmentTransition(client, appointmentId, transition) {
    const config = APPOINTMENT_NOTIFICATIONS[transition];
    if (!config) throw new Error(`Unsupported appointment notification transition: ${transition}`);

    const appointment = await client.query(
        `SELECT a.id,
                patient_user.id AS patient_user_id,
                doctor_user.id AS doctor_user_id
         FROM medorbit.appointments a
         JOIN medorbit.patients p ON p.id=a.patient_id
         JOIN medorbit.users patient_user ON patient_user.id=p.user_id
         JOIN medorbit.doctors d ON d.id=a.doctor_id
         JOIN medorbit.users doctor_user ON doctor_user.id=d.user_id
         WHERE a.id=$1`,
        [appointmentId]
    );
    if (!appointment.rows[0]) throw new Error('Appointment notification target not found');

    const recipientUserId = appointment.rows[0][`${config.recipient}_user_id`];
    await client.query(
        'SELECT pg_advisory_xact_lock(hashtext($1))',
        [`appointment-notification:${recipientUserId}:${appointmentId}:${config.type}`]
    );
    const inserted = await client.query(
        `INSERT INTO medorbit.notifications
            (user_id,title_ar,title_en,message_ar,message_en,
             notification_type,reference_id,reference_type,channel)
         SELECT $1::uuid,$2::varchar,$3::varchar,$4::text,$5::text,
                $6::varchar,$7::uuid,'APPOINTMENT','in_app'
         WHERE NOT EXISTS (
             SELECT 1 FROM medorbit.notifications
             WHERE user_id=$1
               AND notification_type=$6
               AND reference_id=$7
               AND reference_type='APPOINTMENT'
         )
         RETURNING id,user_id,notification_type,reference_id,reference_type,is_read`,
        [recipientUserId, config.titleAr, config.titleEn, config.messageAr,
            config.messageEn, config.type, appointmentId]
    );
    return inserted.rows[0] || null;
}

module.exports = { notifyDoctorApplicationReviewers, notifyAppointmentTransition };

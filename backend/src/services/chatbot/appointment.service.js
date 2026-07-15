const db = require('../../config/database');

class AppointmentService {

    async getAvailableSlots(doctorId) {

        const res = await db.query(`
            SELECT 
                id,
                day_of_week,
                start_time,
                end_time
            FROM doctor_availability
            WHERE doctor_id = $1
            AND is_active = true
            LIMIT 5
        `, [doctorId]);

        return res.rows;
    }

    async createAppointment({ doctorId, patientId }) {

        const res = await db.query(`
            INSERT INTO appointments (
                appointment_number,
                patient_id,
                doctor_id,
                scheduled_date,
                start_time,
                end_time,
                duration_minutes
            )
            VALUES (
                CONCAT('APT-', EXTRACT(EPOCH FROM NOW())),
                $1,
                $2,
                CURRENT_DATE,
                '10:00',
                '10:30',
                30
            )
            RETURNING id
        `, [patientId, doctorId]);

        return res.rows[0];
    }

    formatSlots(slots) {

        if (!slots.length) {
            return "❌ لا يوجد مواعيد متاحة حالياً.";
        }

        let txt = "🗓️ المواعيد المتاحة:\n\n";

        slots.forEach((s, i) => {
            txt += `${i + 1}. 🕐 ${s.start_time} - ${s.end_time}\n`;
        });

        return txt;
    }
}

module.exports = new AppointmentService();
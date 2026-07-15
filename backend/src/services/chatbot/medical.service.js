const db = require('../../config/database');

class MedicalService {

    async getMedications(names) {

        const res = await db.query(`
            SELECT id, name_en, known_interactions
            FROM medications
            WHERE LOWER(name_en) = ANY($1)
        `, [names.map(n => n.toLowerCase())]);

        return res.rows;
    }

    async getLatestRecord(patientId) {

        const res = await db.query(`
            SELECT diagnosis, symptoms, treatment_plan
            FROM medical_records
            WHERE patient_id = $1
            ORDER BY created_at DESC
            LIMIT 1
        `, [patientId]);

        return res.rows[0];
    }
}

module.exports = new MedicalService();
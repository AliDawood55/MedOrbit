const db = require('../../config/database');
const axios = require('axios');

const logger = require('../../utils/logger');

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

    /**
     * T-049: Auto-check drug interactions on prescription creation.
     * Calls the AI Service /prescription-check endpoint.
     * Fail-open: logs warnings but does NOT block prescription creation.
     *
     * @param {Array<{medication_name_en: string}>} items - Prescription items
     * @returns {Promise<{prescription_safe: boolean, warnings: string[]}>}
     */
    async checkPrescriptionInteractions(items) {
        try {
            const aiUrl = process.env.AI_SERVICE_URL || 'http://localhost:8001';
            const response = await axios.post(
                `${aiUrl}/prescription-check`,
                { prescription_items: items },
                { timeout: 5000 }
            );

            const result = response.data;

            if (result.warnings && result.warnings.length > 0) {
                logger.warn(
                    `[T-049] Prescription interaction warnings:\n${result.warnings.join('\n')}`
                );
            }

            if (!result.prescription_safe) {
                logger.warn('[T-049] Prescription flagged as UNSAFE by AI service');
            }

            return {
                prescription_safe: result.prescription_safe !== false,
                warnings: result.warnings || []
            };

        } catch (error) {
            // Fail-open: log the error but allow prescription creation
            logger.error(
                `[T-049] Failed to check prescription interactions: ${error.message || error}`
            );
            return {
                prescription_safe: true,
                warnings: []
            };
        }
    }
}

module.exports = new MedicalService();

const db = require('../../config/database');
const axios = require('axios');
const { internalIdentityHeaders } = require('../aiBoundary.service');

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
     * The result is deliberately advisory.  A clinician's submitted items are
     * never changed and an unavailable checker must never be represented as a
     * clear result.
     *
     * @returns {Promise<{status: 'clear'|'warning'|'unavailable', prescription_safe: boolean|null, warnings: string[], interactions: object[]}>}
     */
    async checkPrescriptionInteractions(items, userId) {
        try {
            const aiUrl = process.env.AI_SERVICE_URL || 'http://localhost:8001';
            const response = await axios.post(
                `${aiUrl}/prescription-check`,
                { prescription_items: items },
                { timeout: 5000, headers: internalIdentityHeaders({ userId }) }
            );

            const result = response.data;
            if (!result || typeof result !== 'object'
                || typeof result.prescription_safe !== 'boolean'
                || !Array.isArray(result.warnings)
                || !Array.isArray(result.interactions)) {
                throw new Error('AI prescription-check returned an invalid response');
            }

            const warnings = result.warnings.filter((warning) => typeof warning === 'string');
            const interactions = result.interactions.filter((interaction) => interaction && typeof interaction === 'object');

            if (warnings.length > 0) {
                logger.warn(
                    `[T-049] Prescription interaction warnings:\n${warnings.join('\n')}`
                );
            }

            if (!result.prescription_safe) {
                logger.warn('[T-049] Prescription flagged as UNSAFE by AI service');
            }

            return {
                status: warnings.length || result.prescription_safe === false ? 'warning' : 'clear',
                prescription_safe: result.prescription_safe,
                warnings,
                interactions,
            };

        } catch (error) {
            // Fail-open: log the error but allow prescription creation
            logger.error(
                `[T-049] Failed to check prescription interactions: ${error.message || error}`
            );
            return {
                status: 'unavailable',
                prescription_safe: null,
                warnings: [],
                interactions: [],
            };
        }
    }
}

module.exports = new MedicalService();

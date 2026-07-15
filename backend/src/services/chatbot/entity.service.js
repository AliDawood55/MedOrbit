const db = require('../../config/database');

class EntityService {

    async normalizeEntities(entities) {
        const result = { ...entities };

        if (entities.specialty) {
            const res = await db.query(
                `SELECT id, name_en FROM specialties
                 WHERE LOWER(name_en) LIKE $1 LIMIT 1`,
                [`%${entities.specialty}%`]
            );

            if (res.rows.length > 0) {
                result.specialty_id = res.rows[0].id;
            }
        }

        return result;
    }
}

module.exports = new EntityService();

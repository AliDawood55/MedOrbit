const db = require('../config/database');

/**
 * Clinic Repository
 * All SQL queries related to clinics, their types, locations, and services.
 * Uses PostGIS for spatial queries when available.
 */
class ClinicRepository {

    // ==================== LIST WITH FILTERS ====================

    async findAll({ region, service, insurance, search, type, page = 1, limit = 10 }) {
        let query = `
            SELECT 
                c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
                c.city, c.region, c.latitude, c.longitude, c.phone, c.email,
                c.website, c.operating_hours, c.services, c.insurance_accepted,
                c.type, c.logo_url, c.is_active, c.verification_status
            FROM medorbit.clinics c
            WHERE c.is_active = true
        `;

        const params = [];
        let paramIndex = 1;

        if (region) {
            query += ` AND c.region ILIKE $${paramIndex}`;
            params.push(`%${region}%`);
            paramIndex++;
        }

        if (service) {
            query += ` AND $${paramIndex} = ANY(c.services)`;
            params.push(service);
            paramIndex++;
        }

        if (insurance) {
            query += ` AND $${paramIndex} = ANY(c.insurance_accepted)`;
            params.push(insurance);
            paramIndex++;
        }

        if (type) {
            query += ` AND c.type = $${paramIndex}`;
            params.push(type);
            paramIndex++;
        }

        if (search) {
            query += ` AND (c.name_ar ILIKE $${paramIndex} OR c.name_en ILIKE $${paramIndex})`;
            params.push(`%${search}%`);
            paramIndex++;
        }

        // Count
        const countResult = await db.query(
            `SELECT COUNT(*) FROM (${query}) as count_query`,
            params
        );
        const total = parseInt(countResult.rows[0].count);

        query += ` ORDER BY c.name_en`;
        query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
        params.push(parseInt(limit), (parseInt(page) - 1) * parseInt(limit));

        const result = await db.query(query, params);

        return {
            clinics: result.rows,
            pagination: {
                page: parseInt(page),
                limit: parseInt(limit),
                total,
                totalPages: Math.ceil(total / parseInt(limit))
            }
        };
    }

    // ==================== NEARBY (PostGIS) ====================

    async findNearby({ userLat, userLng, type, radiusKm = 5, limit = 10 }) {
        let query = `
            SELECT
                c.id, c.name_ar, c.name_en, c.address_ar, c.address_en,
                c.phone, c.latitude, c.longitude, c.type, c.services,
                c.operating_hours, c.insurance_accepted, c.logo_url,
                NULL AS average_rating,
                ST_Distance(
                    ST_SetSRID(ST_MakePoint(c.longitude, c.latitude), 4326)::geography,
                    ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography
                ) AS distance_meters
            FROM medorbit.clinics c
            WHERE c.latitude IS NOT NULL
              AND c.longitude IS NOT NULL
              AND c.is_active = true
        `;

        const values = [userLng, userLat];
        let paramIndex = 3;

        if (type) {
            query += ` AND c.type = $${paramIndex}`;
            values.push(type);
            paramIndex++;
        }

        // Filter by radius if specified
        if (radiusKm > 0) {
            query += ` AND ST_DWithin(
                ST_SetSRID(ST_MakePoint(c.longitude, c.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography,
                $${paramIndex}
            )`;
            values.push(radiusKm * 1000); // Convert km to meters
            paramIndex++;
        }

        query += ` ORDER BY distance_meters ASC`;
        query += ` LIMIT $${paramIndex}`;
        values.push(limit);

        const result = await db.query(query, values);
        return result.rows;
    }

    // ==================== BY ID ====================

    async findById(id) {
        const result = await db.query(
            `SELECT * FROM medorbit.clinics WHERE id = $1 AND is_active = true`,
            [id]
        );
        return result.rows[0] || null;
    }

    // ==================== DOCTORS IN CLINIC ====================

    async findDoctorsByClinicId(clinicId) {
        const result = await db.query(
            `SELECT 
                d.id, d.years_of_experience, d.consultation_fee,
                d.average_rating, d.is_accepting_patients,
                p.first_name_ar, p.first_name_en, p.last_name_ar, p.last_name_en,
                p.profile_image_url,
                s.name_ar as specialty_ar, s.name_en as specialty_en
              FROM medorbit.doctor_clinic_assignments dca
              JOIN medorbit.doctors d ON d.id = dca.doctor_id
              JOIN medorbit.users u ON u.id = d.user_id
              LEFT JOIN medorbit.user_profiles p ON p.user_id = d.user_id
              LEFT JOIN medorbit.specialties s ON s.id = d.specialty_id
              WHERE dca.clinic_id = $1 AND dca.is_active = true AND u.is_active = true`,
            [clinicId]
        );
        return result.rows;
    }

    // ==================== TYPES ====================

    async findAllTypes() {
        const result = await db.query(
            `SELECT DISTINCT type, COUNT(*) as count 
             FROM medorbit.clinics 
             WHERE type IS NOT NULL AND is_active = true 
             GROUP BY type 
             ORDER BY type`
        );
        return result.rows;
    }

    // ==================== SERVICES ====================

    async findAllServices() {
        const result = await db.query(
            `SELECT DISTINCT unnest(services) as service 
             FROM medorbit.clinics 
             WHERE is_active = true 
             ORDER BY service`
        );
        return result.rows.map(r => r.service);
    }

    // ==================== SEARCH BY BOUNDING BOX ====================

    async findByBoundingBox({ south, west, north, east, type }) {
        let query = `
            SELECT 
                c.id, c.name_ar, c.name_en, c.latitude, c.longitude, c.type,
                c.phone, c.address_en
            FROM medorbit.clinics c
            WHERE c.is_active = true
              AND c.latitude BETWEEN $1 AND $2
              AND c.longitude BETWEEN $3 AND $4
        `;

        const params = [south, north, west, east];
        let paramIndex = 5;

        if (type) {
            query += ` AND c.type = $${paramIndex}`;
            params.push(type);
        }

        query += ` ORDER BY c.name_en`;

        const result = await db.query(query, params);
        return result.rows;
    }
}

module.exports = new ClinicRepository();
const path = require('path');
const { Pool } = require('pg');
const { createAudit } = require('../src/services/audit.service');

require('dotenv').config({ path: path.resolve(__dirname, '../../.env'), quiet: true });

const LIVE_DATABASE = 'medorbit';
const EXPECTED_DOCKER_SYSTEM_IDENTIFIER = '7666818136126230567';

function normalizeEmail(value) {
    const email = String(value || '').trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('SUPER_ADMIN_BOOTSTRAP_EMAIL must be a valid email');
    return email;
}

function assertEnvironment() {
    const testMode = process.env.MEDORBIT_BOOTSTRAP_TEST_MODE === 'true';
    const database = process.env.DB_NAME;
    if (process.env.DB_HOST !== 'postgres') throw new Error('Bootstrap refuses non-Docker DB_HOST values');
    if (testMode) {
        if (process.env.NODE_ENV !== 'test' || process.env.MEDORBIT_TEST_ISOLATION !== 'docker' || !String(database).endsWith('_test')) {
            throw new Error('Bootstrap test mode requires the isolated Docker *_test database');
        }
    } else if (database !== LIVE_DATABASE) {
        throw new Error('Bootstrap refuses any database other than medorbit');
    }
    const expected = process.env.MEDORBIT_EXPECTED_SYSTEM_IDENTIFIER || EXPECTED_DOCKER_SYSTEM_IDENTIFIER;
    return { testMode, expected };
}

async function run() {
    const email = normalizeEmail(process.env.SUPER_ADMIN_BOOTSTRAP_EMAIL);
    const { expected } = assertEnvironment();
    const pool = new Pool({ host: process.env.DB_HOST, port: Number(process.env.DB_PORT) || 5432, database: process.env.DB_NAME, user: process.env.DB_USER, password: String(process.env.DB_PASSWORD || ''), max: 1, options: '-c search_path=medorbit,public' });
    const client = await pool.connect();
    try {
        const identity = await client.query(`SELECT current_database() AS database, (pg_control_system()).system_identifier AS system_identifier`);
        if (identity.rows[0].system_identifier !== expected) throw new Error('Bootstrap refuses an unknown PostgreSQL system identifier');
        await client.query(`SELECT pg_advisory_lock(hashtext('medorbit:super_admin_bootstrap'))`);
        try {
            await client.query('BEGIN');
            const target = await client.query(`SELECT id,email,role,is_active,email_verified,deleted_at,authorization_version FROM medorbit.users WHERE lower(email)=lower($1) FOR UPDATE`, [email]);
            if (target.rows.length !== 1) throw new Error('Bootstrap target must resolve to exactly one user');
            const user = target.rows[0];
            if (!user.is_active || !user.email_verified || user.deleted_at) throw new Error('Bootstrap target must be active, verified, and not deleted');
            if (user.role === 'super_admin') {
                await client.query('COMMIT');
                console.log(JSON.stringify({ status: 'already_super_admin', userId: user.id, email: user.email, oldRole: user.role, newRole: user.role }));
                return;
            }
            if (user.role !== 'patient') throw new Error('Bootstrap target has an unexpected role');
            const updated = await client.query(`UPDATE medorbit.users SET role='super_admin', updated_at=NOW() WHERE id=$1 RETURNING id,email,role,authorization_version`, [user.id]);
            await client.query(`UPDATE medorbit.user_sessions SET revoked_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL`, [user.id]);
            await createAudit({ action: 'SUPER_ADMIN_BOOTSTRAPPED', entity_type: 'USER', entity_id: user.id, old_values: { id: user.id, email: user.email, role: user.role, authorization_version: user.authorization_version }, new_values: updated.rows[0] }, client);
            await client.query('COMMIT');
            console.log(JSON.stringify({ status: 'bootstrapped', userId: user.id, email: user.email, oldRole: user.role, newRole: updated.rows[0].role }));
        } catch (err) { await client.query('ROLLBACK').catch(() => {}); throw err; }
        finally { await client.query(`SELECT pg_advisory_unlock(hashtext('medorbit:super_admin_bootstrap'))`); }
    } finally { client.release(); await pool.end(); }
}

run().catch((err) => { console.error(err.message); process.exitCode = 1; });

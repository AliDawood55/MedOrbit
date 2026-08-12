const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

require('dotenv').config({
    path: path.resolve(__dirname, '../../.env'),
    quiet: true,
});

const MIGRATION_FILE_PATTERN = /^(\d{3,})_([a-z0-9_]+)\.sql$/;
const DEFAULT_MIGRATIONS_DIR = path.resolve(__dirname, '../migrations');
const LEDGER_TABLE = 'medorbit.schema_migrations';
const LOCK_KEY = 'medorbit:schema_migrations';

function checksum(contents) {
    // Git may materialize the same migration with CRLF on Windows and LF in
    // Linux containers. Normalize line endings for the ledger checksum only;
    // execute the original contents unchanged.
    const normalizedContents = contents.replace(/\r\n?/g, '\n');
    return crypto.createHash('sha256').update(normalizedContents).digest('hex');
}

function loadMigrations(migrationsDir = DEFAULT_MIGRATIONS_DIR) {
    const entries = fs.readdirSync(migrationsDir, { withFileTypes: true })
        .filter((entry) => entry.isFile() && entry.name.endsWith('.sql'))
        .map((entry) => {
            const match = entry.name.match(MIGRATION_FILE_PATTERN);
            if (!match) {
                throw new Error(`Invalid migration filename: ${entry.name}`);
            }
            const contents = fs.readFileSync(path.join(migrationsDir, entry.name), 'utf8');
            return {
                version: match[1],
                name: match[2],
                filename: entry.name,
                contents,
                checksum: checksum(contents),
            };
        })
        .sort((a, b) => a.version.localeCompare(b.version));

    const versions = new Set();
    for (const migration of entries) {
        if (versions.has(migration.version)) {
            throw new Error(`Duplicate migration version: ${migration.version}`);
        }
        versions.add(migration.version);
    }

    return entries;
}

function createPool() {
    return new Pool({
        host: process.env.DB_HOST,
        port: Number(process.env.DB_PORT) || 5432,
        database: process.env.DB_NAME,
        user: process.env.DB_USER,
        password: String(process.env.DB_PASSWORD || ''),
        max: 1,
        connectionTimeoutMillis: 5000,
        options: '-c search_path=medorbit,public',
    });
}

async function getIdentity(client) {
    const result = await client.query(
        `SELECT current_database() AS database,
                current_user AS database_user,
                current_setting('server_version') AS server_version,
                current_setting('data_directory') AS data_directory,
                (pg_control_system()).system_identifier AS system_identifier`
    );
    return result.rows[0];
}

async function ledgerExists(client) {
    const result = await client.query(`SELECT to_regclass($1) IS NOT NULL AS exists`, [LEDGER_TABLE]);
    return result.rows[0].exists;
}

async function ensureLedger(client) {
    await client.query('BEGIN');
    try {
        await client.query(`
            CREATE TABLE IF NOT EXISTS medorbit.schema_migrations (
                version VARCHAR(64) PRIMARY KEY,
                name VARCHAR(255) NOT NULL,
                checksum CHAR(64) NOT NULL,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            )
        `);
        await client.query('COMMIT');
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    }
}

async function readLedger(client) {
    if (!await ledgerExists(client)) return new Map();
    const result = await client.query(
        `SELECT version, name, checksum, applied_at
         FROM medorbit.schema_migrations
         ORDER BY version`
    );
    return new Map(result.rows.map((row) => [row.version, row]));
}

function buildStatus(migrations, applied) {
    return migrations.map((migration) => {
        const record = applied.get(migration.version);
        return {
            ...migration,
            state: !record ? 'pending' : record.checksum.trim() === migration.checksum ? 'applied' : 'checksum_mismatch',
            appliedAt: record?.applied_at || null,
        };
    });
}

function assertLedgerMatchesFiles(migrations, applied) {
    const fileVersions = new Set(migrations.map((migration) => migration.version));
    const missingFile = [...applied.keys()].find((version) => !fileVersions.has(version));
    if (missingFile) {
        throw new Error(`Applied migration ${missingFile} has no matching version-controlled file`);
    }
}

function printPlan(identity, status, command) {
    console.log(`Database: ${identity.database}`);
    console.log(`System identifier: ${identity.system_identifier}`);
    console.log(`Server: PostgreSQL ${identity.server_version}`);
    console.log(`Data directory: ${identity.data_directory}`);
    console.log(`Command: ${command}`);
    for (const migration of status) {
        console.log(`${migration.version} ${migration.name}: ${migration.state}`);
    }
    if (status.length === 0) console.log('No migration files found');
}

async function run({ command = 'status', migrationsDir = DEFAULT_MIGRATIONS_DIR, pool = createPool() } = {}) {
    if (!['up', 'status', 'dry-run'].includes(command)) {
        throw new Error(`Unknown migration command: ${command}`);
    }

    const migrations = loadMigrations(migrationsDir);
    const client = await pool.connect();
    try {
        const identity = await getIdentity(client);
        let applied = await readLedger(client);
        assertLedgerMatchesFiles(migrations, applied);
        let status = buildStatus(migrations, applied);
        printPlan(identity, status, command);

        const mismatch = status.find((migration) => migration.state === 'checksum_mismatch');
        if (mismatch) {
            throw new Error(`Checksum mismatch for applied migration ${mismatch.filename}`);
        }

        if (command !== 'up') return { identity, status };

        await client.query(`SELECT pg_advisory_lock(hashtext($1))`, [LOCK_KEY]);
        try {
            await ensureLedger(client);
            applied = await readLedger(client);
            assertLedgerMatchesFiles(migrations, applied);
            status = buildStatus(migrations, applied);

            const lockedMismatch = status.find((migration) => migration.state === 'checksum_mismatch');
            if (lockedMismatch) {
                throw new Error(`Checksum mismatch for applied migration ${lockedMismatch.filename}`);
            }

            for (const migration of status.filter((item) => item.state === 'pending')) {
                await client.query('BEGIN');
                try {
                    await client.query(migration.contents);
                    await client.query(
                        `INSERT INTO medorbit.schema_migrations (version, name, checksum)
                         VALUES ($1, $2, $3)`,
                        [migration.version, migration.name, migration.checksum]
                    );
                    await client.query('COMMIT');
                    console.log(`Applied ${migration.filename}`);
                } catch (error) {
                    await client.query('ROLLBACK');
                    throw new Error(`Migration ${migration.filename} failed and was rolled back: ${error.message}`);
                }
            }
        } finally {
            await client.query(`SELECT pg_advisory_unlock(hashtext($1))`, [LOCK_KEY]);
        }

        return { identity, status: buildStatus(migrations, await readLedger(client)) };
    } finally {
        client.release();
        await pool.end();
    }
}

if (require.main === module) {
    run({ command: process.argv[2] || 'status' }).catch((error) => {
        console.error(error.message);
        process.exitCode = 1;
    });
}

module.exports = {
    buildStatus,
    assertLedgerMatchesFiles,
    checksum,
    loadMigrations,
    run,
};

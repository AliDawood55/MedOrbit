const fs = require('fs');
const os = require('os');
const path = require('path');
const { Pool } = require('pg');
const { poolConfig } = require('./helpers/test-environment');
const { checksum, run } = require('../scripts/migrate');

const pool = new Pool(poolConfig);
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  PASS ${name}`);
    } else {
        failed += 1;
        console.error(`  FAIL ${name}${detail ? `: ${detail}` : ''}`);
    }
}

async function runTests() {
    const lfMigration = 'SELECT 1;\nSELECT 2;\n';
    const crlfMigration = lfMigration.replace(/\n/g, '\r\n');
    check(
        'migration checksum is stable across LF and CRLF',
        checksum(lfMigration) === checksum(crlfMigration)
    );

    const before = await pool.query(
        `SELECT version, checksum, applied_at
         FROM medorbit.schema_migrations
         WHERE version IN ('001','002','003')
         ORDER BY version`
    );
    check('migration ledger records all S1A versions', before.rows.length === 3);

    await run({ command: 'up' });
    await run({ command: 'up' });

    const after = await pool.query(
        `SELECT version, checksum, applied_at
         FROM medorbit.schema_migrations
         WHERE version IN ('001','002','003')
         ORDER BY version`
    );
    check('migration runner does not reapply', JSON.stringify(after.rows) === JSON.stringify(before.rows));
    check('migration checksums are recorded', after.rows.every((row) => /^[0-9a-f]{64}$/.test(row.checksum.trim())));

    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'medorbit-migration-test-'));
    const trackedMigrationsDir = path.resolve(__dirname, '../migrations');
    for (const filename of fs.readdirSync(trackedMigrationsDir).filter((name) => name.endsWith('.sql'))) {
        fs.copyFileSync(path.join(trackedMigrationsDir, filename), path.join(tempDir, filename));
    }
    fs.writeFileSync(
        path.join(tempDir, '999_transaction_rollback.sql'),
        `CREATE TABLE medorbit.s1a_migration_rollback_probe (id INTEGER PRIMARY KEY);\n` +
        `INSERT INTO medorbit.table_that_does_not_exist (id) VALUES (1);\n`,
        'utf8'
    );

    let failedAsExpected = false;
    try {
        await run({ command: 'up', migrationsDir: tempDir });
    } catch (err) {
        failedAsExpected = /failed and was rolled back/.test(err.message);
    } finally {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }

    const rollbackState = await pool.query(
        `SELECT to_regclass('medorbit.s1a_migration_rollback_probe') AS probe,
                EXISTS (
                    SELECT 1 FROM medorbit.schema_migrations WHERE version='999'
                ) AS ledger_recorded`
    );
    check('migration failure is reported', failedAsExpected);
    check(
        'failed migration rolls back schema and ledger',
        rollbackState.rows[0].probe === null && rollbackState.rows[0].ledger_recorded === false
    );

    await pool.end();
    console.log(`\nMigration tests: ${passed} passed; ${failed} failed`);
    process.exitCode = failed === 0 ? 0 : 1;
}

runTests().catch(async (err) => {
    console.error(err);
    await pool.end();
    process.exitCode = 1;
});

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const run = Date.now();
const ids = { users: [], reports: [], files: [] };
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) { passed++; console.log(`  ✓ ${name}`); }
    else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); }
}

function token(user, role) {
    return generateAccessToken({ sub: user, role, authorizationVersion: 1 });
}

async function request(method, route, accessToken, body) {
    const headers = accessToken ? { Authorization: `Bearer ${accessToken}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${route}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    return { status: response.status, body: await response.json() };
}

async function createUser(role) {
    const id = crypto.randomUUID();
    ids.users.push(id);
    await pool.query(
        `INSERT INTO medorbit.users
         (id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES ($1,$2,'test-only',$3,true,true,1)`,
        [id, `report_safety_${role}_${run}@medorbit.test`, role]
    );
    return id;
}

async function insertReport(userId, filePath, format = 'csv') {
    const result = await pool.query(
        `INSERT INTO medorbit.generated_reports
         (generated_by,report_title,report_type,report_data,format,file_path,generated_at)
         VALUES ($1,$2,'appointments','[]'::jsonb,$3,$4,NOW())
         RETURNING id`,
        [userId, `report safety ${run}`, format, filePath]
    );
    ids.reports.push(result.rows[0].id);
    return result.rows[0].id;
}

(async () => {
    try {
        check('test isolation targets medorbit_test', poolConfig.database === 'medorbit_test');
        const admin = await createUser('admin');
        const patient = await createUser('patient');
        const adminToken = token(admin, 'admin');
        const patientToken = token(patient, 'patient');

        check('unauthenticated report generation is denied',
            (await request('POST', '/reports', null, { type: 'appointments' })).status === 401);
        check('patient report generation is denied',
            (await request('POST', '/reports', patientToken, { type: 'appointments' })).status === 403);
        check('unsupported report type is rejected before querying data',
            (await request('POST', '/reports', adminToken, { type: 'users', format: 'json' })).status === 400);
        check('unsupported report format is rejected',
            (await request('POST', '/reports', adminToken, { type: 'appointments', format: 'exe' })).status === 400);

        const generated = await request('POST', '/reports', adminToken, { type: 'appointments', format: 'json' });
        check('admin can generate an allowed JSON report', generated.status === 201, JSON.stringify(generated.body));

        const reportsDirectory = path.join(process.cwd(), 'storage', 'reports');
        fs.mkdirSync(reportsDirectory, { recursive: true });
        const safePath = path.join(reportsDirectory, `report-safety-${run}.csv`);
        fs.writeFileSync(safePath, 'safe,report\n1,ok\n');
        ids.files.push(safePath);
        const safeReportId = await insertReport(admin, safePath);
        const safeDownload = await fetch(`${apiBase}/reports/${safeReportId}/download`, {
            headers: { Authorization: `Bearer ${adminToken}` },
        });
        check('admin can download a report stored inside the report directory',
            safeDownload.status === 200 && (await safeDownload.text()).includes('safe,report'));
        check('patient cannot download an admin report',
            (await request('GET', `/reports/${safeReportId}/download`, patientToken)).status === 403);

        const unsafeReportId = await insertReport(admin, '/etc/passwd');
        const unsafeDownload = await request('GET', `/reports/${unsafeReportId}/download`, adminToken);
        check('stored paths outside the report directory are refused',
            unsafeDownload.status === 404 && unsafeDownload.body?.error?.code === 'REPORT_FILE_UNAVAILABLE', JSON.stringify(unsafeDownload.body));
    } catch (error) {
        failed++;
        console.error(error.stack || error.message);
    } finally {
        for (const file of ids.files) fs.rmSync(file, { force: true });
        if (ids.users.length) await pool.query('DELETE FROM medorbit.generated_reports WHERE generated_by=ANY($1::uuid[])', [ids.users]);
        if (ids.users.length) await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [ids.users]);
        await pool.end();
        console.log(`\nReport safety: ${passed} passed, ${failed} failed`);
        process.exitCode = failed ? 1 : 0;
    }
})();

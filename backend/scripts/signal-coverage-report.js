const fs = require('fs');
const path = require('path');
const env = require('../src/config/env');
const db = require('../src/config/database');
const { ALLOWED_SIGNALS } = require('../src/services/recommendationPolicy.service');

const ROOT = path.resolve(__dirname, '..');
const SIGNAL_PATHS = Object.freeze({
    post_view: {
        frontendFile: 'frontend/src/js/feed.js', frontendToken: 'API.social.view(', frontendActivated: true,
        backendFile: 'src/routes/social.routes.js', backendToken: "eventType:'post_view'", routeToken: "feedRoutes.post('/posts/:id/view'",
        endpoint: 'POST /api/feed/posts/:id/view', entityType: 'doctor_post', metadata: [], projection: ['post_category', 'specialty'],
    },
    post_like: {
        frontendFile: 'frontend/src/js/feed.js', frontendToken: 'API.social.like(', frontendActivated: true,
        backendFile: 'src/routes/social.routes.js', backendToken: "eventType:'post_like'", routeToken: "feedRoutes.post('/posts/:id/like'",
        endpoint: 'POST /api/feed/posts/:id/like', entityType: 'doctor_post', metadata: [], projection: ['post_category', 'specialty'],
    },
    post_unlike: {
        frontendFile: 'frontend/src/js/feed.js', frontendToken: 'API.social.unlike(', frontendActivated: true,
        backendFile: 'src/routes/social.routes.js', backendToken: "eventType:'post_unlike'", routeToken: "feedRoutes.delete('/posts/:id/like'",
        endpoint: 'DELETE /api/feed/posts/:id/like', entityType: 'doctor_post', metadata: [], projection: ['post_category', 'specialty'],
    },
    post_comment: {
        frontendFile: 'frontend/src/js/feed.js', frontendToken: 'API.social.addComment(', frontendActivated: true,
        backendFile: 'src/routes/social.routes.js', backendToken: "eventType:'post_comment'", routeToken: "feedRoutes.post('/posts/:id/comments'",
        endpoint: 'POST /api/feed/posts/:id/comments', entityType: 'doctor_post', metadata: ['comment_id'], projection: ['post_category', 'specialty'],
    },
    doctor_profile_view: {
        frontendFile: 'frontend/src/js/doctor.js', frontendToken: 'API.social.doctorView(', frontendActivated: true,
        backendFile: 'src/routes/social.routes.js', backendToken: "eventType:'doctor_profile_view'", routeToken: "socialDoctorRoutes.post('/:id/view'",
        endpoint: 'POST /api/doctors/:id/view', entityType: 'doctor', metadata: [], projection: ['specialty'],
    },
    doctor_follow: {
        frontendFile: 'frontend/src/js/doctor.js', frontendToken: 'API.social.follow(', frontendActivated: true,
        backendFile: 'src/routes/social.routes.js', backendToken: "eventType:'doctor_follow'", routeToken: "socialDoctorRoutes.post('/:id/follow'",
        endpoint: 'POST /api/doctors/:id/follow', entityType: 'doctor', metadata: [], projection: ['specialty'],
    },
    doctor_unfollow: {
        frontendFile: 'frontend/src/js/doctor.js', frontendToken: 'API.social.unfollow(', frontendActivated: true,
        backendFile: 'src/routes/social.routes.js', backendToken: "eventType:'doctor_unfollow'", routeToken: "socialDoctorRoutes.delete('/:id/follow'",
        endpoint: 'DELETE /api/doctors/:id/follow', entityType: 'doctor', metadata: [], projection: ['specialty'],
    },
    search_specialty: {
        frontendFile: 'frontend/src/js/find-doctors.js', frontendToken: 'API.social.specialtySearch(', frontendActivated: true,
        backendFile: 'src/routes/recommendation.routes.js', backendToken: "eventType:'search_specialty'", routeToken: "router.post('/specialties/:id/search'",
        endpoint: 'POST /api/recommendations/specialties/:id/search', entityType: 'specialty', metadata: ['specialty_id'], projection: ['specialty'],
    },
});

function read(relativePath, workspaceRoot) {
    try { return fs.readFileSync(path.join(workspaceRoot, relativePath), 'utf8'); } catch { return ''; }
}

function inspectProductionCoverage(backendRoot = ROOT) {
    const outboxSource = read('src/services/userEvent.service.js', backendRoot);
    const testSource = read('tests/s8-6-signal-activation.test.js', backendRoot);
    return Object.entries(SIGNAL_PATHS).map(([signal, pathSpec]) => {
        const backendSource = read(pathSpec.backendFile, backendRoot);
        return {
            signal,
            frontendTrigger: pathSpec.frontendFile,
            backendEndpoint: pathSpec.endpoint,
            entityType: pathSpec.entityType,
            metadata: pathSpec.metadata,
            outboxEmitted: outboxSource.includes("eventType:'user.interaction.recorded'"),
            projectionDimension: pathSpec.projection,
            productionEmitterPresent: backendSource.includes(pathSpec.backendToken),
            frontendTriggerPresent: pathSpec.frontendActivated === true,
            backendRoutePresent: backendSource.includes(pathSpec.routeToken),
            testCoveragePresent: testSource.includes(signal),
        };
    });
}

async function collectSignalCoverage(pool = db.pool, workspaceRoot) {
    const client = await pool.connect();
    try {
        await client.query('BEGIN TRANSACTION READ ONLY');
        const identity = (await client.query(
            'SELECT current_database() database,system_identifier::text system_identifier FROM pg_control_system()'
        )).rows[0];
        const counts = (await client.query(
            `SELECT event_type,count(*)::int count FROM medorbit.user_events
             WHERE event_type=ANY($1::varchar[]) GROUP BY event_type`,
            [Object.keys(ALLOWED_SIGNALS)]
        )).rows;
        await client.query('COMMIT');
        const countBySignal = new Map(counts.map(row => [row.event_type, Number(row.count)]));
        const signals = inspectProductionCoverage(workspaceRoot)
            .map(row => ({ ...row, liveCount: countBySignal.get(row.signal) || 0 }));
        return {
            database: identity.database,
            systemIdentifier: identity.system_identifier,
            generatedAt: new Date().toISOString(),
            signals,
            allActivated: signals.every(row => row.productionEmitterPresent && row.frontendTriggerPresent && row.backendRoutePresent && row.outboxEmitted && row.testCoveragePresent),
        };
    } catch (error) {
        await client.query('ROLLBACK').catch(() => {});
        throw error;
    } finally { client.release(); }
}

function assertConfiguredTarget() {
    if (env.app.environment === 'test') {
        if (process.env.MEDORBIT_TEST_ISOLATION !== 'docker' || env.database.host !== 'postgres' || !env.database.name.endsWith('_test')) {
            throw new Error('Refusing signal coverage test report outside isolated Docker test database');
        }
        return;
    }
    if (env.database.host !== 'postgres' || env.database.name !== 'medorbit') {
        throw new Error('Refusing signal coverage report outside authoritative Docker medorbit database');
    }
    if (!process.env.SIGNAL_COVERAGE_EXPECTED_SYSTEM_IDENTIFIER) {
        throw new Error('SIGNAL_COVERAGE_EXPECTED_SYSTEM_IDENTIFIER is required');
    }
}

async function main() {
    assertConfiguredTarget();
    const report = await collectSignalCoverage();
    const expected = process.env.SIGNAL_COVERAGE_EXPECTED_SYSTEM_IDENTIFIER;
    if (expected && report.systemIdentifier !== expected) throw new Error('PostgreSQL system identifier mismatch');
    console.log(JSON.stringify(report));
}

if (require.main === module) {
    main().catch(error => { console.error(`Signal coverage failed: ${String(error.message || error).slice(0, 300)}`); process.exitCode = 1; })
        .finally(() => db.pool.end());
}

module.exports = { SIGNAL_PATHS, inspectProductionCoverage, collectSignalCoverage, assertConfiguredTarget };

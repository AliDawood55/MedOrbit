const http = require('http');
const { Pool } = require('pg');
const { poolConfig } = require('./test-environment');
const { getInternalToken } = require('../../src/services/aiBoundary.service');

const pool = new Pool(poolConfig);

function send(res, status, body) {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
}

function readJson(req) {
    return new Promise((resolve, reject) => {
        let data = '';
        req.on('data', (chunk) => { data += chunk; });
        req.on('end', () => {
            try { resolve(data ? JSON.parse(data) : {}); } catch (err) { reject(err); }
        });
        req.on('error', reject);
    });
}

const server = http.createServer(async (req, res) => {
    try {
        if (req.method === 'GET' && req.url === '/health') return send(res, 200, { status: 'healthy' });
        if (req.method === 'POST' && req.url === '/drug-interactions') {
            const body = await readJson(req);
            const userId = req.headers['x-medorbit-user-id'] || null;
            const suppliedToken = req.headers['x-medorbit-internal-token'] || null;
            if (!userId || suppliedToken !== getInternalToken()) {
                return send(res, 403, { detail: 'Internal identity context is required' });
            }
            if ((body.medication_names || []).includes('__UPSTREAM_FAIL__')) {
                return send(res, 503, { detail: 'Simulated AI outage' });
            }
            return send(res, 200, { has_interactions: false, interaction_count: 0, interactions: [], severity_summary: {} });
        }
        if (req.method === 'POST' && req.url === '/triage') {
            const body = await readJson(req);
            if (body.user_id || body.record_id) return send(res, 403, { detail: 'Client-supplied identity is not accepted' });

            const userId = req.headers['x-medorbit-user-id'] || null;
            const suppliedToken = req.headers['x-medorbit-internal-token'] || null;
            if (!userId || suppliedToken !== getInternalToken()) {
                return send(res, 403, { detail: 'Internal identity context is required' });
            }
            const inserted = await pool.query(
                `INSERT INTO medorbit.symptom_triage_sessions
                   (user_id,session_id,reported_symptoms,triage_level,confidence_score,recommendations,follow_up_action)
                 VALUES ($1,$2,$3,'routine',0.5,'test recommendation','monitor')
                 RETURNING id`,
                [userId, body.session_id || `stub-${Date.now()}`, JSON.stringify({ symptoms: body.symptoms || [] })]
            );
            return send(res, 200, {
                id: inserted.rows[0].id,
                symptoms: body.symptoms || [],
                triage_level: 'routine',
                recommended_specialty_id: null,
                recommended_specialty_name_en: null,
                recommended_specialty_name_ar: null,
                confidence_score: 0.5,
                specialty_scores: {},
                matched_keywords: [],
                recommendations: 'test recommendation',
                follow_up_action: 'monitor',
            });
        }
        // Chatbot. Minimal but successful, because a FAILED AI call
        // deliberately releases its quota reservation — so without a working
        // stub here every quota test would measure the release path instead of
        // the consume path.
        if (req.method === 'POST' && req.url === '/chat') {
            const body = await readJson(req);
            const userId = req.headers['x-medorbit-user-id'] || null;
            const suppliedToken = req.headers['x-medorbit-internal-token'] || null;
            if (!userId || suppliedToken !== getInternalToken()) {
                return send(res, 403, { detail: 'Internal identity context is required' });
            }
            // Sentinel for the failure path. A real AI outage is what the
            // release-on-failure logic exists for, and it cannot be exercised
            // through a stub that always succeeds.
            if (String(body.message || '').includes('__AI_FAIL__')) {
                return send(res, 503, { detail: 'Simulated AI outage' });
            }
            return send(res, 200, {
                reply: `stub reply to: ${String(body.message || '').slice(0, 60)}`,
                intent: 'general',
                confidence: 0.9,
                entities: {},
            });
        }

        // ---------------------------------------------------------------
        // Virtual Doctor.
        //
        // Mirrors the real router's trust boundary rather than just its happy
        // path: it refuses a request with no internal credential and refuses a
        // client-supplied identity, so the backend tests exercise the same
        // failure modes the Python service enforces.
        // ---------------------------------------------------------------
        if (req.url.startsWith('/virtual-doctor')) {
            const suppliedToken = req.headers['x-medorbit-internal-token'] || null;
            const userId = req.headers['x-medorbit-user-id'] || null;
            if (!userId || suppliedToken !== getInternalToken()) {
                return send(res, 403, { detail: 'Internal identity context is required' });
            }

            if (req.method === 'POST' && req.url === '/virtual-doctor/start') {
                const body = await readJson(req);
                if (body.user_id) return send(res, 403, { detail: 'Client-supplied identity is not accepted' });
                const language = body.language === 'ar' ? 'ar' : 'en';
                const sessionId = `vd-test-${Date.now()}-${Math.random().toString(16).slice(2, 8)}`;
                const inserted = await pool.query(
                    `INSERT INTO medorbit.virtual_doctor_sessions (user_id, session_id, language, phase)
                     VALUES ($1,$2,$3,'intake') RETURNING id`,
                    [userId, sessionId, language]
                );
                return send(res, 200, {
                    session_id: sessionId,
                    reply: 'Hello, what is your name?',
                    phase: 'intake',
                    language,
                    _row_id: inserted.rows[0].id,
                });
            }

            if (req.method === 'POST' && req.url === '/virtual-doctor/message') {
                const body = await readJson(req);
                // Ownership is part of the lookup, exactly as in the real engine.
                const owned = await pool.query(
                    `SELECT id FROM medorbit.virtual_doctor_sessions
                      WHERE session_id = $1 AND user_id = $2`,
                    [body.session_id, userId]
                );
                if (owned.rows.length !== 1) return send(res, 404, { detail: 'Session not found' });

                // A message containing "finish" drives the consultation to its
                // terminal phase, so tests can exercise completion + cooldown.
                const phase = /finish/i.test(body.message || '') ? 'complete' : 'interviewing';
                return send(res, 200, {
                    session_id: body.session_id,
                    reply: 'Understood.',
                    phase,
                    urgency_level: phase === 'complete' ? 'routine' : null,
                    profile_snapshot: {},
                });
            }

            const sessionMatch = req.url.match(/^\/virtual-doctor\/session\/([^/?]+)$/);
            if (req.method === 'GET' && sessionMatch) {
                const owned = await pool.query(
                    `SELECT session_id, language, phase FROM medorbit.virtual_doctor_sessions
                      WHERE session_id = $1 AND user_id = $2`,
                    [decodeURIComponent(sessionMatch[1]), userId]
                );
                if (owned.rows.length !== 1) return send(res, 404, { detail: 'Session not found' });
                return send(res, 200, {
                    session_id: owned.rows[0].session_id,
                    reply: 'Resumed.',
                    phase: owned.rows[0].phase,
                    language: owned.rows[0].language,
                    messages: [],
                });
            }

            const reportMatch = req.url.match(/^\/virtual-doctor\/report\/([^/?]+)$/);
            if (req.method === 'POST' && reportMatch) {
                const sessionId = decodeURIComponent(reportMatch[1]);
                const owned = await pool.query(
                    `SELECT id FROM medorbit.virtual_doctor_sessions
                      WHERE session_id = $1 AND user_id = $2`,
                    [sessionId, userId]
                );
                if (owned.rows.length !== 1) return send(res, 404, { detail: 'Session not found' });
                const report = await pool.query(
                    `INSERT INTO medorbit.virtual_doctor_reports (session_id, pdf_path, report_json)
                     VALUES ($1,'/tmp/test.pdf','{}'::jsonb) RETURNING id`,
                    [owned.rows[0].id]
                );
                return send(res, 200, {
                    report_id: report.rows[0].id,
                    session_id: sessionId,
                    urgency_level: 'routine',
                    recommended_specialty_name_en: null,
                    recommended_specialty_name_ar: null,
                    download_url: `/virtual-doctor/report/${report.rows[0].id}/download`,
                });
            }

            // Report download. Ownership is re-checked here, exactly as the
            // real service does, so a report id alone is never a bearer token
            // for someone else's medical document.
            const downloadMatch = req.url.match(/^\/virtual-doctor\/report\/([^/?]+)\/download$/);
            if (req.method === 'GET' && downloadMatch) {
                const owned = await pool.query(
                    `SELECT r.id FROM medorbit.virtual_doctor_reports r
                       JOIN medorbit.virtual_doctor_sessions s ON s.id = r.session_id
                      WHERE r.id = $1 AND s.user_id = $2`,
                    [decodeURIComponent(downloadMatch[1]), userId]
                );
                if (owned.rows.length !== 1) return send(res, 404, { detail: 'Report not found' });
                const pdf = Buffer.from('%PDF-1.4 test-stub-report %%EOF', 'utf8');
                res.writeHead(200, { 'Content-Type': 'application/pdf', 'Content-Length': pdf.length });
                return res.end(pdf);
            }

            if (req.url.includes('/warmup') || req.url.includes('/status')) {
                return send(res, 200, { loaded: true, model: 'test-stub' });
            }

            return send(res, 404, { detail: 'Not found' });
        }

        return send(res, 404, { detail: 'Not found' });
    } catch (err) {
        console.error('AI test stub error:', err.message);
        return send(res, 500, { detail: 'Test stub failure' });
    }
});

server.listen(8001, '0.0.0.0', () => console.log('AI test stub listening on 8001'));

async function shutdown() {
    server.close(async () => {
        await pool.end();
        process.exit(0);
    });
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

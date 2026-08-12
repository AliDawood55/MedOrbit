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
            return send(res, 200, { has_interactions: false, interaction_count: 0, interactions: [], severity_summary: {} });
        }
        if (req.method === 'POST' && req.url === '/triage') {
            const body = await readJson(req);
            if (body.user_id || body.record_id) return send(res, 403, { detail: 'Client-supplied identity is not accepted' });

            const userId = req.headers['x-medorbit-user-id'] || null;
            const suppliedToken = req.headers['x-medorbit-internal-token'] || null;
            if (userId && suppliedToken !== getInternalToken()) {
                return send(res, 403, { detail: 'Invalid internal identity context' });
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

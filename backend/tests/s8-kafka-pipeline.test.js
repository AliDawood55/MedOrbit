const crypto = require('crypto');
const http = require('http');
const { spawn } = require('child_process');

const runId = `${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
const topic = `medorbit.s8-test.${runId}`;
const group = `recommendation-profile-v1-test-${runId}`;

// Override the backend-test container's Kafka-disabled defaults BEFORE loading app modules.
process.env.KAFKA_ENABLED = 'true';
process.env.KAFKA_BROKERS = process.env.KAFKA_BROKERS || 'kafka:9092';
process.env.KAFKA_OUTBOX_TOPIC = topic;
process.env.KAFKA_RECOMMENDATION_CONSUMER_GROUP = group;
process.env.OUTBOX_POLL_INTERVAL_MS = '250';

const { Pool } = require('pg');
const { poolConfig } = require('./helpers/test-environment');
const { createKafka, ensureTopics } = require('../src/events/kafkaClient');
const { recordUserEvent } = require('../src/services/userEvent.service');

const pool = new Pool(poolConfig);
const kafka = createKafka(`medorbit-s8-pipeline-test-${runId}`);

const ids = {
  user: crypto.randomUUID(),
  patient: crypto.randomUUID(),
  doctorUser: crypto.randomUUID(),
  doctor: crypto.randomUUID(),
  specialty: crypto.randomUUID(),
  post: crypto.randomUUID(),
};

let outboxId = null;
const children = [];

function wait(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }

async function eventually(fn, { timeoutMs = 15000, intervalMs = 250, label = 'condition' } = {}) {
  const deadline = Date.now() + timeoutMs;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const value = await fn();
      if (value) return value;
    } catch (error) { lastError = error; }
    await wait(intervalMs);
  }
  throw new Error(`Timed out waiting for ${label}${lastError ? `: ${lastError.message}` : ''}`);
}

function health(port) {
  return new Promise((resolve) => {
    const req = http.get({ host: '127.0.0.1', port, path: '/health', timeout: 1000 }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => resolve(res.statusCode === 200 ? body : null));
    });
    req.on('timeout', () => { req.destroy(); resolve(null); });
    req.on('error', () => resolve(null));
  });
}

function startWorker(script, healthPort, extraEnv = {}) {
  const logs = [];
  const child = spawn(process.execPath, [script], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      NODE_ENV: 'test',
      MEDORBIT_TEST_ISOLATION: 'docker',
      DB_HOST: 'postgres',
      DB_NAME: 'medorbit_test',
      KAFKA_ENABLED: 'true',
      KAFKA_BROKERS: 'kafka:9092',
      KAFKA_OUTBOX_TOPIC: topic,
      KAFKA_RECOMMENDATION_CONSUMER_GROUP: group,
      WORKER_HEALTH_PORT: String(healthPort),
      ...extraEnv,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  for (const stream of [child.stdout, child.stderr]) {
    stream.on('data', (chunk) => {
      logs.push(chunk.toString('utf8'));
      if (logs.length > 20) logs.shift();
    });
  }
  child._recentLogs = logs;
  children.push(child);
  return child;
}

async function stopChildren() {
  await Promise.all(children.map(async (child) => {
    if (child.exitCode !== null) return;
    child.kill('SIGTERM');
    await Promise.race([
      new Promise((resolve) => child.once('exit', resolve)),
      wait(3000).then(() => { if (child.exitCode === null) child.kill('SIGKILL'); }),
    ]);
  }));
}

async function createFixtures() {
  await pool.query(`INSERT INTO medorbit.specialties(id,name_ar,name_en,is_active)
                    VALUES($1,$2,$3,true)`, [ids.specialty, `تخصص S8 ${runId}`, `S8 ${runId}`]);

  await pool.query(`INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version)
                    VALUES($1,$2,'s8-kafka-test','patient',true,true,1)`,
  [ids.user, `s8_kafka_${runId}@medorbit.test`]);
  await pool.query(`INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
                    VALUES($1,'اختبار','كافكا','Kafka','Test')`, [ids.user]);
  await pool.query(`INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)`, [ids.patient, ids.user]);

  await pool.query(`INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version)
                    VALUES($1,$2,'s8-kafka-test','doctor',true,true,1)`,
  [ids.doctorUser, `s8_kafka_doctor_${runId}@medorbit.test`]);
  await pool.query(`INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
                    VALUES($1,'طبيب','اختبار','Doctor','Test')`, [ids.doctorUser]);
  await pool.query(`INSERT INTO medorbit.doctors(id,user_id,medical_license_number,specialty_id,approval_status,approved_at)
                    VALUES($1,$2,$3,$4,'approved',NOW())`,
  [ids.doctor, ids.doctorUser, `S8-KAFKA-${runId}`, ids.specialty]);

  await pool.query(`INSERT INTO medorbit.doctor_posts
                    (id,doctor_id,title_en,body,category,is_published,status,moderation_status,published_at)
                    VALUES($1,$2,'S8 Kafka pipeline','safe public body','health_tip',true,'published','approved',NOW())`,
  [ids.post, ids.doctor]);
}

async function createInteraction() {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const like = (await client.query(
      `INSERT INTO medorbit.post_likes(post_id,user_id) VALUES($1,$2) RETURNING id`,
      [ids.post, ids.user]
    )).rows[0];
    if (!like?.id) throw new Error('Expected social like mutation');
    const event = await recordUserEvent({
      userId: ids.user,
      eventType: 'post_like',
      entityType: 'doctor_post',
      entityId: ids.post,
    }, client);
    await client.query('COMMIT');
    if (!event?.id) throw new Error('Expected user event to be recorded');
    const outbox = (await pool.query(
      `SELECT id,kafka_topic,status FROM medorbit.outbox_events
       WHERE aggregate_type='user_event' AND aggregate_id=$1`, [event.id]
    )).rows[0];
    if (!outbox) throw new Error('Expected transactional outbox row');
    if (outbox.kafka_topic !== topic) throw new Error(`Unexpected outbox topic: ${outbox.kafka_topic}`);
    outboxId = outbox.id;
    return event.id;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

async function cleanup() {
  if (outboxId) {
    await pool.query(`DELETE FROM medorbit.processed_events
                      WHERE consumer_name=$1 AND event_id=$2`, [group.replace(/-test-.+$/, ''), outboxId]).catch(() => {});
    // Actual consumer name is fixed in projection service, not Kafka group.
    await pool.query(`DELETE FROM medorbit.processed_events
                      WHERE consumer_name='recommendation-profile-v1' AND event_id=$1`, [outboxId]).catch(() => {});
  }
  await pool.query(`DELETE FROM medorbit.user_interest_profiles WHERE user_id=$1`, [ids.user]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.outbox_events WHERE aggregate_type='user_event' AND aggregate_id IN
                    (SELECT id FROM medorbit.user_events WHERE user_id=$1)`, [ids.user]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.user_events WHERE user_id=$1`, [ids.user]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.post_likes WHERE post_id=$1`, [ids.post]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.doctor_posts WHERE id=$1`, [ids.post]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.doctors WHERE id=$1`, [ids.doctor]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.patients WHERE id=$1`, [ids.patient]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.user_profiles WHERE user_id IN($1,$2)`, [ids.user, ids.doctorUser]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.users WHERE id IN($1,$2)`, [ids.user, ids.doctorUser]).catch(() => {});
  await pool.query(`DELETE FROM medorbit.specialties WHERE id=$1`, [ids.specialty]).catch(() => {});
}

async function deleteTopic() {
  const admin = kafka.admin();
  try {
    await admin.connect();
    await admin.deleteTopics({ topics: [topic], timeout: 5000 }).catch(() => {});
  } finally { await admin.disconnect().catch(() => {}); }
}

(async () => {
  let failed = false;
  try {
    const identity = (await pool.query('SELECT current_database() db')).rows[0];
    if (identity.db !== 'medorbit_test') throw new Error(`Unsafe DB target: ${identity.db}`);

    await ensureTopics(kafka, [topic]);

    const consumer = startWorker('scripts/recommendation-consumer.js', 3004);
    await eventually(() => health(3004), { label: 'recommendation consumer health' });
    if (consumer.exitCode !== null) throw new Error(`Recommendation consumer exited early: ${consumer._recentLogs.join('')}`);

    const publisher = startWorker('scripts/outbox-worker.js', 3002);
    await eventually(() => health(3002), { label: 'outbox worker health' });
    if (publisher.exitCode !== null) throw new Error(`Outbox worker exited early: ${publisher._recentLogs.join('')}`);

    await createFixtures();
    const userEventId = await createInteraction();

    const published = await eventually(async () => {
      const row = (await pool.query(`SELECT status FROM medorbit.outbox_events WHERE id=$1`, [outboxId])).rows[0];
      return row?.status === 'published' ? row : null;
    }, { label: 'outbox publish' });

    const profileRows = await eventually(async () => {
      const rows = (await pool.query(
        `SELECT interest_type,interest_key,score::float score,interaction_count
         FROM medorbit.user_interest_profiles WHERE user_id=$1 ORDER BY interest_type,interest_key`, [ids.user]
      )).rows;
      return rows.length >= 2 ? rows : null;
    }, { label: 'recommendation profile projection' });

    const markerCount = Number((await pool.query(
      `SELECT count(*) FROM medorbit.processed_events
       WHERE consumer_name='recommendation-profile-v1' AND event_id=$1`, [outboxId]
    )).rows[0].count);

    if (markerCount !== 1) throw new Error(`Expected one processed_events marker, found ${markerCount}`);
    if (profileRows.some((row) => row.score !== 3 || row.interaction_count !== 1)) {
      throw new Error(`Unexpected projection rows: ${JSON.stringify(profileRows)}`);
    }

    console.log('S8 Kafka pipeline: PASS');
    console.log(JSON.stringify({
      database: identity.db,
      topic,
      userEventId,
      outboxStatus: published.status,
      processedMarkers: markerCount,
      profileRows: profileRows.length,
    }));
  } catch (error) {
    failed = true;
    console.error(`S8 Kafka pipeline: FAIL — ${error.message}`);
    for (const child of children) {
      if (child._recentLogs?.length) console.error(child._recentLogs.join('').slice(-2000));
    }
  } finally {
    await stopChildren();
    await cleanup().catch((error) => { failed = true; console.error(`Cleanup failed: ${error.message}`); });
    await deleteTopic().catch(() => {});
    await pool.end().catch(() => {});
  }
  if (failed) process.exitCode = 1;
})();

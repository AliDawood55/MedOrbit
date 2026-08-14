const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const run = Date.now();
let passed = 0; let failed = 0;
const ids = {};
function check(name, ok, detail = '') { if (ok) { passed++; console.log(`  ✓ ${name}`); } else { failed++; console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`); } }
function jwt(id, role, version = 1) { return generateAccessToken({ sub: id, role, authorizationVersion: version }); }
async function request(method, route, token, body) { const headers = token ? { Authorization: `Bearer ${token}` } : {}; if (body !== undefined) headers['Content-Type'] = 'application/json'; const r = await fetch(`${apiBase}${route}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }); return { status: r.status, body: await r.json() }; }
async function user(key, role) { ids[key] = crypto.randomUUID(); await pool.query(`INSERT INTO medorbit.users (id,email,password_hash,role,is_active,email_verified,authorization_version,deleted_at) VALUES ($1,$2,'test-only',$3,true,true,1,NULL)`, [ids[key], `analytics_${key}_${run}@medorbit.test`, role]); return ids[key]; }

// Every /api/dashboard/stats analytics.* section must be either
// { data: { labels: [...], counts: [...] } } or { data: { items: [...] } }
// (topSpecialties) or { error: true } — never a thrown exception, never a
// negative count.
function checkSection(name, section) {
  if (section && section.error === true) {
    check(`${name} — error-shaped section is well-formed`, Object.keys(section).length === 1);
    return;
  }
  check(`${name} — section present`, !!section && !!section.data);
  if (!section?.data) return;
  const counts = section.data.counts || (section.data.items || []).map((i) => i.count);
  check(`${name} — counts is an array`, Array.isArray(counts));
  check(`${name} — all counts are non-negative integers`, counts.every((n) => Number.isInteger(n) && n >= 0));
  if (section.data.labels) {
    check(`${name} — labels/counts same length`, section.data.labels.length === counts.length);
  }
}

(async () => {
  try {
    await user('admin', 'admin');
    await user('super', 'super_admin');
    await user('doctor', 'doctor');
    await user('patient', 'patient');

    const adminToken = jwt(ids.admin, 'admin');
    const superToken = jwt(ids.super, 'super_admin');
    const doctorToken = jwt(ids.doctor, 'doctor');
    const patientToken = jwt(ids.patient, 'patient');

    // ---- Authorization matrix ----
    check('guest (no token) -> 401', (await request('GET', '/dashboard/stats', null)).status === 401);
    check('patient -> 403', (await request('GET', '/dashboard/stats', patientToken)).status === 403);
    check('doctor -> 403', (await request('GET', '/dashboard/stats', doctorToken)).status === 403);

    const adminRes = await request('GET', '/dashboard/stats', adminToken);
    check('admin -> 200', adminRes.status === 200, JSON.stringify(adminRes.body).slice(0, 300));

    const superRes = await request('GET', '/dashboard/stats', superToken);
    check('super_admin -> 200', superRes.status === 200, JSON.stringify(superRes.body).slice(0, 300));

    // ---- Response contract ----
    const data = adminRes.body?.data || {};
    check('response has legacy aggregate fields', !!data.users && !!data.appointments && !!data.medical_records && !!data.prescriptions && !!data.ratings);
    check('response has analytics object', !!data.analytics);

    const a = data.analytics || {};
    ['usersByRole', 'appointmentsOverTime', 'topSpecialties', 'conversationsPerWeek', 'triageLevels', 'clinicTypes']
      .forEach((key) => check(`analytics.${key} key present`, key in a));

    checkSection('usersByRole', a.usersByRole);
    checkSection('appointmentsOverTime', a.appointmentsOverTime);
    checkSection('topSpecialties', a.topSpecialties);
    checkSection('conversationsPerWeek', a.conversationsPerWeek);
    checkSection('triageLevels', a.triageLevels);
    checkSection('clinicTypes', a.clinicTypes);

    // ---- Zero-data behavior ----
    // This test DB has no appointments/virtual_doctor_sessions/chatbot_conversations/clinics rows
    // (schema-only test database) — these sections must come back as real,
    // honest empty results rather than errors or fabricated values.
    const dbCounts = await pool.query(`
      SELECT
        (SELECT COUNT(*) FROM medorbit.appointments) appointments,
        (SELECT COUNT(*) FROM medorbit.virtual_doctor_sessions) vds,
        (SELECT COUNT(*) FROM medorbit.chatbot_conversations) chat,
        (SELECT COUNT(*) FROM medorbit.clinics) clinics
    `);
    const { appointments, vds, chat, clinics } = dbCounts.rows[0];
    if (Number(appointments) === 0) {
      check('appointmentsOverTime is real zero (not an error) when the table is empty', a.appointmentsOverTime?.data && !a.appointmentsOverTime.error && !a.appointmentsOverTime.data.counts.some((n) => n > 0));
      check('topSpecialties is a real empty list when there are no appointments', a.topSpecialties?.data?.items?.length === 0);
    }
    if (Number(vds) === 0) {
      check('triageLevels is real zero (not an error) when virtual_doctor_sessions is empty', a.triageLevels?.data?.labels?.length === 0);
    }
    if (Number(chat) === 0) {
      check('conversationsPerWeek is real zero (not an error) when chatbot_conversations is empty', a.conversationsPerWeek?.data && !a.conversationsPerWeek.data.counts.some((n) => n > 0));
    }
    if (Number(clinics) === 0) {
      check('clinicTypes is a real empty list when clinics is empty', a.clinicTypes?.data?.labels?.length === 0);
    }

    // usersByRole must reflect the real, current medorbit.users table — cross-checked directly.
    const roleCounts = await pool.query(`SELECT role, COUNT(*)::int FROM medorbit.users WHERE deleted_at IS NULL GROUP BY role`);
    const dbRoleMap = Object.fromEntries(roleCounts.rows.map((r) => [r.role, r.count]));
    const apiRoleMap = Object.fromEntries((a.usersByRole?.data?.labels || []).map((label, i) => [label, a.usersByRole.data.counts[i]]));
    const sameKeys = Object.keys(dbRoleMap).length === Object.keys(apiRoleMap).length
      && Object.keys(dbRoleMap).every((role) => dbRoleMap[role] === apiRoleMap[role]);
    check('usersByRole matches a direct DB aggregate', sameKeys, `db=${JSON.stringify(dbRoleMap)} api=${JSON.stringify(apiRoleMap)}`);

    // ---- Top Specialties: no appointment fan-out ----
    // doctors.specialty_id is a single scalar FK (no doctor_specialties
    // junction table exists in this schema), so the specialties -> doctors ->
    // appointments join can only ever match each appointment to exactly one
    // specialty row. Prove that on real seeded data rather than trusting the
    // schema shape alone: two specialties, two doctors (one per specialty),
    // 3 appointments (2 + 1) — the per-specialty split and the total must
    // both come out exact, with no appointment counted twice or dropped.
    const specA = crypto.randomUUID();
    const specB = crypto.randomUUID();
    await pool.query(`INSERT INTO medorbit.specialties (id, name_ar, name_en) VALUES ($1,$2,$3)`, [specA, `تخصص أ ${run}`, `Specialty A ${run}`]);
    await pool.query(`INSERT INTO medorbit.specialties (id, name_ar, name_en) VALUES ($1,$2,$3)`, [specB, `تخصص ب ${run}`, `Specialty B ${run}`]);

    await user('doctor2', 'doctor');
    const doctor1Id = (await pool.query(`INSERT INTO medorbit.doctors (user_id, specialty_id) VALUES ($1,$2) RETURNING id`, [ids.doctor, specA])).rows[0].id;
    const doctor2Id = (await pool.query(`INSERT INTO medorbit.doctors (user_id, specialty_id) VALUES ($1,$2) RETURNING id`, [ids.doctor2, specB])).rows[0].id;
    const patientRowId = (await pool.query(`INSERT INTO medorbit.patients (user_id) VALUES ($1) RETURNING id`, [ids.patient])).rows[0].id;

    const apptRows = [
      [doctor1Id, '09:00', '09:30'],
      [doctor1Id, '10:00', '10:30'],
      [doctor2Id, '11:00', '11:30']
    ];
    for (let i = 0; i < apptRows.length; i++) {
      const [doctorId, start, end] = apptRows[i];
      await pool.query(
        `INSERT INTO medorbit.appointments (appointment_number, patient_id, doctor_id, scheduled_date, start_time, end_time, duration_minutes)
         VALUES ($1,$2,$3,CURRENT_DATE,$4,$5,30)`,
        [`AT${String(run).slice(-10)}${i}`, patientRowId, doctorId, start, end]
      );
    }

    // Structural invariant, independent of the API: a direct count of
    // appointments whose doctor has a specialty must equal the sum of the
    // per-specialty grouped counts.
    const invariant = await pool.query(`
      SELECT
        (SELECT COUNT(*) FROM medorbit.appointments a JOIN medorbit.doctors d ON d.id = a.doctor_id WHERE d.specialty_id IS NOT NULL) AS direct_count,
        (SELECT COALESCE(SUM(cnt), 0) FROM (
           SELECT COUNT(a.id) cnt
           FROM medorbit.specialties s
           JOIN medorbit.doctors d ON d.specialty_id = s.id
           JOIN medorbit.appointments a ON a.doctor_id = d.id
           GROUP BY s.id
        ) t) AS grouped_sum
    `);
    check(
      'topSpecialties join produces no appointment fan-out (direct count == grouped sum)',
      Number(invariant.rows[0].direct_count) === Number(invariant.rows[0].grouped_sum),
      JSON.stringify(invariant.rows[0])
    );

    // And the API itself must reflect the exact 2/1 split just seeded.
    const afterSeedRes = await request('GET', '/dashboard/stats', adminToken);
    const items = afterSeedRes.body?.data?.analytics?.topSpecialties?.data?.items || [];
    const countFor = (name) => items.find((i) => i.nameEn === name)?.count;
    check('topSpecialties gives Specialty A exactly 2 (not multiplied)', countFor(`Specialty A ${run}`) === 2, JSON.stringify(items));
    check('topSpecialties gives Specialty B exactly 1 (not multiplied)', countFor(`Specialty B ${run}`) === 1, JSON.stringify(items));
    check('topSpecialties total across seeded specialties equals appointments inserted (3)', items.reduce((sum, i) => sum + (i.nameEn?.includes(String(run)) ? i.count : 0), 0) === 3);

  } catch (err) {
    failed++; console.error(err);
  } finally {
    await pool.end();
    console.log(`\nAnalytics: ${passed} passed, ${failed} failed`);
    process.exitCode = failed ? 1 : 0;
  }
})();

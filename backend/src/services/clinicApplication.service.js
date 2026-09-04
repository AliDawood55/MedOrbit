const db = require('../config/database');
const { createAudit } = require('./audit.service');

const VALID_TYPES = new Set(['clinic', 'dental', 'hospital', 'laboratory', 'radiology']);
const VALID_SERVICES = new Set([
  'cardiology', 'orthopedics', 'dentistry', 'dermatology', 'pediatrics',
  'gynecology', 'general_medicine', 'laboratory', 'radiology', 'emergency',
]);
const VALID_SOCIAL_LINKS = new Set(['website', 'instagram', 'facebook', 'tiktok', 'linkedin', 'whatsapp', 'x', 'youtube']);

function fail(message, statusCode = 400, code = 'VALIDATION_ERROR') {
  const error = new Error(message); error.statusCode = statusCode; error.code = code; throw error;
}
function clean(value, max = 500) { return String(value || '').trim().slice(0, max); }
function services(value) {
  const list = Array.isArray(value) ? value : [];
  const normalized = [...new Set(list.map((item) => clean(item, 60)).filter((item) => VALID_SERVICES.has(item)))];
  if (!normalized.length) fail('At least one valid medical service is required');
  return normalized;
}
function socialLinks(value) {
  if (value == null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) fail('Invalid social links');
  const links = {};
  for (const [key, raw] of Object.entries(value)) {
    const link = clean(raw, 500);
    if (!link || !VALID_SOCIAL_LINKS.has(key)) continue;
    if (!/^https:\/\//i.test(link)) fail('Social links must use HTTPS URLs');
    links[key] = link;
  }
  return links;
}
function dto(row) {
  return {
    id: row.id, user_id: row.user_id, name_ar: row.name_ar, name_en: row.name_en,
    address_ar: row.address_ar, address_en: row.address_en, city: row.city,
    region: row.region, phone: row.phone, email: row.email, website: row.website,
    type: row.type, services: row.services || [], social_links: row.social_links || {}, registration_number: row.registration_number,
    status: row.status, submitted_at: row.submitted_at, reviewed_at: row.reviewed_at,
    rejection_reason: row.rejection_reason, approved_clinic_id: row.approved_clinic_id,
  };
}
function adminDto(row) {
  return { ...dto(row), applicant: {
    email: row.applicant_email, first_name_ar: row.first_name_ar, last_name_ar: row.last_name_ar,
    first_name_en: row.first_name_en, last_name_en: row.last_name_en,
  }};
}
function payload(body, accountPhone = '') {
  const result = {
    name_ar: clean(body.name_ar, 200), name_en: clean(body.name_en, 200),
    address_ar: clean(body.address_ar, 2000), address_en: clean(body.address_en, 2000),
    city: clean(body.city, 100), region: clean(body.region, 100) || null,
    // The account phone is the verified operational contact collected during
    // clinic registration. The application does not ask applicants to enter
    // that same phone number twice.
    phone: clean(body.phone || accountPhone, 30), email: clean(body.email, 255) || null,
    website: clean(body.website, 255) || null, type: clean(body.type, 50) || 'clinic',
    services: services(body.services), social_links: socialLinks(body.social_links), registration_number: clean(body.registration_number, 120),
  };
  for (const field of ['name_ar', 'name_en', 'address_ar', 'address_en', 'city', 'phone', 'registration_number']) {
    if (!result[field]) fail(`${field} is required`);
  }
  if (!VALID_TYPES.has(result.type)) fail('Invalid clinic type');
  return result;
}
async function notify(client, userId, type, referenceId, {
  titleEn = 'Clinic application',
  titleAr = 'طلب منشأة صحية',
  messageEn,
  messageAr,
}) {
  await client.query(
    `INSERT INTO medorbit.notifications(user_id,notification_type,title_en,title_ar,message_en,message_ar,reference_id,reference_type,channel)
     VALUES($1,$2,$3,$4,$5,$6,$7,'CLINIC_APPLICATION','in_app')`,
    [userId, type, titleEn, titleAr, messageEn, messageAr, referenceId]
  );
}
async function notifyAdministratorsOfSubmission(client, application) {
  await client.query(
    `INSERT INTO medorbit.notifications
       (user_id,notification_type,title_en,title_ar,message_en,message_ar,reference_id,reference_type,channel)
     SELECT id,'CLINIC_APPLICATION_SUBMITTED','New clinic application','طلب منشأة صحية جديد',$1,$2,$3,'CLINIC_APPLICATION','in_app'
     FROM medorbit.users
     WHERE role IN ('admin','super_admin') AND is_active=true AND email_verified=true AND deleted_at IS NULL`,
    [
      `${application.name_en} submitted a clinic application for review.`,
      `قدّمت ${application.name_ar} طلب منشأة صحية للمراجعة.`,
      application.id,
    ]
  );
}
async function submit(user, body) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const account = (await client.query(
      `SELECT u.role,u.is_active,u.email_verified,u.deleted_at,p.phone
       FROM medorbit.users u LEFT JOIN medorbit.user_profiles p ON p.user_id=u.id
       WHERE u.id=$1 FOR UPDATE OF u`, [user.sub]
    )).rows[0];
    if (!account || !account.is_active || !account.email_verified || account.deleted_at || account.role !== 'clinic') {
      fail('Only verified clinic accounts may submit a clinic application', 403, 'FORBIDDEN');
    }
    const data = payload(body, account.phone);
    const columns = Object.keys(data); const values = columns.map((key) => key === 'social_links' ? JSON.stringify(data[key]) : data[key]);
    const row = (await client.query(
      `INSERT INTO medorbit.clinic_applications(user_id,${columns.join(',')})
       VALUES($1,${columns.map((_, index) => `$${index + 2}`).join(',')}) RETURNING *`, [user.sub, ...values]
    )).rows[0];
    await createAudit({ user_id: user.sub, user_role: user.role, action: 'CLINIC_APPLICATION_SUBMITTED', entity_type: 'CLINIC_APPLICATION', entity_id: row.id, new_values: dto(row) }, client);
    await notify(client, user.sub, 'CLINIC_APPLICATION_SUBMITTED', row.id, {
      messageEn: 'Your clinic application was submitted for review.',
      messageAr: 'تم إرسال طلب منشأتك الصحية للمراجعة.',
    });
    await notifyAdministratorsOfSubmission(client, row);
    await client.query('COMMIT'); return dto(row);
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; } finally { client.release(); }
}
async function decide(id, reviewer, approve, reason) {
  const client = await db.getClient();
  try {
    await client.query('BEGIN');
    const application = (await client.query('SELECT * FROM medorbit.clinic_applications WHERE id=$1 FOR UPDATE', [id])).rows[0];
    if (!application || application.status !== 'pending') fail('Pending clinic application not found', 404, 'NOT_FOUND');
    if (!approve) {
      const text = clean(reason, 2000); if (!text) fail('Rejection reason is required');
      const row = (await client.query(
        `UPDATE medorbit.clinic_applications SET status='rejected',reviewed_at=NOW(),reviewed_by_user_id=$1,rejection_reason=$2,updated_at=NOW() WHERE id=$3 RETURNING *`,
        [reviewer.sub, text, id]
      )).rows[0];
      await createAudit({ user_id: reviewer.sub, user_role: reviewer.role, action: 'CLINIC_APPLICATION_REJECTED', entity_type: 'CLINIC_APPLICATION', entity_id: id, new_values: dto(row) }, client);
      await notify(client, application.user_id, 'CLINIC_APPLICATION_REJECTED', id, {
        titleEn: 'Clinic application decision',
        titleAr: 'قرار طلب المنشأة الصحية',
        messageEn: `Your clinic application was rejected. Reason: ${text}`,
        messageAr: `تم رفض طلب منشأتك الصحية. السبب: ${text}`,
      });
      await client.query('COMMIT'); return dto(row);
    }
    const user = (await client.query('SELECT * FROM medorbit.users WHERE id=$1 FOR UPDATE', [application.user_id])).rows[0];
    // New applicants already have the clinic role. The patient alternative is
    // retained only so a pending application created before this migration can
    // still be reviewed rather than becoming permanently stuck.
    if (!user || !user.is_active || !user.email_verified || user.deleted_at || !['clinic', 'patient'].includes(user.role)) fail('Applicant is no longer eligible', 409, 'INVALID_TARGET');
    const clinic = (await client.query(
      `INSERT INTO medorbit.clinics(name_ar,name_en,address_ar,address_en,city,region,phone,email,website,type,services,registration_number,owner_user_id,approval_status,verification_status,approved_at,approved_by_user_id)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,'approved','verified',NOW(),$14) RETURNING id`,
      [application.name_ar, application.name_en, application.address_ar, application.address_en, application.city, application.region, application.phone, application.email, application.website, application.type, application.services, application.registration_number, user.id, reviewer.sub]
    )).rows[0];
    await client.query(
      "UPDATE medorbit.users SET role='clinic', preferences=jsonb_set(COALESCE(preferences,'{}'::jsonb),'{social_links}',$2::jsonb,true), authorization_version=authorization_version+1, updated_at=NOW() WHERE id=$1",
      [user.id, JSON.stringify(application.social_links || {})]
    );
    const row = (await client.query(
      `UPDATE medorbit.clinic_applications SET status='approved',reviewed_at=NOW(),reviewed_by_user_id=$1,approved_clinic_id=$2,updated_at=NOW() WHERE id=$3 RETURNING *`,
      [reviewer.sub, clinic.id, id]
    )).rows[0];
    await createAudit({ user_id: reviewer.sub, user_role: reviewer.role, action: 'CLINIC_APPLICATION_APPROVED', entity_type: 'CLINIC_APPLICATION', entity_id: id, new_values: dto(row) }, client);
    await notify(client, user.id, 'CLINIC_APPLICATION_APPROVED', id, {
      titleEn: 'Clinic application approved',
      titleAr: 'تمت الموافقة على المنشأة الصحية',
      messageEn: 'Your clinic was approved and verified. Please sign in again to open the clinic workspace.',
      messageAr: 'تمت الموافقة على منشأتك الصحية والتحقق منها. يرجى تسجيل الدخول مرة أخرى لفتح مساحة عمل المنشأة.',
    });
    await client.query('COMMIT'); return dto(row);
  } catch (error) { await client.query('ROLLBACK').catch(() => {}); throw error; } finally { client.release(); }
}
module.exports = { VALID_SERVICES, dto, adminDto, submit, decide };

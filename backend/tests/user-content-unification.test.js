const crypto = require('crypto');
const { Pool } = require('pg');
const { apiBase, poolConfig } = require('./helpers/test-environment');
const { generateAccessToken } = require('../src/utils/jwt');

const pool = new Pool(poolConfig);
const marker = `content_${Date.now()}`;
const userIds = [];
const postIds = [];
const applicationIds = [];
let specialtyId = null;
let passed = 0;
let failed = 0;

function check(name, condition, detail = '') {
    if (condition) {
        passed += 1;
        console.log(`  ✓ ${name}`);
    } else {
        failed += 1;
        console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`);
    }
}

function access(user) {
    return generateAccessToken({ sub: user.id, role: user.role, authorizationVersion: 1 });
}

async function request(method, path, token, body) {
    const headers = token ? { Authorization: `Bearer ${token}` } : {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(`${apiBase}${path}`, {
        method,
        headers,
        body: body === undefined ? undefined : JSON.stringify(body),
    });
    let responseBody = null;
    try { responseBody = await response.json(); } catch {}
    return { status: response.status, body: responseBody };
}

async function createUser(key, role = 'patient', withPatient = role === 'patient') {
    const user = {
        id: crypto.randomUUID(),
        role,
        email: `${marker}_${key}@medorbit.test`,
    };
    userIds.push(user.id);
    await pool.query(
        `INSERT INTO medorbit.users(id,email,password_hash,role,is_active,email_verified,authorization_version)
         VALUES($1,$2,'content-test-only',$3,true,true,1)`,
        [user.id, user.email, role]
    );
    await pool.query(
        `INSERT INTO medorbit.user_profiles(user_id,first_name_ar,last_name_ar,first_name_en,last_name_en)
         VALUES($1,'طبيب','اختبار',$2,'Test')`,
        [user.id, key]
    );
    if (withPatient) {
        user.patientId = crypto.randomUUID();
        await pool.query('INSERT INTO medorbit.patients(id,user_id) VALUES($1,$2)', [user.patientId, user.id]);
    }
    return user;
}

async function createDoctor(key) {
    const doctor = await createUser(key, 'doctor', true);
    doctor.doctorId = crypto.randomUUID();
    await pool.query(
        `INSERT INTO medorbit.doctors(id,user_id,medical_license_number,specialty_id,approval_status,approved_at)
         VALUES($1,$2,$3,$4,'approved',NOW())`,
        [doctor.doctorId, doctor.id, `${marker}-${key}`, specialtyId]
    );
    return doctor;
}

async function createPost(doctor, titlePayload, suffix, isPublished = false) {
    const response = await request('POST', '/doctors/me/posts', access(doctor), {
        ...titlePayload,
        category: 'health_tip',
        body: `${marker} ${suffix}`,
        isPublished,
    });
    if (response.body?.data?.id) postIds.push(response.body.data.id);
    return response;
}

async function createApplication(user, bioPayload, suffix) {
    const response = await request('POST', '/doctor-applications', access(user), {
        specialty_id: specialtyId,
        medical_license_number: `${marker}-${suffix}`,
        years_of_experience: 7,
        ...bioPayload,
    });
    if (response.body?.data?.id) applicationIds.push(response.body.data.id);
    return response;
}

async function cleanup() {
    if (applicationIds.length) {
        await pool.query(
            `DELETE FROM medorbit.processed_events WHERE event_id IN (
                SELECT id FROM medorbit.outbox_events
                WHERE aggregate_id=ANY($1::uuid[]) OR payload->>'applicationId'=ANY($1::text[])
            )`,
            [applicationIds]
        ).catch(() => {});
        await pool.query(
            `DELETE FROM medorbit.outbox_events
             WHERE aggregate_id=ANY($1::uuid[]) OR payload->>'applicationId'=ANY($1::text[])`,
            [applicationIds]
        ).catch(() => {});
        await pool.query(
            'DELETE FROM medorbit.notifications WHERE reference_id=ANY($1::uuid[])',
            [applicationIds]
        ).catch(() => {});
        await pool.query(
            'DELETE FROM medorbit.audit_logs WHERE entity_id=ANY($1::uuid[])',
            [applicationIds]
        ).catch(() => {});
    }
    if (postIds.length) {
        await pool.query('DELETE FROM medorbit.doctor_posts WHERE id=ANY($1::uuid[])', [postIds]).catch(() => {});
    }
    if (userIds.length) {
        await pool.query('DELETE FROM medorbit.audit_logs WHERE user_id=ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.notifications WHERE user_id=ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctor_applications WHERE user_id=ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.doctors WHERE user_id=ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.patients WHERE user_id=ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_sessions WHERE user_id=ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.user_profiles WHERE user_id=ANY($1::uuid[])', [userIds]).catch(() => {});
        await pool.query('DELETE FROM medorbit.users WHERE id=ANY($1::uuid[])', [userIds]).catch(() => {});
    }
    if (specialtyId) {
        await pool.query('DELETE FROM medorbit.specialties WHERE id=$1', [specialtyId]).catch(() => {});
    }
}

async function residualCounts() {
    const result = {};
    result.users = userIds.length
        ? (await pool.query('SELECT count(*)::int count FROM medorbit.users WHERE id=ANY($1::uuid[])', [userIds])).rows[0].count
        : 0;
    result.posts = postIds.length
        ? (await pool.query('SELECT count(*)::int count FROM medorbit.doctor_posts WHERE id=ANY($1::uuid[])', [postIds])).rows[0].count
        : 0;
    result.applications = applicationIds.length
        ? (await pool.query('SELECT count(*)::int count FROM medorbit.doctor_applications WHERE id=ANY($1::uuid[])', [applicationIds])).rows[0].count
        : 0;
    result.notifications = applicationIds.length
        ? (await pool.query('SELECT count(*)::int count FROM medorbit.notifications WHERE reference_id=ANY($1::uuid[])', [applicationIds])).rows[0].count
        : 0;
    result.specialties = specialtyId
        ? (await pool.query('SELECT count(*)::int count FROM medorbit.specialties WHERE id=$1', [specialtyId])).rows[0].count
        : 0;
    return result;
}

(async () => {
    console.log('\nSingle-language user-content compatibility tests\n');
    try {
        specialtyId = crypto.randomUUID();
        await pool.query(
            `INSERT INTO medorbit.specialties(id,name_ar,name_en) VALUES($1,'اختبار المحتوى',$2)`,
            [specialtyId, marker]
        );

        const doctor = await createDoctor('author');
        const otherDoctor = await createDoctor('other-author');
        const admin = await createUser('admin', 'admin', false);

        const arabicTitle = 'نصيحة لصحة القلب';
        const arabic = await createPost(doctor, { title: arabicTitle }, 'arabic');
        check('Arabic canonical post title is accepted', arabic.status === 201);
        check(
            'Arabic canonical title is stored exactly in both legacy columns',
            arabic.body?.data?.title === arabicTitle && arabic.body?.data?.title_ar === arabicTitle && arabic.body?.data?.title_en === arabicTitle
        );

        const englishTitle = 'Heart health advice';
        const english = await createPost(doctor, { title: englishTitle }, 'english');
        check('English canonical post title is accepted and preserved', english.status === 201 && english.body?.data?.title_en === englishTitle);

        const mixedTitle = 'صحة القلب Heart Health 2026';
        const mixed = await createPost(doctor, { title: mixedTitle }, 'mixed', true);
        check(
            'Mixed Unicode canonical post title is not detected, translated, or rewritten',
            mixed.status === 201 && mixed.body?.data?.title_ar === mixedTitle && mixed.body?.data?.title_en === mixedTitle
        );

        const legacy = await createPost(doctor, { titleAr: 'عنوان تاريخي', titleEn: 'Historical title' }, 'legacy');
        check(
            'Legacy bilingual post payload remains accepted with distinct values',
            legacy.status === 201 && legacy.body?.data?.title_ar === 'عنوان تاريخي' && legacy.body?.data?.title_en === 'Historical title'
        );

        const missing = await createPost(doctor, {}, 'missing');
        check('Post creation still requires a title', missing.status === 400 && missing.body?.error?.code === 'VALIDATION_ERROR');
        const tooLong = await createPost(doctor, { title: 'x'.repeat(151) }, 'long');
        check('Canonical title keeps the 150-character bound', tooLong.status === 400 && tooLong.body?.error?.code === 'VALIDATION_ERROR');
        const longBody = await request('POST', '/doctors/me/posts', access(doctor), {
            title: 'bounded body', body: 'x'.repeat(10001), category: 'health_tip',
        });
        check('Post body keeps the 10,000-character bound', longBody.status === 400);

        const xssTitle = '<img src=x onerror=alert(1)> عنوان';
        const xss = await createPost(doctor, { title: xssTitle }, 'xss');
        check('User title is stored as text without server-side rewriting', xss.status === 201 && xss.body?.data?.title === xssTitle);

        const preserve = await request('PUT', `/doctors/me/posts/${legacy.body.data.id}`, access(doctor), { body: 'Edited body only' });
        check(
            'Editing an old post without a title preserves both historical translations',
            preserve.status === 200 && preserve.body?.data?.title_ar === 'عنوان تاريخي' && preserve.body?.data?.title_en === 'Historical title'
        );

        const legacyPartial = await request('PUT', `/doctors/me/posts/${legacy.body.data.id}`, access(doctor), { titleAr: 'عنوان معدل' });
        check(
            'Legacy partial title update changes only its supplied language',
            legacyPartial.status === 200 && legacyPartial.body?.data?.title_ar === 'عنوان معدل' && legacyPartial.body?.data?.title_en === 'Historical title'
        );

        const canonicalEdit = await request('PUT', `/doctors/me/posts/${legacy.body.data.id}`, access(doctor), { title: 'عنوان واحد One title' });
        check(
            'Canonical post edit intentionally replaces both legacy title values',
            canonicalEdit.status === 200 && canonicalEdit.body?.data?.title_ar === 'عنوان واحد One title' && canonicalEdit.body?.data?.title_en === 'عنوان واحد One title'
        );

        const denied = await request('PUT', `/doctors/me/posts/${legacy.body.data.id}`, access(otherDoctor), { title: 'tampered' });
        const afterDenied = (await pool.query('SELECT title_ar,title_en FROM medorbit.doctor_posts WHERE id=$1', [legacy.body.data.id])).rows[0];
        check('Post ownership remains enforced', denied.status === 404 && afterDenied.title_ar === 'عنوان واحد One title');

        const ownList = await request('GET', '/doctors/me/posts', access(doctor));
        check(
            'Own-post read contract exposes canonical and legacy fields',
            ownList.status === 200 && ownList.body.data.some((post) => post.id === arabic.body.data.id && post.title === arabicTitle && post.title_ar === arabicTitle)
        );
        // A doctor's post list and the health feed are account-only under the
        // guest policy; the title contract is unchanged, only the reader is.
        const reader = await createUser('post-reader', 'patient', true);
        const publicPosts = await request('GET', `/doctors/${doctor.doctorId}/posts`, access(reader));
        check(
            'Doctor posts expose the canonical title without dropping legacy fields',
            publicPosts.status === 200 && publicPosts.body.data.some((post) => post.id === mixed.body.data.id && post.title === mixedTitle && post.title_en === mixedTitle)
        );
        const feed = await request('GET', '/feed/posts?limit=30', access(reader));
        check(
            'Recommendation feed keeps reason semantics and exposes canonical title',
            feed.status === 200 && feed.body.data.items.some((post) => post.id === mixed.body.data.id && post.title === mixedTitle && post.reason_code)
        );

        const arabicApplicant = await createUser('arabic-applicant');
        const englishApplicant = await createUser('english-applicant');
        const legacyApplicant = await createUser('legacy-applicant');
        const applicationArabicBio = 'طبيبة قلب بخبرة سريرية';
        const arabicApplication = await createApplication(arabicApplicant, { bio: applicationArabicBio }, 'arabic-bio');
        check(
            'One Arabic application bio is accepted and copied exactly to legacy columns',
            arabicApplication.status === 201 && arabicApplication.body?.data?.bio_ar === applicationArabicBio && arabicApplication.body?.data?.bio_en === applicationArabicBio
        );
        const applicationEnglishBio = 'Cardiologist with clinical experience';
        const englishApplication = await createApplication(englishApplicant, { bio: applicationEnglishBio }, 'english-bio');
        check(
            'One English application bio is accepted without duplicate input',
            englishApplication.status === 201 && englishApplication.body?.data?.bio === applicationEnglishBio && englishApplication.body?.data?.bio_ar === applicationEnglishBio
        );
        const legacyApplication = await createApplication(
            legacyApplicant,
            { bio_ar: 'نبذة طلب قديم', bio_en: 'Old application bio' },
            'legacy-bio'
        );
        check(
            'Legacy bilingual application payload remains accepted with distinct values',
            legacyApplication.status === 201 && legacyApplication.body?.data?.bio_ar === 'نبذة طلب قديم' && legacyApplication.body?.data?.bio_en === 'Old application bio'
        );

        const myApplications = await request('GET', '/doctor-applications/me', access(legacyApplicant));
        check(
            'Historical application reads retain both bios and add a fallback canonical bio',
            myApplications.status === 200 && myApplications.body.data.some((application) => (
                application.id === legacyApplication.body.data.id && application.bio === 'نبذة طلب قديم' && application.bio_en === 'Old application bio'
            ))
        );
        const adminApplications = await request('GET', '/admin/doctor-applications?status=pending', access(admin));
        check(
            'Admin application API displays old and new bio contracts safely',
            adminApplications.status === 200 &&
            adminApplications.body.data.some((application) => application.id === legacyApplication.body.data.id && application.bio_en === 'Old application bio') &&
            adminApplications.body.data.some((application) => application.id === englishApplication.body.data.id && application.bio === applicationEnglishBio)
        );

        const approved = await request(
            'POST',
            `/admin/doctor-applications/${legacyApplication.body.data.id}/approve`,
            access(admin),
            {}
        );
        const approvedDoctor = approved.body?.data?.approved_doctor_id
            ? (await pool.query(
                'SELECT professional_bio_ar,professional_bio_en FROM medorbit.doctors WHERE id=$1',
                [approved.body.data.approved_doctor_id]
            )).rows[0]
            : null;
        check(
            'Approving an old application preserves both historical professional bios',
            approved.status === 200 && approvedDoctor?.professional_bio_ar === 'نبذة طلب قديم' && approvedDoctor?.professional_bio_en === 'Old application bio'
        );

        const columns = (await pool.query(
            `SELECT table_name,column_name FROM information_schema.columns
             WHERE table_schema='medorbit'
               AND table_name IN ('doctor_posts','doctor_applications')
               AND column_name IN ('title','bio','title_ar','title_en','bio_ar','bio_en')`
        )).rows;
        check(
            'Compatibility refactor uses legacy schema and requires no migration',
            columns.some((column) => column.column_name === 'title_ar') &&
            columns.some((column) => column.column_name === 'bio_en') &&
            !columns.some((column) => ['title', 'bio'].includes(column.column_name))
        );
    } catch (error) {
        failed += 1;
        console.error(`  ✗ suite error — ${error.stack || error.message}`);
    } finally {
        await cleanup();
        const residual = await residualCounts();
        console.log(`Focused residual counts: ${JSON.stringify(residual)}`);
        check('Focused fixtures leave zero residual rows', Object.values(residual).every((value) => Number(value) === 0));
        await pool.end();
    }

    console.log(`\nSingle-language user content: ${passed} passed, ${failed} failed`);
    if (failed) process.exitCode = 1;
})();

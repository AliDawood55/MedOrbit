const fs = require('fs');
const path = require('path');
const vm = require('vm');

let passed = 0;
let failed = 0;

function check(name, condition) {
    if (condition) {
        passed += 1;
        console.log(`  ✓ ${name}`);
    } else {
        failed += 1;
        console.error(`  ✗ ${name}`);
    }
}

function frontendFile(relativePath) {
    return fs.readFileSync(path.resolve(__dirname, '..', relativePath), 'utf8');
}

function repositoryFile(relativePath) {
    return fs.readFileSync(path.resolve(__dirname, '..', '..', relativePath), 'utf8');
}

console.log('\nSingle-language user-content UI tests\n');

const postPage = frontendFile('public/doctor-posts.html');
const postController = frontendFile('src/js/doctor-posts.js');
const applicationPage = frontendFile('public/doctor-application.html');
const applicationController = frontendFile('src/js/doctor-application.js');
const adminApplications = frontendFile('src/js/admin-doctor-applications.js');
const adminSocial = frontendFile('src/js/admin-social.js');
const feed = frontendFile('src/js/feed.js');
const doctorProfile = frontendFile('src/js/doctor.js');
const i18nSource = frontendFile('src/js/i18n.js');
const backendAdapter = repositoryFile('backend/src/utils/bilingualUserContent.js');
const compatibilityDoc = repositoryFile('docs/bilingual-user-content-compatibility.md');

check(
    'doctor post form has exactly one title input',
    (postPage.match(/id="postTitle"/g) || []).length === 1 &&
    !/id="postTitleAr"|id="postTitleEn"/.test(postPage)
);
check(
    'post title accepts natural bidirectional Unicode text',
    /id="postTitle"[^>]*maxlength="150"[^>]*dir="auto"/s.test(postPage)
);
check(
    'post title label and placeholder use localized copy',
    /data-i18n="doctorPosts\.postTitle"/.test(postPage) &&
    /data-i18n-placeholder="doctorPosts\.postTitlePlaceholder"/.test(postPage) &&
    /doctorPosts\.postTitlePlaceholder': 'Write the title in Arabic, English, or both'/.test(i18nSource)
);
check(
    'new post submissions send the canonical title field only',
    /body\.title = title/.test(postController) &&
    !/titleAr\s*:|titleEn\s*:/.test(postController)
);
check(
    'unchanged historical post edits omit title to preserve both legacy values',
    /title !== editingDisplayedTitle/.test(postController) &&
    /editingDisplayedTitle = postTitle\(p\)/.test(postController)
);
check(
    'doctor post renderer escapes the locale-fallback title',
    /escapeHtml\(postTitle\(p\)\)/.test(postController)
);

check(
    'doctor application form has exactly one professional-bio input',
    (applicationPage.match(/id="bio"/g) || []).length === 1 &&
    !/id="bioAr"|id="bioEn"/.test(applicationPage)
);
check(
    'application bio supports mixed-direction text and localized guidance',
    /id="bio"[^>]*dir="auto"/s.test(applicationPage) &&
    /data-i18n="doctorApplication\.bio"/.test(applicationPage) &&
    /data-i18n-placeholder="doctorApplication\.bioPlaceholder"/.test(applicationPage)
);
check(
    'application submission sends one canonical bio and no duplicate language payload',
    /bio: byId\('bio'\)\.value\.trim\(\)/.test(applicationController) &&
    !/bio_ar\s*:|bio_en\s*:|byId\('bioAr'\)|byId\('bioEn'\)/.test(applicationController)
);
check(
    'admin application history prefers canonical bio with legacy locale fallback',
    /escapeHtml\(application\.bio \|\| localized\(application\.bio_ar, application\.bio_en\)/.test(adminApplications)
);
check(
    'admin post moderation chooses locale with fallback and escapes titles',
    /escapeHtml\(localized\(post\.title_ar, post\.title_en\)/.test(adminSocial)
);
check(
    'public feed retains locale-first historical title fallback and HTML escaping',
    /const title = isAr\(\) \? \(p\.title_ar \|\| p\.title_en\) : \(p\.title_en \|\| p\.title_ar\);/.test(feed) &&
    /<h2 class="feed-title">\$\{esc\(title\)\}<\/h2>/.test(feed)
);
check(
    'doctor profile retains locale-first fallbacks for bios and reviews',
    /localized\(doctor, 'professional_bio_ar', 'professional_bio_en'\)/.test(doctorProfile) &&
    /localized\(review, 'review_text_ar', 'review_text_en'\)/.test(doctorProfile)
);

check(
    'backend compatibility adapter accepts canonical and old camel/snake fields',
    /canonicalKey/.test(backendAdapter) && /legacyArKeys/.test(backendAdapter) && /legacyEnKeys/.test(backendAdapter)
);
check(
    'canonical backend content is copied without translation or language detection',
    /const ar = isBilingualObject \? normalizeText\(supplied\.ar\) : normalizeText\(supplied\);/.test(backendAdapter) &&
    /const en = isBilingualObject \? normalizeText\(supplied\.en\) : normalizeText\(supplied\);/.test(backendAdapter) &&
    !/translate|detectLanguage|languageDetector/i.test(backendAdapter)
);
check(
    'compatibility policy documents the identity-name exception',
    /First and last names remain separate Arabic\/English identity fields/.test(compatibilityDoc) &&
    /separately planned identity migration/.test(compatibilityDoc)
);
check(
    'compatibility policy keeps canonical reference and translated product data bilingual',
    /Specialty\/clinic names and descriptions remain bilingual/.test(compatibilityDoc) &&
    /Notification titles\/messages/.test(compatibilityDoc)
);

const context = vm.createContext({
    console,
    CustomEvent: class CustomEvent { constructor(type, init) { this.type = type; this.detail = init?.detail; } },
    Store: {
        getLang: () => 'ar',
        setLang: () => {},
    },
    document: {
        documentElement: { lang: 'ar', dir: 'rtl' },
        body: { lang: 'ar' },
        getElementById: () => null,
        querySelectorAll: () => [],
    },
    window: { dispatchEvent: () => {} },
});
vm.runInContext(i18nSource, context);
const arabicPreferred = vm.runInContext("I18n.localizedContent('عنوان قديم', 'Old title')", context);
const arabicFallback = vm.runInContext("I18n.localizedContent('', 'English only')", context);
vm.runInContext("I18n.setLang('en')", context);
const englishPreferred = vm.runInContext("I18n.localizedContent('عنوان قديم', 'Old title')", context);
const englishFallback = vm.runInContext("I18n.localizedContent('عربي فقط', null)", context);
check(
    'runtime fallback prefers Arabic in Arabic locale and falls back to English',
    arabicPreferred === 'عنوان قديم' && arabicFallback === 'English only'
);
check(
    'runtime fallback prefers English in English locale and falls back to Arabic',
    englishPreferred === 'Old title' && englishFallback === 'عربي فقط'
);

console.log(`\nSingle-language user-content UI: ${passed} passed, ${failed} failed`);
process.exitCode = failed ? 1 : 0;

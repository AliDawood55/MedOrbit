const fs = require('fs');
const path = require('path');

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

const publicDir = path.resolve(__dirname, '..', 'public');
const files = fs.readdirSync(publicDir).filter((f) => f.endsWith('.html'));

const DYNAMIC_H1_PAGES = new Set(['clinic.html', 'doctor.html', 'patient-detail.html']);

console.log(`\nAccessibility shell tests (${files.length} pages)\n`);

const h1Exceptions = [];
const mainExceptions = [];
const skipMissing = [];
const skipTargetMissing = [];
const skipOrderIssues = [];
const oldBrandPattern = [];
const mainContentIdMissing = [];
const duplicateMainContentId = [];

for (const file of files) {
    const src = fs.readFileSync(path.join(publicDir, file), 'utf8');

const mainOpenTags = src.match(/<main\b[^>]*>/g) || [];
    if (mainOpenTags.length !== 1) {
        mainExceptions.push(`${file} (${mainOpenTags.length} <main> tags)`);
    }

if (/<h1>\s*MedOrbit\s*<\/h1>/.test(src)) {
        oldBrandPattern.push(file);
    }

const mainWithId = mainOpenTags.filter((tag) => /id="main-content"/.test(tag));
    if (mainOpenTags.length > 0 && mainWithId.length === 0) {
        mainContentIdMissing.push(file);
    }
    if (mainWithId.length > 1) {
        duplicateMainContentId.push(file);
    }

const skipMatch = src.match(/<a\b[^>]*class="skip-link"[^>]*href="#([^"]+)"[^>]*>/);
    if (!skipMatch) {
        skipMissing.push(file);
    } else {
        const targetId = skipMatch[1];
        const targetExists = new RegExp(`id="${targetId}"`).test(src);
        if (!targetExists) skipTargetMissing.push(`${file} -> #${targetId}`);

const skipIndex = src.indexOf(skipMatch[0]);
        const headerIndex = src.search(/<header\b/);
        if (headerIndex !== -1 && skipIndex > headerIndex) {
            skipOrderIssues.push(file);
        }
    }

const h1Count = (src.match(/<h1[\s>]/g) || []).length;
    if (h1Count !== 1 && !DYNAMIC_H1_PAGES.has(file)) {
        h1Exceptions.push(`${file} (${h1Count} h1 elements)`);
    }
}

check('every page has exactly one <main> (or is reported as an exception)',
    mainExceptions.length === 0, mainExceptions.join(', '));

check('no page contains the old <h1>MedOrbit</h1> branding pattern',
    oldBrandPattern.length === 0, oldBrandPattern.join(', '));

check('every <main> carries id="main-content"',
    mainContentIdMissing.length === 0, mainContentIdMissing.join(', '));

check('no page has a duplicate id="main-content"',
    duplicateMainContentId.length === 0, duplicateMainContentId.join(', '));

check('every page has a skip link (a.skip-link)',
    skipMissing.length === 0, skipMissing.join(', '));

check('every skip link points to an id that exists on the page',
    skipTargetMissing.length === 0, skipTargetMissing.join(', '));

check('the skip link appears before the header/main navigation in source order',
    skipOrderIssues.length === 0, skipOrderIssues.join(', '));

check('every page has exactly one meaningful H1 (or is an approved dynamic-content exception)',
    h1Exceptions.length === 0, h1Exceptions.join(', '));

const STANDALONE_PAGES = new Set(['admin-invitation-accept.html', 'billing-sandbox.html']);
const brandNameMissing = [];
for (const file of files) {
    if (STANDALONE_PAGES.has(file)) continue;
    const src = fs.readFileSync(path.join(publicDir, file), 'utf8');
    if (!/class="brand-name"/.test(src)) brandNameMissing.push(file);
}
check('brand-name element still exists on normal app-header pages',
    brandNameMissing.length === 0, brandNameMissing.join(', '));

const layoutJsPath = path.resolve(__dirname, '..', 'src', 'js', 'layout.js');
const layoutJsSrc = fs.readFileSync(layoutJsPath, 'utf8');
check('layout.js does not dynamically recreate <h1>MedOrbit</h1>',
    !/<h1>\s*MedOrbit\s*<\/h1>/.test(layoutJsSrc));
check('layout.js injects the neutral brand-name element for the mobile drawer',
    /class="brand-name"/.test(layoutJsSrc));

const mainCssPath = path.resolve(__dirname, '..', 'src', 'css', 'main.css');
const mainCssSrc = fs.readFileSync(mainCssPath, 'utf8');
check('shared .skip-link CSS exists in main.css', /\.skip-link\s*\{/.test(mainCssSrc));
check('.skip-link becomes visible on focus (no display:none/visibility:hidden hiding)',
    /\.skip-link:focus/.test(mainCssSrc) && !/\.skip-link\s*\{[^}]*display:\s*none/.test(mainCssSrc));

console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);

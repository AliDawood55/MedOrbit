/**
 * Redundant current-user fetch elimination (Phase 5, P5D1).
 *
 * auth-gate.js is the single authoritative caller of GET /users/me per page
 * load (verifySession() dedupes in-flight calls). Protected page controllers
 * that only need the currently verified identity must reuse that result via
 * AuthGate.verifySession() / AuthGate.getVerifiedUser() instead of issuing
 * their own API.users.me() call, which would double the request.
 *
 * A handful of API.users.me() calls remain deliberately — a fresh server
 * round trip is required right after an identity-changing mutation (e.g. an
 * avatar upload) that AuthGate's cached verifiedUser would not reflect. Those
 * are allowlisted below with the reason they stay.
 *
 * Static source scan only, no DOM/vm: this is a data-flow property of the
 * source text (who calls API.users.me()), not of runtime behavior already
 * covered by auth-gate-ui.test.js.
 */
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

function jsPath(name) {
    return path.resolve(__dirname, '..', 'src', 'js', name);
}

function jsFile(name) {
    return fs.readFileSync(jsPath(name), 'utf8');
}

function countMatches(source, pattern) {
    const matches = source.match(pattern);
    return matches ? matches.length : 0;
}

console.log('\nRedundant current-user request elimination tests\n');

// =====================================================================
// auth-gate.js remains the sole authoritative caller
// =====================================================================

console.log('auth-gate.js authoritative verification');
{
    const source = jsFile('auth-gate.js');
    const callCount = countMatches(source, /API\.users\.me\(\)/g);
    check('auth-gate.js calls API.users.me() exactly once', callCount === 1, `found ${callCount}`);
    check('verifySession is deduplicated via a shared in-flight promise',
        /verifyPromise\s*=\s*\(async/.test(source) && /if\s*\(verifyPromise\)\s*return verifyPromise;/.test(source));
    check('getVerifiedUser returns the stored identity directly (no .data wrapper)',
        /getVerifiedUser:\s*\(\)\s*=>\s*verifiedUser/.test(source));
}

// =====================================================================
// Protected page controllers: init-time duplicates removed
// =====================================================================

console.log('\nProtected page controllers use AuthGate instead of a second /users/me fetch');

const dedupedPages = [
    'dashboard.js',
    'doctor-posts.js',
    'my-doctor.js',
    'feed.js',
    'profile.js',
    'patient-detail.js',
    'my-reports.js',
    'my-patients.js',
    'direct-messages.js',
    'analytics.js',
    'doctor-application.js',
    'admin-contact-messages.js',
    'admin-doctor-applications.js',
    'admin-invitations.js',
    'admin-social.js',
    'admin-users.js'
];

for (const name of dedupedPages) {
    const source = jsFile(name);
    check(`${name}: no direct API.users.me() call`, !/API\.users\.me\(\)/.test(source));
    check(`${name}: uses AuthGate.verifySession()`, /AuthGate\.verifySession\(\)/.test(source));
    check(`${name}: uses AuthGate.getVerifiedUser()`, /AuthGate\.getVerifiedUser\(\)/.test(source));
}

// =====================================================================
// Retained API.users.me() calls: explicitly allowlisted with a reason
// =====================================================================

console.log('\nRetained API.users.me() calls are documented freshness exceptions');

const allowlist = {
    'doctor-profile-edit.js': {
        count: 1,
        reason: 'refetches immediately after uploadAvatar() so renderPreview() shows the ' +
            'just-changed profile_image_url — AuthGate\'s cached verifiedUser predates the mutation'
    }
};

for (const [name, { count }] of Object.entries(allowlist)) {
    const source = jsFile(name);
    const actual = countMatches(source, /API\.users\.me\(\)/g);
    check(`${name}: retains exactly ${count} allowlisted API.users.me() call`, actual === count, `found ${actual}`);
    check(`${name}: also uses AuthGate for its init-time identity load`,
        /AuthGate\.verifySession\(\)/.test(source) && /AuthGate\.getVerifiedUser\(\)/.test(source));
}

// =====================================================================
// Full-repo inventory: every API.users.me() occurrence is accounted for
// =====================================================================

console.log('\nFull-repo inventory');
{
    const jsDir = path.resolve(__dirname, '..', 'src', 'js');
    const files = fs.readdirSync(jsDir).filter((f) => f.endsWith('.js'));

    const expectedTotal = 1 /* auth-gate.js */ + Object.values(allowlist).reduce((sum, { count }) => sum + count, 0);
    let total = 0;
    const unexpected = [];

    for (const file of files) {
        const source = fs.readFileSync(path.join(jsDir, file), 'utf8');
        const count = countMatches(source, /API\.users\.me\(\)/g);
        if (count === 0) continue;
        total += count;

        const isAuthGate = file === 'auth-gate.js';
        const isAllowlisted = Object.prototype.hasOwnProperty.call(allowlist, file);
        if (!isAuthGate && !isAllowlisted) unexpected.push(`${file} (${count})`);
    }

    check(`total API.users.me() occurrences across src/js == ${expectedTotal}`, total === expectedTotal, `found ${total}`);
    check('no unexpected/undocumented API.users.me() occurrences', unexpected.length === 0, unexpected.join(', '));
}

// =====================================================================

console.log(`\n${passed} passed, ${failed} failed\n`);
if (failed > 0) process.exit(1);

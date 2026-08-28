const fs = require('fs');
const path = require('path');
const vm = require('vm');

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

function frontendPath(relativePath) {
    return path.resolve(__dirname, '..', relativePath);
}

function frontendFile(relativePath) {
    return fs.readFileSync(frontendPath(relativePath), 'utf8');
}

console.log('\nGlobal authentication gate tests\n');

function loadAuthGate(pathname = '/public/home.html', search = '') {
    const listeners = {};

    function element(tag = 'div') {
        const el = {
            tagName: tag,
            style: {},
            dataset: {},
            hidden: false,
            attributes: {},
            children: [],
            classList: {
                add() {}, remove() {}, toggle() {}, contains: () => false
            },
            setAttribute(k, v) { this.attributes[k] = v; },
            getAttribute(k) { return k in this.attributes ? this.attributes[k] : null; },
            removeAttribute(k) { delete this.attributes[k]; },
            hasAttribute(k) { return k in this.attributes; },
            appendChild(child) { this.children.push(child); return child; },
            remove() {},
            focus() {},
            addEventListener() {},
            querySelector: () => null,
            querySelectorAll: () => [],
            closest: () => null,
            set textContent(v) { this._text = v; },
            get textContent() { return this._text; },
            set innerHTML(v) { this._html = v; },
            get innerHTML() { return this._html; }
        };
        return el;
    }

    const documentElement = element('html');
    const head = element('head');
    const body = element('body');

    const sandbox = {
        console,
        URL,
        URLSearchParams,
        setTimeout,
        clearTimeout,
        Promise,
        Set,
        Map,
        Array,
        JSON,
        CustomEvent: function CustomEvent(type, init) { return { type, detail: init && init.detail }; },
        requestAnimationFrame: (fn) => fn(),
        sessionStorage: (() => {
            const store = new Map();
            return {
                getItem: (k) => (store.has(k) ? store.get(k) : null),
                setItem: (k, v) => store.set(k, String(v)),
                removeItem: (k) => store.delete(k)
            };
        })(),
        document: {
            readyState: 'complete',
            currentScript: { src: 'http://localhost:8080/src/js/auth-gate.js' },
            documentElement,
            head,
            body,
            addEventListener(type, fn) { (listeners[type] = listeners[type] || []).push(fn); },
            createElement: (tag) => element(tag),
            getElementById: () => null,
            querySelector: () => null,
            querySelectorAll: () => [],
            contains: () => false,
            dispatchEvent() {},
            get activeElement() { return null; }
        },
        window: {
            location: {
                pathname,
                search,
                hash: '',
                href: `http://localhost:8080${pathname}${search}`,
                origin: 'http://localhost:8080',
                replace() {},
                assign() {}
            },
            history: { replaceState() {} },
            addEventListener() {},
            dispatchEvent() {}
        }
    };
    sandbox.globalThis = sandbox;
    sandbox.window.document = sandbox.document;

    const source = frontendFile('src/js/auth-gate.js');
    vm.createContext(sandbox);

    return vm.runInContext(source + '\n;AuthGate;', sandbox, { filename: 'auth-gate.js' });
}

let AuthGate;
try {
    AuthGate = loadAuthGate();
    check('auth-gate.js boots on home.html without a DOM/API', !!AuthGate);
} catch (err) {
    check('auth-gate.js boots on home.html without a DOM/API', false, err.message);
    process.exit(1);
}

const pagesOnDisk = fs.readdirSync(frontendPath('public'))
    .filter((f) => f.endsWith('.html'))
    .sort();

const EXPECTED_PUBLIC = ['home.html'];
const EXPECTED_AUTH_FLOW = [
    'forgot-password.html',
    'login.html',
    'register.html',
    'reset-password.html',
    'verify-email.html'
];

check('every page under frontend/public is a known page to the gate',
    pagesOnDisk.every((p) => AuthGate.classify(p) !== undefined));

const actualPublic = pagesOnDisk.filter((p) => AuthGate.classify(p) === 'PUBLIC_HOME');
const actualAuthFlow = pagesOnDisk.filter((p) => AuthGate.classify(p) === 'AUTH_FLOW').sort();
const actualProtected = pagesOnDisk.filter((p) => AuthGate.classify(p) === 'PROTECTED');

check('home.html is the only guest-browsable product page',
    JSON.stringify(actualPublic) === JSON.stringify(EXPECTED_PUBLIC),
    JSON.stringify(actualPublic));

check('AUTH_FLOW is exactly the pages needed to sign in / create / recover an account',
    JSON.stringify(actualAuthFlow) === JSON.stringify(EXPECTED_AUTH_FLOW),
    JSON.stringify(actualAuthFlow));

check('every remaining page is PROTECTED',
    actualProtected.length === pagesOnDisk.length - EXPECTED_PUBLIC.length - EXPECTED_AUTH_FLOW.length,
    `${actualProtected.length} protected of ${pagesOnDisk.length}`);

check('an unlisted future page defaults to PROTECTED',
    AuthGate.classify('brand-new-feature.html') === 'PROTECTED');
check('a bare directory request resolves to a PROTECTED page, not Home',
    AuthGate.classify('') === 'PROTECTED');

const missingGate = pagesOnDisk.filter((p) => {
    const html = frontendFile(path.join('public', p));
    const headEnd = html.indexOf('</head>');
    const tag = html.indexOf('src="../src/js/auth-gate.js"');
    return tag === -1 || headEnd === -1 || tag > headEnd;
});
check('every page loads auth-gate.js inside <head>', missingGate.length === 0, missingGate.join(', '));

const duplicateGate = pagesOnDisk.filter((p) =>
    (frontendFile(path.join('public', p)).match(/src="\.\.\/src\/js\/auth-gate\.js"/g) || []).length !== 1);
check('no page loads the gate twice', duplicateGate.length === 0, duplicateGate.join(', '));

check('admin-invitation-accept.html is PROTECTED (a session is required)',
    AuthGate.classify('admin-invitation-accept.html') === 'PROTECTED');
check('admin-invitation-accept.html carries no admin/super_admin restriction',
    !('admin-invitation-accept.html' in AuthGate.ROLE_RESTRICTED),
    JSON.stringify(AuthGate.ROLE_RESTRICTED['admin-invitation-accept.html']));
check('super_admin-only invitation management is still marked super_admin-only',
    JSON.stringify(AuthGate.ROLE_RESTRICTED['admin-invitations.html']) === '["super_admin"]',
    JSON.stringify(AuthGate.ROLE_RESTRICTED['admin-invitations.html']));

check('admin-users.html is PROTECTED',
    AuthGate.classify('admin-users.html') === 'PROTECTED');
check('admin-users.html carries the admin/super_admin role-matrix entry',
    JSON.stringify(AuthGate.ROLE_RESTRICTED['admin-users.html']) === '["admin","super_admin"]',
    JSON.stringify(AuthGate.ROLE_RESTRICTED['admin-users.html']));
check('sanitizeReturnPath accepts admin-users.html as a return destination',
    AuthGate.sanitizeReturnPath('admin-users.html') === 'admin-users.html');
check('sanitizeReturnPath preserves query and hash on admin-users.html',
    AuthGate.sanitizeReturnPath('admin-users.html?role=doctor#users') === 'admin-users.html?role=doctor#users');

const gateSourceForRoles = frontendFile('src/js/auth-gate.js');
check('ROLE_RESTRICTED is never consulted to allow or deny a page',
    !/ROLE_RESTRICTED\s*\[/.test(gateSourceForRoles) &&
    !/in\s+ROLE_RESTRICTED/.test(gateSourceForRoles) &&
    !/ROLE_RESTRICTED\.\w/.test(gateSourceForRoles),
    'the gate defines and exports the map, and must never read it');

const gateClassificationSource = gateSourceForRoles.slice(0, gateSourceForRoles.indexOf('function defaultLandingPage'));
check('the gate makes no role decision while classifying a requested page',
    !/\.role\s*===|\.role\s*!==|includes\(.*\.role/.test(gateClassificationSource));

const GUEST_RENDERABLE = new Set(EXPECTED_PUBLIC.concat(EXPECTED_AUTH_FLOW));
const protectedOnDisk = pagesOnDisk.filter((p) => !GUEST_RENDERABLE.has(p));

const missingShield = protectedOnDisk.filter((p) => {
    const html = frontendFile(path.join('public', p));
    const headEnd = html.indexOf('</head>');
    const rootState = html.indexOf('data-auth-gate="pending"');
    const shieldRule = html.indexOf('html[data-auth-gate="pending"]');
    return rootState === -1 || shieldRule === -1 || headEnd === -1 ||
        rootState > headEnd || shieldRule > headEnd;
});
check('every protected page declares its fail-closed state and shield before protected markup',
    missingShield.length === 0, missingShield.join(', '));

const missingBootstrap = protectedOnDisk.filter((p) => {
    const html = frontendFile(path.join('public', p));
    return !html.includes('src="../src/js/auth-bootstrap.js"');
});
check('every protected page loads the gate-never-loaded bootstrap',
    missingBootstrap.length === 0, missingBootstrap.join(', '));

const duplicateBootstrap = protectedOnDisk.filter((p) => {
    const html = frontendFile(path.join('public', p));
    return (html.match(/src="\.\.\/src\/js\/auth-bootstrap\.js"/g) || []).length !== 1;
});
check('every protected page loads the auth bootstrap exactly once',
    duplicateBootstrap.length === 0, duplicateBootstrap.join(', '));

const guestBlocked = Array.from(GUEST_RENDERABLE).filter((p) =>
    /data-auth-gate="pending"|src="\.\.\/src\/js\/auth-bootstrap\.js"/
        .test(frontendFile(path.join('public', p))));
check('Home and the auth-flow pages are never shielded',
    guestBlocked.length === 0, guestBlocked.join(', '));

const bootstrapTooLate = protectedOnDisk.filter((p) => {
    const html = frontendFile(path.join('public', p));
    const bootstrap = html.indexOf('src="../src/js/auth-bootstrap.js"');
    const gate = html.indexOf('src="../src/js/auth-gate.js"');
    return bootstrap === -1 || gate === -1 || bootstrap > gate;
});
check('the synchronous auth bootstrap runs before the gate is requested',
    bootstrapTooLate.length === 0, bootstrapTooLate.join(', '));

const deferredBootstrap = protectedOnDisk.filter((p) => {
    const html = frontendFile(path.join('public', p));
    const tag = html.match(/<script\b[^>]*auth-bootstrap\.js[^>]*>/i)?.[0] || '';
    return /\b(?:async|defer)\b/i.test(tag);
});
check('the auth bootstrap is never async or deferred',
    deferredBootstrap.length === 0, deferredBootstrap.join(', '));

const INLINE_SHIELD_RULE = 'html[data-auth-gate="pending"] body>*:not([data-auth-ui])';
check('the HTML shield and the gate\'s own shield hide the same elements',
    /html\[data-auth-gate="pending"\] body > \*:not\(\[data-auth-ui\]\)/
        .test(frontendFile('src/js/auth-gate.js')) &&
    protectedOnDisk.every((p) => frontendFile(path.join('public', p)).includes(INLINE_SHIELD_RULE)));

const watchdog = frontendFile('src/js/auth-bootstrap.js');
check('the watchdog stands down once the gate reports itself ready',
    /if\s*\(\s*window\.__medorbitAuthGateReady\s*\|\|\s*window\.__medorbitNavigatingAway\s*\)\s*\{\s*return;\s*\}/.test(watchdog));
check('the watchdog waits for load, with a timeout only as a backstop',
    /addEventListener\(\s*'load'/.test(watchdog) && /setTimeout\(\s*f\s*,\s*20000\s*\)/.test(watchdog));
check('the watchdog fails closed to Home instead of revealing the page',
    /location\.replace\(\s*'home\.html\?auth=unavailable&next='/.test(watchdog) &&
    !/removeAttribute/.test(watchdog));
check('the watchdog carries the intended destination to Home for the sanitizer',
    /'home\.html\?auth=unavailable&next='\s*\+\s*encodeURIComponent\(\s*location\.pathname\.split\(\s*'\/'\s*\)\.pop\(\)\s*\+\s*location\.search\s*\)/.test(watchdog));
check('the gate publishes its ready flag only after installing itself',
    /window\.__medorbitAuthGateReady = true;[\s\S]{0,40}return \{/.test(frontendFile('src/js/auth-gate.js')));

const indexHtml = frontendFile('public/index.html');
check('redirect-guard.js still loads before the gate on index.html',
    indexHtml.indexOf('redirect-guard.js') < indexHtml.indexOf('auth-gate.js'));
check('redirect-guard.js signals the gate to stand down during its hand-off',
    /__medorbitNavigatingAway\s*=\s*true/.test(frontendFile('src/js/redirect-guard.js')));

const MUST_REJECT = [
    ['absolute https URL', 'https://evil.example'],
    ['absolute http URL', 'http://evil.example/public/home.html'],
    ['protocol-relative', '//evil.example'],
    ['protocol-relative, backslashes', '\\\\evil.example'],
    ['mixed slash/backslash', '/\\evil.example'],
    ['javascript: scheme', 'javascript:alert(1)'],
    ['javascript: with embedded newline', 'java\nscript:alert(1)'],
    ['javascript: with embedded tab', 'java\tscript:alert(1)'],
    ['data: scheme', 'data:text/html,<script>alert(1)</script>'],
    ['vbscript: scheme', 'vbscript:msgbox(1)'],
    ['file: scheme', 'file:///etc/passwd'],
    ['root-absolute path', '/admin/secret.html'],
    ['parent traversal', '../../etc/passwd'],
    ['traversal that renormalises onto a real page', '../public/dashboard.html'],
    ['percent-encoded traversal', '%2e%2e%2fadmin-invitations.html'],
    ['encoded slash', 'sub%2Fdashboard.html'],
    ['backslash directory', 'sub\dashboard.html'],
    ['subdirectory', 'sub/dashboard.html'],
    ['unknown page name', 'not-a-real-page.html'],
    ['non-html asset', 'api.js'],
    ['userinfo trick', 'https://medorbit.invalid@evil.example/'],
    ['empty string', ''],
    ['whitespace only', '   '],
    ['null', null],
    ['object', { toString: () => 'dashboard.html' }],
    ['over-long value', 'dashboard.html?q=' + 'a'.repeat(600)],
    ['login.html (auth-flow loop)', 'login.html'],
    ['register.html (auth-flow loop)', 'register.html']
];

MUST_REJECT.forEach(([label, value]) => {
    check(`sanitizer rejects ${label}`, AuthGate.sanitizeReturnPath(value) === null,
        `got ${JSON.stringify(AuthGate.sanitizeReturnPath(value))}`);
});

const MUST_ACCEPT = [
    ['a bare protected page', 'dashboard.html', 'dashboard.html'],
    ['home.html', 'home.html', 'home.html'],
    ['a query string is preserved', 'direct-messages.html?id=42', 'direct-messages.html?id=42'],
    ['a doctor id is preserved', 'doctor.html?id=abc-123', 'doctor.html?id=abc-123'],
    ['a clinic id is preserved', 'clinic.html?id=7', 'clinic.html?id=7'],
    ['a search query is preserved', 'find-doctors.html?search=heart', 'find-doctors.html?search=heart'],
    ['a hash is preserved', 'my-schedule.html#appointments', 'my-schedule.html#appointments'],
    ['query and hash together', 'feed.html?tab=all#top', 'feed.html?tab=all#top'],
    ['surrounding whitespace is trimmed', '  analytics.html  ', 'analytics.html']
];

MUST_ACCEPT.forEach(([label, value, expected]) => {
    const got = AuthGate.sanitizeReturnPath(value);
    check(`sanitizer accepts ${label}`, got === expected, `expected ${expected}, got ${JSON.stringify(got)}`);
});

check('every protected page is a valid return destination',
    AuthGate.PROTECTED.every((p) => AuthGate.sanitizeReturnPath(p) === p));

const INVITE_TOKEN = 'Zm9v-QmFy_YmF6.9';
const inviteUrl = `admin-invitation-accept.html?token=${INVITE_TOKEN}`;

check('the invitation token survives the sanitizer intact',
    AuthGate.sanitizeReturnPath(inviteUrl) === inviteUrl,
    JSON.stringify(AuthGate.sanitizeReturnPath(inviteUrl)));
check('the invitation destination survives being stashed and read back',
    AuthGate.rememberIntendedDestination(inviteUrl) === inviteUrl);
check('an invitation link cannot smuggle a foreign origin past the sanitizer',
    AuthGate.sanitizeReturnPath(`https://evil.example/${inviteUrl}`) === null &&
    AuthGate.sanitizeReturnPath(`//evil.example/${inviteUrl}`) === null &&
    AuthGate.sanitizeReturnPath(`../public/${inviteUrl}`) === null &&
    AuthGate.sanitizeReturnPath(`https://medorbit.invalid@evil.example/${inviteUrl}`) === null);
check('a token-bearing value cannot become a javascript: destination',
    AuthGate.sanitizeReturnPath(`javascript:x='${inviteUrl}'`) === null);
AuthGate.clearIntendedDestination();

check('verify-email.html opens without a session',
    AuthGate.classify('verify-email.html') === 'AUTH_FLOW');
check('reset-password.html opens without a session',
    AuthGate.classify('reset-password.html') === 'AUTH_FLOW');
['verify-email.html', 'reset-password.html'].forEach((page) => {
    check(`${page} is never used as a post-sign-in destination`,
        AuthGate.sanitizeReturnPath(`${page}?token=${INVITE_TOKEN}`) === null,
        'bouncing back into the auth flow after signing in is a loop, not a destination');
});

const apiSource = frontendFile('src/js/api.js');
const authSource = frontendFile('src/js/auth.js');
const googleSource = frontendFile('src/js/google-signin.js');
const gateSource = frontendFile('src/js/auth-gate.js');

check('password login resolves its destination through the shared sanitizer',
    /intendedDestination\(\)/.test(authSource) &&
    /AuthGate\.readIntendedDestination\(\)/.test(authSource));
check('password login no longer reads ?redirect= directly',
    !/URLSearchParams\(window\.location\.search\)\.get\('redirect'\)/.test(authSource));
check('Google sign-in resolves its destination through the shared sanitizer',
    /AuthGate\.readIntendedDestination\(\)/.test(googleSource));
check('Google sign-in no longer reads ?redirect= directly',
    !/URLSearchParams\(window\.location\.search\)\.get\('redirect'\)/.test(googleSource));
check('sanitizeReturnPath is defined exactly once in the codebase',
    (gateSource.match(/function sanitizeReturnPath/g) || []).length === 1 &&
    !/function sanitizeReturnPath/.test(authSource) &&
    !/function sanitizeReturnPath/.test(googleSource) &&
    !/function sanitizeReturnPath/.test(apiSource));

check('the gate verifies against the server, not localStorage',
    /API\.users\.me\(\)/.test(gateSource));
check('a stored token alone never resolves a protected page',
    !/if\s*\(\s*localStorage\.getItem/.test(gateSource) &&
    /hasStoredSession/.test(gateSource));
check('verification is deduplicated per page load',
    /if \(verifyPromise\) return verifyPromise;/.test(gateSource));
check('a rejected identity (401/403) clears the session',
    /err\.status === 401 \|\| err\.status === 403[\s\S]{0,400}API\.clearSession\(\)/.test(gateSource));
check('an unreachable backend does NOT clear the session',
    /sessionState = 'unreachable'/.test(gateSource) &&
    !/unreachable'[\s\S]{0,120}clearSession/.test(gateSource));
check('token refresh is not reimplemented in the gate',
    !/\/auth\/refresh/.test(gateSource) && !/refreshToken\s*:/.test(gateSource));
check('denial leaves no protected URL in history',
    /window\.location\.replace\(PUBLIC_HOME/.test(gateSource));
check('the auth prompt strips its own query params to avoid a Back loop',
    /history\.replaceState/.test(gateSource));

check('the shield is installed during head parse, before body exists',
    /if \(isProtectedPage\) installShield\(\);/.test(gateSource));
check('the shield rule ships with the script rather than a stylesheet',
    /data-auth-gate="pending"[\s\S]{0,200}visibility:hidden !important/.test(gateSource));
check('the gate has a safe failure state instead of a permanently blank page',
    /renderStatusPanel\('offline'\)/.test(gateSource) && /authGate\.retry/.test(gateSource));

check('API.requireAuth defers its redirect to the gate when the gate is loaded',
    /if \(typeof AuthGate !== 'undefined'\) return false;/.test(apiSource));

check('navigation is intercepted by one delegated capture-phase listener',
    /document\.addEventListener\('click', handleDocumentClick, true\)/.test(gateSource));
check('modifier-clicks and new-tab clicks are left alone',
    /metaKey \|\| event\.ctrlKey \|\| event\.shiftKey \|\| event\.altKey/.test(gateSource));
check('cross-origin and non-http links are left alone',
    /url\.origin !== window\.location\.origin/.test(gateSource));

const homeHtml = frontendFile('public/home.html');
const homePageSource = frontendFile('src/js/pages/home.js');
check('the Home hero search routes through the gate instead of navigating',
    /AuthGate\.navigate\(/.test(homePageSource) &&
    !/window\.location\.href = target/.test(homePageSource));
check('Home adds no per-link auth handlers',
    !/addEventListener\('click'[\s\S]{0,200}openModal/.test(homePageSource));

const layoutSource = frontendFile('src/js/layout.js');
['feed.html', 'index.html', 'find-doctors.html', 'find-clinics.html', 'contact.html', 'symptom-checker.html']
    .forEach((href) => check(`guest nav still advertises ${href}`, layoutSource.includes(`'${href}'`)));
check('logout returns to Home', /API\.logout\(\)[\s\S]{0,120}home\.html/.test(layoutSource));

const gateCode = gateSource
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/^\s*\/\/.*$/gm, '');

check('the modal reuses the existing GoogleSignIn module',
    /GoogleSignIn\.init\('authModalGoogleBtn'/.test(gateSource));
check('the modal does not reimplement the Google flow',
    !/accounts\.google\.com\/gsi\/client/.test(gateCode) &&
    !/\/auth\/google/.test(gateCode) &&
    !/google\.accounts\.id\.initialize/.test(gateCode) &&
    !/setSession/.test(gateCode));
check('the Google client id still comes from the backend config endpoint',
    /API\.get\('\/config'/.test(googleSource) && !/client_id\s*:\s*['"][0-9]/.test(googleSource));
check('GoogleSignIn.init stays backward compatible for login/register',
    /function init\(containerId, options\)/.test(googleSource) &&
    /handlers = options \|\| \{\}/.test(googleSource));
['login', 'register'].forEach((pageName) => {
    check(`${pageName}.html still calls GoogleSignIn.init with one argument`,
        /GoogleSignIn\.init\('googleSignInBtn'\)/
            .test(frontendFile(`src/js/pages/${pageName}.js`)));
});

check('the dialog is announced to assistive technology',
    /role', 'dialog'/.test(gateSource) &&
    /aria-modal', 'true'/.test(gateSource) &&
    /aria-labelledby', 'authModalTitle'/.test(gateSource) &&
    /aria-describedby', 'authModalDesc'/.test(gateSource));
check('the dialog traps Tab and handles Escape',
    /event\.key === 'Escape'/.test(gateSource) && /event\.key !== 'Tab'/.test(gateSource));
check('focus moves in on open and is restored on close',
    /closeBtn\.focus\(\)/.test(gateSource) && /modalPreviousFocus\.focus\(\)/.test(gateSource));
check('the backdrop dismisses the dialog',
    /e\.target === backdrop\) closeModal/.test(gateSource));
check('no untrusted value reaches innerHTML in the modal',
    !/innerHTML\s*=\s*[^;]*(intended|destination|redirect|search)/i.test(gateSource));

const i18nSource = frontendFile('src/js/i18n.js');
const REQUIRED_KEYS = [
    'authModal.title', 'authModal.desc', 'authModal.createAccount',
    'authModal.haveAccount', 'authModal.signIn', 'authModal.close',
    'authGate.checking', 'authGate.offlineTitle', 'authGate.offlineDesc',
    'authGate.retry', 'authGate.backHome', 'authGate.expired',
    'auth.patientSignUp', 'auth.doctorSignUp',
    'auth.doctorRegisterTitle', 'auth.doctorRegisterDesc'
];
REQUIRED_KEYS.forEach((key) => {
    check(`i18n defines ${key} in both languages`,
        (i18nSource.match(new RegExp(`'${key.replace('.', '\\.')}':`, 'g')) || []).length === 2);
});
check('a missing translation preserves the HTML fallback instead of printing its key',
    /if \(text && text !== key\) el\.textContent = text;/.test(i18nSource));
check('the modal renders its copy from i18n, not hardcoded Arabic',
    /data-i18n="authModal\.title"/.test(gateSource) &&
    /data-i18n="authModal\.createAccount"/.test(gateSource));

const loginHtml = frontendFile('public/login.html');
const registerHtml = frontendFile('public/register.html');
const registerPageSource = frontendFile('src/js/pages/register.js');
check('the doctor option appears in the sign-up area',
    /href="register\.html\?intent=doctor"/.test(loginHtml) &&
    /data-i18n="auth\.doctorSignUp"/.test(loginHtml));
check('the doctor sign-up intent explains the protected application next step',
    /id="doctorApplicationIntro"/.test(registerHtml) &&
    /get\('intent'\) === 'doctor'/.test(registerPageSource));
check('role-specific landing pages are selected only after a shared login',
    /case 'doctor':[\s\S]{0,100}'my-schedule\.html'/.test(gateSource) &&
    /case 'admin':[\s\S]{0,100}'analytics\.html'/.test(gateSource) &&
    /case 'super_admin':[\s\S]{0,100}'admin-invitations\.html'/.test(gateSource) &&
    /isDoctorApplicationIntent/.test(gateSource) &&
    /'doctor-application\.html'/.test(gateSource) &&
    /AuthGate\.defaultLandingPage\(res\?\.data\?\.user\)/.test(authSource) &&
    /AuthGate\.defaultLandingPage\(res\?\.data\?\.user\)/.test(googleSource));

const componentsCss = frontendFile('src/css/components.css');
check('modal styles use theme tokens so dark mode follows automatically',
    /\.auth-modal \{[\s\S]{0,400}var\(--bg-card\)/.test(componentsCss));
check('the close button uses a logical inset so RTL mirrors it',
    /\.auth-modal-close \{[\s\S]{0,200}inset-inline-end/.test(componentsCss));
check('the modal respects prefers-reduced-motion',
    /prefers-reduced-motion[\s\S]{0,300}\.auth-modal/.test(componentsCss));
check('the modal cannot overflow the viewport on mobile',
    /\.auth-modal \{[\s\S]{0,400}max-width: 400px/.test(componentsCss) &&
    /max-height: calc\(100vh - 40px\)/.test(componentsCss));

const AUTH_FLOW_FILES = new Set(['auth.js', 'google-signin.js', 'api.js']);
const offenders = fs.readdirSync(frontendPath('src/js'))
    .filter((f) => f.endsWith('.js') && !AUTH_FLOW_FILES.has(f))
    .filter((f) => /auth:\s*false/.test(frontendFile(path.join('src/js', f))));
check('no product-data call opts out of the Authorization header',
    offenders.length === 0, offenders.join(', '));

console.log(`\n${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);

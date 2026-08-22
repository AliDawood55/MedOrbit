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

function read(relativePath) {
    return fs.readFileSync(path.resolve(__dirname, '..', relativePath), 'utf8');
}

console.log('\nAdmin application and notification UI tests\n');

const adminPage = read('public/admin-doctor-applications.html');
const adminController = read('src/js/admin-doctor-applications.js');
const api = read('src/js/api.js');
const layout = read('src/js/layout.js');
const notifications = read('src/js/notifications.js');
const layoutCss = read('src/css/layout.css');
const feedbackDashboard = read('src/js/feedback-dashboard.js');
const invitationPage = read('public/admin-invitations.html');
const invitationController = read('src/js/admin-invitations.js');
const contactController = read('src/js/admin-contact-messages.js');
const messagingController = read('src/js/direct-messages.js');

check(
    'admin page has one initializer and controller init is idempotent',
    (adminPage.match(/AdminDoctorApplications\.init\(\)/g) || []).length === 1 &&
    /if \(initialized\) return;[\s\S]*initialized = true;/.test(adminController)
);
check(
    'admin list fetch is bounded and has no polling loop',
    /if \(loadRequest\) return loadRequest;/.test(adminController) &&
    !/setInterval|setTimeout/.test(adminController)
);
check(
    '429 handling is localized and never immediately retries',
    /response\.status === 429/.test(api) &&
    /تم إرسال طلبات كثيرة خلال وقت قصير/.test(api) &&
    /Too many requests\. Please try again shortly\./.test(api) &&
    !/response\.status === 429[\s\S]{0,300}return request\(/.test(api)
);
check(
    'notification polling is deduplicated and no faster than 60 seconds',
    /NOTIFICATION_POLL_MS = 60_000/.test(layout) &&
    /if \(notificationRequest\) return notificationRequest;/.test(layout) &&
    !/setInterval/.test(layout)
);
check(
    'navbar badge is hidden at zero and bounded at 9+',
    /count > 9 \? '9\+'/.test(layout) &&
    /classList\.toggle\('hidden', count === 0\)/.test(layout) &&
    /background: var\(--danger\)/.test(layoutCss)
);
check(
    'notification click routes reviewer to pending application',
    /admin-doctor-applications\.html\?status=pending&application=/.test(notifications)
);
check(
    'notification click routes appointment and reminder records by role',
    /\['APPOINTMENT', 'APPOINTMENTS'\]/.test(notifications) &&
    /my-schedule\.html#appointments/.test(notifications) &&
    /my-appointments\.html/.test(notifications)
);
check(
    'notification is marked read only in an intentional action path',
    /async function openNotification[\s\S]*API\.notifications\.markRead/.test(notifications) &&
    !/async function loadNotifications[\s\S]{0,800}markRead/.test(notifications)
);
check(
    'badge refresh respects Retry-After without a retry storm',
    /err\.retryAfterSeconds \* 1000/.test(layout) &&
    /Math\.max\(nextDelay/.test(layout)
);
check(
    'public feedback background refresh cannot exhaust the old 15-minute bucket',
    /POLL_MS = 60_000/.test(feedbackDashboard) &&
    /if \(loadRequest\) return loadRequest;/.test(feedbackDashboard) &&
    !/setInterval/.test(feedbackDashboard) &&
    /document\.hidden/.test(feedbackDashboard)
);
check(
    'super-admin invitation create list and revoke are wired with server role verification',
    /admin-invitations\.js/.test(invitationPage) && /AuthGate\.getVerifiedUser\(\)/.test(invitationController) &&
    /role !== 'super_admin'/.test(invitationController) && /adminInvitations\.list/.test(invitationController) &&
    /adminInvitations\.create/.test(invitationController) && /adminInvitations\.revoke/.test(invitationController)
);
check(
    'contact inbox passes bounded offset pagination to the backend',
    /limit: PAGE_SIZE \+ 1, offset/.test(contactController) && /contactPrevPage/.test(contactController) && /contactNextPage/.test(contactController)
);
check(
    'Socket.IO client is loaded from the current backend rather than a stale third-party endpoint',
    /API\.getOrigin\(\)\+'\/socket\.io\/socket\.io\.js'/.test(messagingController)
);

(async () => {
    let fetchCalls = 0;
    const storage = new Map([['accessToken', 'focused-ui-token']]);
    const context = vm.createContext({
        console,
        URLSearchParams,
        CustomEvent: class CustomEvent { constructor(type) { this.type = type; } },
        localStorage: {
            getItem: (key) => storage.get(key) || null,
            setItem: (key, value) => storage.set(key, value),
            removeItem: (key) => storage.delete(key),
        },
        window: {
            MEDORBIT_API_URL: 'http://127.0.0.1:3001',
            location: { hostname: '127.0.0.1', protocol: 'http:', pathname: '/public/test.html', search: '' },
            dispatchEvent: () => {},
        },
        fetch: async () => {
            fetchCalls += 1;
            return {
                status: 429,
                ok: false,
                headers: { get: (name) => name.toLowerCase() === 'retry-after' ? '30' : null },
                json: async () => ({ success: false, error: { code: 'RATE_LIMITED', message: 'server copy' } }),
            };
        },
    });
    vm.runInContext(api, context);
    let rateError = null;
    try {
        await vm.runInContext("API.get('/focused-429')", context);
    } catch (err) {
        rateError = err;
    }
    check(
        'runtime API surfaces Retry-After and performs exactly one 429 request',
        fetchCalls === 1 && rateError?.status === 429 && rateError?.retryAfterSeconds === 30 &&
        rateError?.message === 'Too many requests. Please try again shortly.'
    );
    check(
        'runtime API resolves relative media paths and preserves complete URLs',
        vm.runInContext("API.assetUrl('/uploads/avatars/a.png')", context) === 'http://127.0.0.1:3001/uploads/avatars/a.png' &&
        vm.runInContext("API.assetUrl('https://cdn.example.test/a.png')", context) === 'https://cdn.example.test/a.png'
    );

    console.log(`\nAdmin notification UI: ${passed} passed, ${failed} failed`);
    process.exitCode = failed ? 1 : 0;
})().catch((err) => {
    console.error(err.stack || err.message);
    process.exitCode = 1;
});

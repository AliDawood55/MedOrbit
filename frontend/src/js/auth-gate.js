const AuthGate = (() => {
    'use strict';

const PUBLIC_HOME = 'home.html';

    const AUTH_FLOW = [
        'login.html',
        'register.html',
        'forgot-password.html',
        'reset-password.html',
        'verify-email.html'
    ];

const PROTECTED = [
        'admin-contact-messages.html',
        'admin-clinic-applications.html',
        'admin-doctor-applications.html',
        'admin-invitation-accept.html',
        'admin-invitations.html',
        'admin-social.html',
        'admin-users.html',
        'analytics.html',
        'avatar-preview.html',
        'billing.html',

'billing-sandbox.html',
        'book-appointment.html',
        'clinic.html',
        'clinic-application.html',
        'clinic-workspace.html',
        'contact.html',
        'dashboard.html',
        'direct-messages.html',
        'doctor-application.html',
        'doctor-posts.html',
        'doctor-profile-edit.html',
        'doctor.html',
        'drug-checker.html',
        'feed.html',
        'feedback.html',
        'feedback-review.html',
        'find-clinics.html',
        'find-doctors.html',
        'index.html',
        'my-appointments.html',
        'my-doctor.html',
        'my-patients.html',
        'my-prescriptions.html',
        'my-records.html',
        'my-reports.html',
        'my-schedule.html',
        'notifications.html',
        'patient-detail.html',
        'patient-profile.html',
        'profile.html',
        'report-summary.html',
        'symptom-checker.html'
    ];

    // Platform operators manage the service; they do not use personal-care
    // pages. This is presentation routing only — backend routes remain the
    // authorization authority for every request.
    const PLATFORM_EXCLUDED_PAGES = new Set([
        'avatar-preview.html', 'billing-sandbox.html', 'billing.html',
        'book-appointment.html', 'contact.html', 'direct-messages.html',
        'doctor-application.html', 'doctor-posts.html',
        'doctor-profile-edit.html', 'drug-checker.html', 'feedback.html',
        'index.html', 'my-appointments.html', 'my-doctor.html',
        'my-patients.html', 'my-prescriptions.html', 'my-records.html',
        'my-reports.html', 'my-schedule.html', 'patient-detail.html',
        'patient-profile.html', 'report-summary.html', 'symptom-checker.html'
    ]);

    /**
     * Roles each protected page is meant for, where the page and its backend
     * routes already restrict by role. Documentation and test-matrix input
     * ONLY — the gate deliberately does not enforce it, because authorization
     * belongs to the backend and to the existing per-page checks. Being
     * authenticated is not the same as being allowed; this module answers only
     * the first question and must never be read as answering the second.
     */
    const ROLE_RESTRICTED = {
        'analytics.html': ['admin', 'super_admin'],
        'admin-contact-messages.html': ['admin', 'super_admin'],
        'admin-clinic-applications.html': ['admin', 'super_admin'],
        'admin-doctor-applications.html': ['admin', 'super_admin'],
        'admin-social.html': ['admin', 'super_admin'],
        'admin-users.html': ['admin', 'super_admin'],
        'admin-invitations.html': ['super_admin'],
         // admin-invitation-accept.html is deliberately absent. Its backend
        // route (POST /api/admin/invitations/accept) requires authenticate but
        // NOT authorizeAdmin: the whole point of an invitation is that the
        // invited account is not an admin yet. It is PROTECTED — you must be
        // signed in as the invited account — and nothing more. Listing it here
        // would describe a restriction the backend does not have, and would be
        // the first step towards a frontend authorization system.
         'doctor-posts.html': ['doctor'],
         'clinic-workspace.html': ['clinic'],
        'doctor-profile-edit.html': ['doctor'],
        'my-patients.html': ['doctor'],
        'my-schedule.html': ['doctor'],
        'patient-detail.html': ['doctor'],
        'book-appointment.html': ['patient'],
        'my-appointments.html': ['patient'],
        'my-doctor.html': ['patient'],
        'my-prescriptions.html': ['patient'],
        'my-records.html': ['patient'],
        'patient-profile.html': ['patient']
    };

    const KNOWN_PAGES = new Set([PUBLIC_HOME].concat(AUTH_FLOW, PROTECTED));

    const CLASS_PUBLIC_HOME = 'PUBLIC_HOME';
    const CLASS_AUTH_FLOW = 'AUTH_FLOW';
    const CLASS_PROTECTED = 'PROTECTED';

    const NEXT_STORAGE_KEY = 'medorbit_auth_next';
    const VERIFY_TIMEOUT_MS = 12000;

    function classify(pageName) {
        if (pageName === PUBLIC_HOME) return CLASS_PUBLIC_HOME;
        if (AUTH_FLOW.indexOf(pageName) !== -1) return CLASS_AUTH_FLOW;
        return CLASS_PROTECTED;
    }

    function currentPage() {
        const last = window.location.pathname.split('/').pop();

return last || 'index.html';
    }

    function currentReturnPath() {
        return currentPage() + window.location.search + window.location.hash;
    }

const SANITIZER_BASE = 'https://medorbit.invalid/public/';
    const SANITIZER_ORIGIN = 'https://medorbit.invalid';
    const SANITIZER_DIR = '/public/';

function sanitizeReturnPath(raw) {
        if (typeof raw !== 'string') return null;

        const value = raw.trim();
        if (!value || value.length > 512) return null;

if (/[\x00-\x1F\x7F]/.test(value)) return null;

if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) return null;

if (/^[/\\]{2}/.test(value)) return null;

const pathPart = value.split(/[?#]/)[0];
        if (!/^[A-Za-z0-9._-]+\.html$/.test(pathPart)) return null;

        let url;
        try {
            url = new URL(value, SANITIZER_BASE);
        } catch {
            return null;
        }

        if (url.origin !== SANITIZER_ORIGIN) return null;

        const dir = url.pathname.slice(0, url.pathname.lastIndexOf('/') + 1);
        if (dir !== SANITIZER_DIR) return null;

        const pageName = url.pathname.slice(dir.length);
        if (!KNOWN_PAGES.has(pageName)) return null;

if (classify(pageName) === CLASS_AUTH_FLOW) return null;

        return pageName + url.search + url.hash;
    }

function readIntendedDestination() {
        const params = new URLSearchParams(window.location.search);
        const fromQuery = sanitizeReturnPath(params.get('redirect') || params.get('next'));
        if (fromQuery) return fromQuery;

        try {
            return sanitizeReturnPath(sessionStorage.getItem(NEXT_STORAGE_KEY));
        } catch {
            return null;
        }
    }

    function rememberIntendedDestination(path) {
        const safe = sanitizeReturnPath(path);
        try {
            if (safe) sessionStorage.setItem(NEXT_STORAGE_KEY, safe);
            else sessionStorage.removeItem(NEXT_STORAGE_KEY);
        } catch {

        }
        return safe;
    }

    function clearIntendedDestination() {
        try {
            sessionStorage.removeItem(NEXT_STORAGE_KEY);
        } catch {

        }
    }

function isDoctorApplicationIntent() {
        return new URLSearchParams(window.location.search).get('intent') === 'doctor';
    }

    function isClinicApplicationIntent() {
        return new URLSearchParams(window.location.search).get('intent') === 'clinic';
    }

    function defaultLandingPage(user) {

if (user?.role === 'patient' && isDoctorApplicationIntent()) {
            return 'doctor-application.html';
        }
        if (user?.role === 'clinic' && user?.clinic_account_status !== 'approved') {
            return 'clinic-application.html';
        }
        switch (user?.role) {
            case 'doctor':
                return 'my-schedule.html';
            case 'clinic':
                return 'clinic-workspace.html';
            case 'admin':
                return 'analytics.html';
            case 'super_admin':
                return 'admin-invitations.html';
            default:
                return 'dashboard.html';
        }
    }

const thisPage = currentPage();
    const pageClass = classify(thisPage);
    const isProtectedPage = pageClass === CLASS_PROTECTED;

    let verifyPromise = null;
    let verifiedUser = null;
    let sessionState = 'unknown';

    const scriptDir = (() => {
        const src = document.currentScript && document.currentScript.src;
        if (!src) return '../src/js/';
        return src.slice(0, src.lastIndexOf('/') + 1);
    })();

function installShield() {
        const style = document.createElement('style');
        style.id = 'authGateShield';
        style.textContent =
            'html[data-auth-gate="pending"] body > *:not([data-auth-ui]),' +
            'html[data-auth-gate="blocked"] body > *:not([data-auth-ui])' +
            '{visibility:hidden !important;}' +
            'html[data-auth-gate="pending"] body,' +
            'html[data-auth-gate="blocked"] body' +
            '{overflow:hidden !important;background:var(--bg,#F9FAFB) !important;}';
        (document.head || document.documentElement).appendChild(style);
        document.documentElement.setAttribute('data-auth-gate', 'pending');
    }

    function raiseShield(state) {
        document.documentElement.setAttribute('data-auth-gate', state);
    }

    function lowerShield() {
        document.documentElement.removeAttribute('data-auth-gate');
        removeStatusPanel();
    }

    if (isProtectedPage) installShield();

function tr(key, fallbackAr, fallbackEn) {
        if (typeof I18n !== 'undefined' && typeof I18n.t === 'function') {
            const value = I18n.t(key);
            if (value && value !== key) return value;
        }
        const ar = (typeof I18n !== 'undefined' && typeof I18n.getLang === 'function')
            ? I18n.getLang() === 'ar'
            : (document.documentElement.lang || 'ar') === 'ar';
        return ar ? fallbackAr : fallbackEn;
    }

    function removeStatusPanel() {
        const existing = document.getElementById('authGateStatus');
        if (existing) existing.remove();
    }

    function renderStatusPanel(mode) {
        if (!document.body) return;
        removeStatusPanel();

        const panel = document.createElement('div');
        panel.id = 'authGateStatus';
        panel.className = 'auth-gate-status';
        panel.setAttribute('data-auth-ui', '');
        panel.setAttribute('role', 'status');
        panel.setAttribute('aria-live', 'polite');

        const card = document.createElement('div');
        card.className = 'auth-gate-status-card';

        if (mode === 'checking') {
            const spinner = document.createElement('div');
            spinner.className = 'auth-gate-spinner';
            spinner.setAttribute('aria-hidden', 'true');
            card.appendChild(spinner);

            const title = document.createElement('p');
            title.className = 'auth-gate-status-title';
            title.textContent = tr('authGate.checking', 'جارٍ التحقق من جلستك…', 'Verifying your session…');
            card.appendChild(title);
        } else {
            const icon = document.createElement('div');
            icon.className = 'auth-gate-status-icon';
            icon.setAttribute('aria-hidden', 'true');
            const glyph = document.createElement('i');
            glyph.className = 'fas fa-triangle-exclamation';
            icon.appendChild(glyph);
            card.appendChild(icon);

            const title = document.createElement('p');
            title.className = 'auth-gate-status-title';
            title.textContent = tr('authGate.offlineTitle', 'تعذّر التحقق من جلستك', 'Could not verify your session');
            card.appendChild(title);

            const desc = document.createElement('p');
            desc.className = 'auth-gate-status-desc';
            desc.textContent = tr(
                'authGate.offlineDesc',
                'لم نتمكن من الوصول إلى خدمة MedOrbit. لم يتم تسجيل خروجك — تحقق من اتصالك ثم أعد المحاولة.',
                'We could not reach the MedOrbit service. You have not been signed out — check your connection and try again.'
            );
            card.appendChild(desc);

            const actions = document.createElement('div');
            actions.className = 'auth-gate-status-actions';

            const retry = document.createElement('button');
            retry.type = 'button';
            retry.className = 'btn btn-primary';
            retry.textContent = tr('authGate.retry', 'إعادة المحاولة', 'Retry');
            retry.addEventListener('click', () => {
                raiseShield('pending');
                renderStatusPanel('checking');
                verifyPromise = null;
                resolveProtectedPage();
            });
            actions.appendChild(retry);

            const home = document.createElement('a');
            home.className = 'btn btn-secondary';
            home.href = PUBLIC_HOME;
            home.textContent = tr('authGate.backHome', 'العودة إلى الرئيسية', 'Back to Home');
            actions.appendChild(home);

            card.appendChild(actions);
        }

        panel.appendChild(card);
        document.body.appendChild(panel);
    }

function hasStoredSession() {
        if (typeof API === 'undefined') return false;
        return !!(API.getAccessToken() || API.getRefreshToken());
    }

function verifySession(options) {
        const force = !!(options && options.force);
        if (force) verifyPromise = null;
        if (verifyPromise) return verifyPromise;

        verifyPromise = (async () => {
            if (typeof API === 'undefined') {
                sessionState = 'unreachable';
                return sessionState;
            }

if (!hasStoredSession()) {
                verifiedUser = null;
                sessionState = 'invalid';
                return sessionState;
            }

            try {
                const res = await API.users.me();
                verifiedUser = (res && res.data) || null;
                sessionState = 'valid';
            } catch (err) {
                if (err && (err.status === 401 || err.status === 403)) {

verifiedUser = null;
                    sessionState = 'invalid';
                    API.clearSession();
                } else {

sessionState = 'unreachable';
                }
            }

            return sessionState;
        })();

        return verifyPromise;
    }

    function withTimeout(promise, ms) {
        return Promise.race([
            promise,
            new Promise((resolve) => setTimeout(() => resolve('unreachable'), ms))
        ]);
    }

function denyToHome(reason) {
        const intended = rememberIntendedDestination(currentReturnPath());
        const params = new URLSearchParams();
        params.set('auth', reason);
        if (intended) params.set('next', intended);

window.location.replace(PUBLIC_HOME + '?' + params.toString());
    }

    function redirectPlatformOperatorFromPersonalCare() {
        const role = String(verifiedUser?.role || '').trim().toLowerCase();
        if (!['admin', 'super_admin'].includes(role) || !PLATFORM_EXCLUDED_PAGES.has(thisPage)) return false;
        window.location.replace('dashboard.html?access=platform');
        return true;
    }

    // ================= PROTECTED PAGE BOOT =================

    async function resolveProtectedPage() {

if (window.__medorbitNavigatingAway) return;

        if (typeof API === 'undefined') {
            raiseShield('blocked');
            renderStatusPanel('offline');
            return;
        }

        renderStatusPanel('checking');

        const state = await withTimeout(verifySession(), VERIFY_TIMEOUT_MS);

        if (state === 'valid') {
            if (thisPage === 'clinic-workspace.html' &&
                verifiedUser?.role === 'clinic' &&
                verifiedUser?.clinic_account_status !== 'approved') {
                window.location.replace('clinic-application.html');
                return;
            }
            if (redirectPlatformOperatorFromPersonalCare()) return;
            lowerShield();
            clearIntendedDestination();
            document.dispatchEvent(new CustomEvent('authgate:allowed', { detail: { user: verifiedUser } }));
            return;
        }

        if (state === 'invalid') {
            denyToHome('required');
            return;
        }

        raiseShield('blocked');
        renderStatusPanel('offline');
    }

async function resolvePublicPage() {

if (typeof API === 'undefined' || !hasStoredSession()) return;

        const state = await verifySession();
        // Sign-in and registration are entry pages only. A verified session
        // must not be able to open them again, regardless of account role.
        if (state === 'valid' && (thisPage === 'login.html' || thisPage === 'register.html')) {
            window.location.replace(PUBLIC_HOME);
            return;
        }
        if (state === 'invalid') {

document.dispatchEvent(new CustomEvent('authgate:signedout'));
        }
    }

function isSignedInEnough() {

if (sessionState === 'valid') return true;
        if (sessionState === 'invalid') return false;
        return hasStoredSession();
    }

function pageFromAnchor(anchor) {
        const raw = anchor.getAttribute('href');
        if (!raw) return null;

        const trimmed = raw.trim();
        if (!trimmed || trimmed.charAt(0) === '#') return null;
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed)) return null;

        let url;
        try {
            url = new URL(anchor.href, window.location.href);
        } catch {
            return null;
        }
        if (url.origin !== window.location.origin) return null;

        return url.pathname.split('/').pop() || 'index.html';
    }

    function handleDocumentClick(event) {
        if (event.defaultPrevented) return;
        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

        const anchor = event.target && event.target.closest && event.target.closest('a[href]');
        if (!anchor) return;
        if (anchor.target && anchor.target !== '_self') return;
        if (anchor.hasAttribute('download')) return;
        if (anchor.hasAttribute('data-auth-bypass')) return;

        const target = pageFromAnchor(anchor);
        if (!target || classify(target) !== CLASS_PROTECTED) return;
        if (isSignedInEnough()) return;

        event.preventDefault();
        event.stopPropagation();

        const url = new URL(anchor.href, window.location.href);
        const name = url.pathname.split('/').pop() || 'index.html';
        requireAuthFor(name + url.search + url.hash, anchor);
    }

function navigate(destination, trigger) {
        const safe = sanitizeReturnPath(destination);
        if (!safe) return false;

        const targetPage = safe.split('?')[0].split('#')[0];
        if (classify(targetPage) !== CLASS_PROTECTED || isSignedInEnough()) {
            window.location.href = safe;
            return true;
        }

        requireAuthFor(safe, trigger);
        return false;
    }

    function requireAuthFor(destination, trigger) {
        const safe = rememberIntendedDestination(destination);
        openModal({ intended: safe, trigger });
    }

let modalEl = null;
    let modalPreviousFocus = null;
    let modalIntended = null;
    let googleLoaderPromise = null;
    let googleMounted = false;

    function loadGoogleSignIn() {
        if (typeof GoogleSignIn !== 'undefined') return Promise.resolve(true);
        if (googleLoaderPromise) return googleLoaderPromise;

        googleLoaderPromise = new Promise((resolve) => {
            const script = document.createElement('script');
            script.src = scriptDir + 'google-signin.js';
            script.async = true;
            script.onload = () => resolve(typeof GoogleSignIn !== 'undefined');
            script.onerror = () => resolve(false);
            document.head.appendChild(script);
        });
        return googleLoaderPromise;
    }

    function buildModal() {
        const backdrop = document.createElement('div');
        backdrop.className = 'auth-modal-backdrop';
        backdrop.id = 'authModal';
        backdrop.setAttribute('data-auth-ui', '');
        backdrop.hidden = true;

        const dialog = document.createElement('div');
        dialog.className = 'auth-modal';
        dialog.setAttribute('role', 'dialog');
        dialog.setAttribute('aria-modal', 'true');
        dialog.setAttribute('aria-labelledby', 'authModalTitle');
        dialog.setAttribute('aria-describedby', 'authModalDesc');

dialog.innerHTML =
            '<button type="button" class="auth-modal-close" id="authModalClose" data-i18n-aria="authModal.close" aria-label="Close">' +
                '<i class="fas fa-times" aria-hidden="true"></i>' +
            '</button>' +
            '<div class="auth-modal-brand" aria-hidden="true">' +
                '<div class="brand-icon"><i class="fas fa-heartbeat"></i></div>' +
            '</div>' +
            '<h2 class="auth-modal-title" id="authModalTitle" data-i18n="authModal.title"></h2>' +
            '<p class="auth-modal-desc" id="authModalDesc" data-i18n="authModal.desc"></p>' +
            '<div class="auth-modal-alert hidden" id="authModalAlert" role="alert"></div>' +
            '<div class="auth-modal-oauth" id="authModalOauth">' +
                '<div class="google-signin-container" id="authModalGoogleBtn"></div>' +
            '</div>' +
            '<div class="auth-modal-divider" id="authModalDivider"><span data-i18n="auth.orDivider"></span></div>' +
            '<a class="btn btn-primary auth-modal-register" id="authModalRegister" data-auth-bypass href="register.html">' +
                '<span data-i18n="authModal.createAccount"></span>' +
            '</a>' +
            '<p class="auth-modal-signin">' +
                '<span data-i18n="authModal.haveAccount"></span> ' +
                '<a id="authModalLogin" data-auth-bypass href="login.html" data-i18n="authModal.signIn"></a>' +
            '</p>';

        backdrop.appendChild(dialog);
        document.body.appendChild(backdrop);

        backdrop.addEventListener('click', (e) => {
            if (e.target === backdrop) closeModal();
        });
        backdrop.querySelector('#authModalClose').addEventListener('click', () => closeModal());
        backdrop.addEventListener('keydown', handleModalKeydown);

        return backdrop;
    }

    function focusableInModal() {
        if (!modalEl) return [];
        const nodes = modalEl.querySelectorAll(
            'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])'
        );
        return Array.prototype.filter.call(nodes, (el) => el.offsetParent !== null || el === document.activeElement);
    }

    function handleModalKeydown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            closeModal();
            return;
        }
        if (event.key !== 'Tab') return;

        const items = focusableInModal();
        if (!items.length) return;

        const first = items[0];
        const last = items[items.length - 1];
        const active = document.activeElement;

if (event.shiftKey && (active === first || !modalEl.contains(active))) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && active === last) {
            event.preventDefault();
            first.focus();
        }
    }

    function setModalAlert(message) {
        if (!modalEl) return;
        const box = modalEl.querySelector('#authModalAlert');
        if (!box) return;
        box.textContent = message || '';
        box.classList.toggle('hidden', !message);
    }

    function applyModalLinks() {
        const suffix = modalIntended ? '?redirect=' + encodeURIComponent(modalIntended) : '';
        const register = modalEl.querySelector('#authModalRegister');
        const login = modalEl.querySelector('#authModalLogin');
        if (register) register.href = 'register.html' + suffix;
        if (login) login.href = 'login.html' + suffix;
    }

    function openModal(options) {
        const opts = options || {};
        if (!document.body) return;
        if (!modalEl) modalEl = buildModal();

        modalIntended = sanitizeReturnPath(opts.intended) || readIntendedDestination();
        modalPreviousFocus = opts.trigger || document.activeElement;

        applyModalLinks();
        setModalAlert(opts.message);

        modalEl.hidden = false;

        requestAnimationFrame(() => modalEl.classList.add('open'));

        if (typeof Dom !== 'undefined' && typeof Dom.lockScroll === 'function') Dom.lockScroll();
        else document.body.classList.add('scroll-locked');

        if (typeof I18n !== 'undefined') I18n.apply();

        const closeBtn = modalEl.querySelector('#authModalClose');
        if (closeBtn) closeBtn.focus();

        mountGoogleButton();
    }

    function closeModal() {
        if (!modalEl || modalEl.hidden) return;

        modalEl.classList.remove('open');
        modalEl.hidden = true;

        if (typeof Dom !== 'undefined' && typeof Dom.unlockScroll === 'function') Dom.unlockScroll();
        else document.body.classList.remove('scroll-locked');

        if (modalPreviousFocus && typeof modalPreviousFocus.focus === 'function' &&
            document.contains(modalPreviousFocus)) {
            modalPreviousFocus.focus();
        }
        modalPreviousFocus = null;
    }

async function mountGoogleButton() {
        if (googleMounted) return;

        const ok = await loadGoogleSignIn();
        if (!ok || typeof GoogleSignIn === 'undefined') {
            hideModalOauth();
            return;
        }

        googleMounted = true;
        GoogleSignIn.init('authModalGoogleBtn', {
            onSuccess: () => {
                closeModal();
                const destination = modalIntended || readIntendedDestination() || defaultLandingPage();
                clearIntendedDestination();
                window.location.href = destination;
            },
            onError: (message) => {
                setModalAlert(message);
            },
            onUnavailable: () => {
                googleMounted = false;
                hideModalOauth();
            }
        });
    }

    function hideModalOauth() {
        if (!modalEl) return;
        const oauth = modalEl.querySelector('#authModalOauth');
        const divider = modalEl.querySelector('#authModalDivider');
        if (oauth) oauth.classList.add('hidden');
        if (divider) divider.classList.add('hidden');
    }

function handleHomeAuthPrompt() {
        if (pageClass !== CLASS_PUBLIC_HOME) return;

        const params = new URLSearchParams(window.location.search);
        const reason = params.get('auth');
        if (!reason) return;

        const intended = sanitizeReturnPath(params.get('next')) || readIntendedDestination();

try {
            window.history.replaceState(null, '', window.location.pathname + window.location.hash);
        } catch {

        }

if (reason !== 'expired' && isSignedInEnough()) return;

        openModal({
            intended,
            message: reason === 'expired'
                ? tr('authGate.expired', 'انتهت جلستك. سجّل الدخول للمتابعة.', 'Your session has ended. Please sign in to continue.')
                : null
        });
    }

function handleAuthChanged() {
        if (typeof API === 'undefined') return;

        if (API.isAuthenticated()) {

            if (sessionState === 'invalid') {
                sessionState = 'unknown';
                verifyPromise = null;
            }
            return;
        }

verifiedUser = null;
        sessionState = 'invalid';
        verifyPromise = null;

        if (!isProtectedPage) return;

        if (document.documentElement.getAttribute('data-auth-gate') === 'pending') return;

        raiseShield('pending');
        denyToHome('expired');
    }

function boot() {
        try {
            document.addEventListener('click', handleDocumentClick, true);
            window.addEventListener('auth:changed', handleAuthChanged);

            if (isProtectedPage) {
                resolveProtectedPage();
            } else {
                handleHomeAuthPrompt();
                resolvePublicPage();
            }
        } catch {

if (isProtectedPage) {
                raiseShield('blocked');
                renderStatusPanel('offline');
            }
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot);
    } else {
        boot();
    }

window.__medorbitAuthGateReady = true;

    return {

        PUBLIC_HOME: PUBLIC_HOME,
        AUTH_FLOW: AUTH_FLOW,
        PROTECTED: PROTECTED,
        ROLE_RESTRICTED: ROLE_RESTRICTED,
        classify: classify,
        currentPage: currentPage,
        pageClassification: () => pageClass,

        sanitizeReturnPath: sanitizeReturnPath,
        readIntendedDestination: readIntendedDestination,
        rememberIntendedDestination: rememberIntendedDestination,
        clearIntendedDestination: clearIntendedDestination,
        defaultLandingPage: defaultLandingPage,
        isDoctorApplicationIntent: isDoctorApplicationIntent,
         isClinicApplicationIntent: isClinicApplicationIntent,
         // session
        verifySession: verifySession,
        getVerifiedUser: () => verifiedUser,
        getSessionState: () => sessionState,

        navigate: navigate,
        requireAuthFor: requireAuthFor,
        openModal: openModal,
        closeModal: closeModal
    };
})();

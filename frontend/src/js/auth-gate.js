/**
 * MedOrbit v2 - Global Authentication Gate
 *
 * ONE source of truth for "who is allowed to see which page". Loaded as the
 * first script in <head> on every page under frontend/public, so it can hide
 * protected markup before the browser paints it.
 *
 * Policy (deny by default):
 *   PUBLIC_HOME  home.html only — the public product landing page.
 *   AUTH_FLOW    the minimum pages needed to sign in / create / recover an
 *                account. Authentication infrastructure, not product content.
 *   PROTECTED    every other page under frontend/public, including pages that
 *                do not exist yet: an unknown page name is treated as
 *                protected, so a new product page is guarded the day it is
 *                created rather than the day someone remembers to list it.
 *
 * Lifecycle on a protected page:
 *   head parse   classify page -> data-auth-gate="pending" + critical CSS
 *                (protected markup is never painted)
 *   DOMContent   verify the session against the server, once per page load
 *   verified     attribute removed -> page becomes visible
 *   rejected     session cleared -> location.replace to home.html + modal
 *   unreachable  "checking your session" panel with Retry; the session is NOT
 *                erased and protected markup stays hidden
 *
 * A gate that fails to load hides nothing, so each protected page also carries
 * a few inline lines in <head> that raise the same shield and set a watchdog.
 * They cannot 404 the way this file can. If this module never reports itself
 * ready, the watchdog sends the browser to Home instead of revealing the page.
 * That covers the shell only: the HTML itself is still a public static file,
 * and the data inside it is protected by the API, not by this shield.
 *
 * A token sitting in localStorage proves nothing, so the gate never treats it
 * as proof. The only thing that opens a protected page is a 200 from
 * GET /api/users/me through the shared API client (which owns the single
 * refresh-token retry). Backend authentication/authorization stays
 * authoritative for data — this module governs page presentation only.
 */
const AuthGate = (() => {
    'use strict';

    // ================= PAGE REGISTRY =================
    // Listing a page here does NOT make it public. Only the two explicit
    // classifications below are reachable without a verified session.

    const PUBLIC_HOME = 'home.html';

    const AUTH_FLOW = [
        'login.html',
        'register.html',
        'forgot-password.html',
        'reset-password.html',
        'verify-email.html'
    ];

    // Known product pages. Kept as a list purely so the return-path sanitizer
    // and the automated route matrix can enumerate real destinations —
    // classification itself is "not PUBLIC_HOME and not AUTH_FLOW".
    const PROTECTED = [
        'admin-contact-messages.html',
        'admin-doctor-applications.html',
        'admin-invitation-accept.html',
        'admin-invitations.html',
        'admin-social.html',
        'analytics.html',
        'avatar-preview.html',
        'billing.html',
        // The sandbox checkout stands in for a provider-hosted page, but it
        // is served from our own origin and reads a checkout attempt scoped
        // to the caller — so it is protected like any other page. A signed-out
        // browser has nothing to see there.
        'billing-sandbox.html',
        'book-appointment.html',
        'clinic.html',
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
        'admin-doctor-applications.html': ['admin', 'super_admin'],
        'admin-social.html': ['admin', 'super_admin'],
        'admin-invitations.html': ['super_admin'],
        // admin-invitation-accept.html is deliberately absent. Its backend
        // route (POST /api/admin/invitations/accept) requires authenticate but
        // NOT authorizeAdmin: the whole point of an invitation is that the
        // invited account is not an admin yet. It is PROTECTED — you must be
        // signed in as the invited account — and nothing more. Listing it here
        // would describe a restriction the backend does not have, and would be
        // the first step towards a frontend authorization system.
        'doctor-posts.html': ['doctor'],
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
        return CLASS_PROTECTED; // deny by default, unknown pages included
    }

    function currentPage() {
        const last = window.location.pathname.split('/').pop();
        // A bare directory URL resolves to the app's entry point, which is the
        // chat app (index.html) — a protected page, not Home.
        return last || 'index.html';
    }

    function currentReturnPath() {
        return currentPage() + window.location.search + window.location.hash;
    }

    // ================= RETURN-PATH SANITIZER =================
    // The single validator for every ?redirect= / intended-destination value in
    // the app (global gate, auth modal, password login, Google sign-in).
    // Anything that is not a bare, known, same-directory MedOrbit page is
    // rejected outright rather than repaired.

    const SANITIZER_BASE = 'https://medorbit.invalid/public/';
    const SANITIZER_ORIGIN = 'https://medorbit.invalid';
    const SANITIZER_DIR = '/public/';

    /**
     * @returns {string|null} "page.html?query#hash" when the value is a safe
     * in-app destination, otherwise null. Callers MUST treat null as "no
     * destination" and fall back to their own default — never to the raw input.
     */
    function sanitizeReturnPath(raw) {
        if (typeof raw !== 'string') return null;

        const value = raw.trim();
        if (!value || value.length > 512) return null;

        // Control characters, including the \t \n \r that browsers strip from a
        // URL before parsing it — which is how "java\nscript:" style payloads
        // survive a naive scheme check.
        if (/[\x00-\x1F\x7F]/.test(value)) return null;

        // Any explicit scheme: javascript:, data:, http:, https:, vbscript:, ...
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(value)) return null;

        // Protocol-relative ("//evil.example") and the backslash variants some
        // browsers normalise to "//".
        if (/^[/\\]{2}/.test(value)) return null;

        // Only a bare page filename is a valid destination — no directories, no
        // traversal, no percent-encoding. Checked on the raw value before any
        // URL normalisation, because normalisation is exactly what turns
        // "../public/dashboard.html" or "%2e%2e%2fadmin.html" into something
        // that looks local. A legitimate caller never produces either.
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
        if (dir !== SANITIZER_DIR) return null; // ../ traversal, subdirectories

        const pageName = url.pathname.slice(dir.length);
        if (!KNOWN_PAGES.has(pageName)) return null; // deny by default

        // Bouncing back into the auth flow after signing in is a loop, not a
        // destination.
        if (classify(pageName) === CLASS_AUTH_FLOW) return null;

        return pageName + url.search + url.hash;
    }

    /**
     * The intended destination for the current sign-in attempt: the ?redirect=
     * parameter first (so existing login.html?redirect=... links keep working),
     * then whatever the gate stashed when it bounced someone.
     */
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
            // Private mode / storage disabled: ?redirect= still carries it.
        }
        return safe;
    }

    function clearIntendedDestination() {
        try {
            sessionStorage.removeItem(NEXT_STORAGE_KEY);
        } catch {
            /* nothing to clean up */
        }
    }

    /**
     * Where an authenticated user lands when there is no safe intended
     * destination. Authentication is shared by every account type; the role
     * changes only the useful first page, never what the account may access.
     */
    function isDoctorApplicationIntent() {
        return new URLSearchParams(window.location.search).get('intent') === 'doctor';
    }

    function defaultLandingPage(user) {
        // Public registration deliberately creates a patient account. This
        // explicit sign-up intent is the only client-side convenience: the
        // protected application route and server still decide eligibility.
        if (user?.role === 'patient' && isDoctorApplicationIntent()) {
            return 'doctor-application.html';
        }
        switch (user?.role) {
            case 'doctor':
                return 'my-schedule.html';
            case 'admin':
                return 'analytics.html';
            case 'super_admin':
                return 'admin-invitations.html';
            default:
                return 'dashboard.html';
        }
    }

    // ================= PAGE STATE =================

    const thisPage = currentPage();
    const pageClass = classify(thisPage);
    const isProtectedPage = pageClass === CLASS_PROTECTED;

    let verifyPromise = null;     // in-flight GET /users/me for this page load
    let verifiedUser = null;      // last server-confirmed identity
    let sessionState = 'unknown'; // unknown | valid | invalid | unreachable

    const scriptDir = (() => {
        const src = document.currentScript && document.currentScript.src;
        if (!src) return '../src/js/';
        return src.slice(0, src.lastIndexOf('/') + 1);
    })();

    // ================= NO-FLASH SHIELD =================
    // Injected by this script rather than declared in a stylesheet, so the rule
    // cannot arrive late (or not at all) relative to the attribute that uses
    // it. Elements the gate owns carry [data-auth-ui] and stay visible.

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

    // ================= STATUS PANEL =================
    // The safe failure state: shown instead of protected content when the
    // session cannot be verified (backend down, request failed). Never
    // presented as a credential problem — an outage is not a rejected identity.

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

    // ================= SESSION VERIFICATION =================

    function hasStoredSession() {
        if (typeof API === 'undefined') return false;
        return !!(API.getAccessToken() || API.getRefreshToken());
    }

    /**
     * Verifies the session against the server, at most once per page load.
     * Every caller shares the same in-flight promise, so a page that boots
     * several components still issues a single GET /users/me.
     *
     * Expired access tokens are deliberately not handled here: API.request()
     * already refreshes once on a 401 and retries, and clears the session when
     * the refresh itself fails. Duplicating that would create a second token
     * system with its own bugs.
     *
     * @returns {Promise<'valid'|'invalid'|'unreachable'>}
     */
    function verifySession(options) {
        const force = !!(options && options.force);
        if (force) verifyPromise = null;
        if (verifyPromise) return verifyPromise;

        verifyPromise = (async () => {
            if (typeof API === 'undefined') {
                sessionState = 'unreachable';
                return sessionState;
            }

            // No credentials at all — a definitive "not signed in" that needs no
            // network round trip.
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
                    // The server rejected the identity: forged token, deleted or
                    // disabled user, authorization-version bump, or a refresh
                    // that failed. Clearing the session here is correct.
                    verifiedUser = null;
                    sessionState = 'invalid';
                    API.clearSession();
                } else {
                    // Everything else — 5xx, 429, or no status at all because the
                    // fetch never completed (offline, DNS, refused, CORS). The
                    // session may well be fine, so it is kept; the page stays
                    // closed until we actually know.
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

    // ================= DENY =================

    function denyToHome(reason) {
        const intended = rememberIntendedDestination(currentReturnPath());
        const params = new URLSearchParams();
        params.set('auth', reason);
        if (intended) params.set('next', intended);

        // replace(), not assign(): the protected URL must not stay in history,
        // or Back from Home would bounce straight into the gate again.
        window.location.replace(PUBLIC_HOME + '?' + params.toString());
    }

    // ================= PROTECTED PAGE BOOT =================

    async function resolveProtectedPage() {
        // redirect-guard.js owns this load (a password-reset / verify-email
        // link landing on index.html); it has already started navigating to the
        // dedicated auth page, so the gate must not race it.
        if (window.__medorbitNavigatingAway) return;

        if (typeof API === 'undefined') {
            raiseShield('blocked');
            renderStatusPanel('offline');
            return;
        }

        renderStatusPanel('checking');

        const state = await withTimeout(verifySession(), VERIFY_TIMEOUT_MS);

        if (state === 'valid') {
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

    // ================= PUBLIC / AUTH-FLOW PAGE BOOT =================

    async function resolvePublicPage() {
        // Home and the auth pages render for everyone. A stored session is
        // still confirmed in the background so the header, the CTA state and
        // the navigation interception below reflect reality rather than a
        // leftover token — reusing the same deduplicated request, not an extra one.
        if (typeof API === 'undefined' || !hasStoredSession()) return;

        const state = await verifySession();
        if (state === 'invalid') {
            // API.clearSession() has already fired auth:changed, so Layout has
            // re-rendered itself as a signed-out header.
            document.dispatchEvent(new CustomEvent('authgate:signedout'));
        }
    }

    // ================= NAVIGATION INTERCEPTION =================
    // One capture-phase listener for the whole document. Desktop nav, mobile
    // drawer, footer, hero actions, feature cards, the user menu, and any link
    // a page renders later all pass through here — there is nothing to wire up
    // per link, and a link added tomorrow is covered automatically.

    function isSignedInEnough() {
        // Presentation-level check only. 'valid' is server-confirmed; a bare
        // stored token is optimistically allowed to navigate because the
        // destination page runs this same gate and will bounce it if the
        // session turns out to be bad. Nothing is disclosed either way — the
        // backend authorises the data, not this function.
        if (sessionState === 'valid') return true;
        if (sessionState === 'invalid') return false;
        return hasStoredSession();
    }

    /** Resolves an <a href> to a same-directory page name, or null. */
    function pageFromAnchor(anchor) {
        const raw = anchor.getAttribute('href');
        if (!raw) return null;

        const trimmed = raw.trim();
        if (!trimmed || trimmed.charAt(0) === '#') return null;
        if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(trimmed)) return null; // mailto:, tel:, http:, ...

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

    /**
     * Programmatic equivalent of clicking a protected link, for navigation a
     * page computes in JS (the Home hero search picks its destination from a
     * dropdown, so there is no href to intercept).
     *
     * @returns {boolean} true if navigation happened, false if the auth modal
     * opened instead.
     */
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

    // ================= AUTH MODAL =================

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

        // Static, developer-authored markup only — no user or URL data reaches
        // innerHTML here; the destination is written through the href property
        // of an element resolved by id (see applyModalLinks).
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

        // The Google button lives in a cross-origin iframe, so focus can leave
        // the list entirely; wrapping from the known ends keeps the trap intact.
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
        // Next frame, so the opening transition actually runs.
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

    /**
     * Mounts the existing Google Identity Services implementation into the
     * modal. Reused verbatim: same script loader, same GET /api/config client
     * id, same POST /api/auth/google exchange, same API.setSession. Only the
     * post-success destination is supplied by the gate.
     */
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

    // ================= HOME ENTRY POINT =================

    function handleHomeAuthPrompt() {
        if (pageClass !== CLASS_PUBLIC_HOME) return;

        const params = new URLSearchParams(window.location.search);
        const reason = params.get('auth');
        if (!reason) return;

        const intended = sanitizeReturnPath(params.get('next')) || readIntendedDestination();

        // Strip the prompt parameters from the URL so a refresh, or Back from
        // somewhere else, does not re-trigger the modal. replaceState reuses
        // the single history entry that the gate's location.replace() created,
        // which is what keeps Back from looping between Home and the protected
        // page.
        try {
            window.history.replaceState(null, '', window.location.pathname + window.location.hash);
        } catch {
            /* file:// and similar: leaving the query in place is harmless */
        }

        // Someone who is already signed in and simply followed a stale link
        // should not be nagged; an expired session always explains itself.
        if (reason !== 'expired' && isSignedInEnough()) return;

        openModal({
            intended,
            message: reason === 'expired'
                ? tr('authGate.expired', 'انتهت جلستك. سجّل الدخول للمتابعة.', 'Your session has ended. Please sign in to continue.')
                : null
        });
    }

    // ================= SESSION LOSS DURING A PAGE'S LIFETIME =================

    function handleAuthChanged() {
        if (typeof API === 'undefined') return;

        if (API.isAuthenticated()) {
            // A fresh sign-in on this page: let the next check re-confirm it.
            if (sessionState === 'invalid') {
                sessionState = 'unknown';
                verifyPromise = null;
            }
            return;
        }

        // The session went away — most often API.refreshAccessToken() giving up
        // and calling clearSession(). On a protected page that leaves a dead
        // shell that will only produce more 401s, so leave immediately with the
        // current location preserved as the return destination.
        verifiedUser = null;
        sessionState = 'invalid';
        verifyPromise = null;

        if (!isProtectedPage) return;
        // Boot is still deciding; letting it finish avoids a double redirect.
        if (document.documentElement.getAttribute('data-auth-gate') === 'pending') return;

        raiseShield('pending');
        denyToHome('expired');
    }

    // ================= BOOT =================

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
            // Never leave a protected page permanently blank because of a bug in
            // this module: fall back to the retry state, which is honest about
            // what happened and keeps the content hidden.
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

    // Set last, so it means "this module parsed and installed itself", not
    // merely "the file started downloading". The inline bootstrap in each
    // protected page's <head> watches this flag: if the gate never arrives —
    // 404, blocked request, a parse error partway through — the bootstrap
    // leaves for Home rather than exposing the page it is shielding.
    window.__medorbitAuthGateReady = true;

    return {
        // classification
        PUBLIC_HOME: PUBLIC_HOME,
        AUTH_FLOW: AUTH_FLOW,
        PROTECTED: PROTECTED,
        ROLE_RESTRICTED: ROLE_RESTRICTED,
        classify: classify,
        currentPage: currentPage,
        pageClassification: () => pageClass,
        // return-path security
        sanitizeReturnPath: sanitizeReturnPath,
        readIntendedDestination: readIntendedDestination,
        rememberIntendedDestination: rememberIntendedDestination,
        clearIntendedDestination: clearIntendedDestination,
        defaultLandingPage: defaultLandingPage,
        isDoctorApplicationIntent: isDoctorApplicationIntent,
        // session
        verifySession: verifySession,
        getVerifiedUser: () => verifiedUser,
        getSessionState: () => sessionState,
        // navigation + UI
        navigate: navigate,
        requireAuthFor: requireAuthFor,
        openModal: openModal,
        closeModal: closeModal
    };
})();

/**
 * MedOrbit v2 - Google Sign-In
 * Renders the official Google Identity Services button into a container on
 * login.html / register.html, exchanges the returned ID token for a normal
 * MedOrbit session via POST /auth/google, and stores it through the exact
 * same API.setSession() path as password login — so everything downstream
 * (auth:changed listeners, redirect-after-login) behaves identically
 * regardless of which method the user signed in with.
 */
const GoogleSignIn = (() => {
    let initialized = false;
    let renderedContainerId = null;
    let clientIdPromise = null;
    let gisScriptEl = null;
    let currentHl = null;

    // Single source of truth is the backend's GOOGLE_CLIENT_ID (.env) —
    // fetched once from GET /api/config rather than duplicated into a
    // static frontend file. It's a public OAuth client identifier, not a
    // secret, so shipping it to the browser is fine; the duplication was
    // the actual problem.
    function fetchClientId() {
        if (!clientIdPromise) {
            clientIdPromise = API.get('/config', null, { auth: false, cacheTTL: 5 * 60 * 1000 })
                .then((res) => res?.data?.googleClientId || null)
                .catch(() => null);
        }
        return clientIdPromise;
    }

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

    function showAlert(message, type) {
        const box = document.getElementById('alertBox');
        const msg = document.getElementById('alertMsg');
        if (!box || !msg) return;
        box.className = 'alert ' + (type || 'error');
        const icon = box.querySelector('i');
        if (icon) icon.className = type === 'success' ? 'fas fa-circle-check' : 'fas fa-circle-exclamation';
        msg.textContent = message;
    }

    async function handleCredential(response) {
        try {
            const res = await API.post('/auth/google', { idToken: response.credential }, { auth: false });
            API.setSession(res?.data || {});
            showAlert(isAr() ? 'تم تسجيل الدخول بنجاح!' : 'Logged in successfully!', 'success');

            const redirect = new URLSearchParams(window.location.search).get('redirect');
            setTimeout(() => {
                window.location.href = redirect || 'index.html';
            }, 400);
        } catch (err) {
            showAlert(isAr()
                ? 'تعذر تسجيل الدخول باستخدام جوجل'
                : 'Could not sign in with Google');
        }
    }

    function renderButton(containerId) {
        const container = document.getElementById(containerId);
        if (!container || typeof google === 'undefined' || !google.accounts?.id) return;

        // Re-render from scratch each time theme/language changes.
        container.innerHTML = '';
        google.accounts.id.renderButton(container, {
            type: 'standard',
            theme: document.body.dataset.theme === 'dark' ? 'filled_black' : 'outline',
            size: 'large',
            shape: 'pill',
            text: 'continue_with',
            logo_alignment: 'center',
            width: Math.min(container.clientWidth || 320, 400)
            // No `locale` here — confirmed empirically that GIS ignores a
            // per-button locale override and instead derives the button's
            // displayed language from the `hl` query param on the gsi/client
            // script URL itself (see loadGisScript below).
        });
    }

    function loadGisScript(hl) {
        return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = 'https://accounts.google.com/gsi/client?hl=' + encodeURIComponent(hl);
            script.async = true;
            script.defer = true;
            script.onload = resolve;
            script.onerror = reject;
            document.head.appendChild(script);
            gisScriptEl = script;
        });
    }

    // (Re)loads the GIS script pinned to the given language, then
    // (re)initializes and renders the button. Needed both on first load and
    // whenever the UI language toggles, since `hl` is fixed for the
    // lifetime of a loaded script instance.
    async function setup(containerId, clientId, hl) {
        currentHl = hl;
        initialized = false;

        if (gisScriptEl) gisScriptEl.remove();
        delete window.google;

        try {
            await loadGisScript(hl);
        } catch {
            return;
        }

        if (typeof google === 'undefined' || !google.accounts?.id) return;

        google.accounts.id.initialize({
            client_id: clientId,
            callback: handleCredential,
            auto_select: false
        });
        initialized = true;

        renderedContainerId = containerId;
        renderButton(containerId);
    }

    async function init(containerId) {
        const clientId = await fetchClientId();
        if (!clientId) {
            // Not configured yet — hide the whole block (button + divider)
            // rather than show a broken button.
            document.getElementById(containerId)?.closest('.oauth-block')?.classList.add('hidden');
            return;
        }

        await setup(containerId, clientId, isAr() ? 'ar' : 'en');

        document.getElementById('themeToggle')?.addEventListener('click', () => {
            setTimeout(() => renderButton(renderedContainerId), 50);
        });

        window.addEventListener('languageChanged', () => {
            const hl = isAr() ? 'ar' : 'en';
            if (hl === currentHl) return;
            setup(renderedContainerId, clientId, hl);
        });
    }

    return { init };
})();

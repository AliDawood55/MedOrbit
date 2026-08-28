const GoogleSignIn = (() => {
    let initialized = false;
    let renderedContainerId = null;
    let clientIdPromise = null;
    let gisScriptEl = null;
    let currentHl = null;
    let handlers = {};

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

function safeRedirect() {
        if (typeof AuthGate === 'undefined') return null;
        return AuthGate.readIntendedDestination();
    }

    async function handleCredential(response) {
        try {
            const res = await API.post('/auth/google', { idToken: response.credential }, { auth: false });
            API.setSession(res?.data || {});

            if (typeof handlers.onSuccess === 'function') {
                handlers.onSuccess();
                return;
            }

            showAlert(isAr() ? 'تم تسجيل الدخول بنجاح!' : 'Logged in successfully!', 'success');

            const redirect = safeRedirect();
            const landing = typeof AuthGate !== 'undefined'
                ? AuthGate.defaultLandingPage(res?.data?.user)
                : 'dashboard.html';
            setTimeout(() => {
                window.location.href = redirect || landing;
            }, 400);
        } catch (err) {
            const message = err?.status === 429
                ? (isAr()
                    ? 'محاولات كثيرة خلال وقت قصير. حاول مرة أخرى بعد قليل.'
                    : 'Too many attempts. Please try again shortly.')
                : (isAr()
                    ? 'تعذر تسجيل الدخول باستخدام جوجل'
                    : 'Could not sign in with Google');

            if (typeof handlers.onError === 'function') handlers.onError(message);
            else showAlert(message);
        }
    }

    function renderButton(containerId) {
        const container = document.getElementById(containerId);
        if (!container || typeof google === 'undefined' || !google.accounts?.id) return;

container.innerHTML = '';
        google.accounts.id.renderButton(container, {
            type: 'standard',
            theme: document.body.dataset.theme === 'dark' ? 'filled_black' : 'outline',
            size: 'large',
            shape: 'pill',
            text: 'continue_with',
            logo_alignment: 'center',
            width: Math.min(container.clientWidth || 320, 400)

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

async function setup(containerId, clientId, hl) {
        currentHl = hl;
        initialized = false;

        if (gisScriptEl) gisScriptEl.remove();
        delete window.google;

        try {
            await loadGisScript(hl);
        } catch {
            reportUnavailable();
            return;
        }

        if (typeof google === 'undefined' || !google.accounts?.id) {
            reportUnavailable();
            return;
        }

        google.accounts.id.initialize({
            client_id: clientId,
            callback: handleCredential,
            auto_select: false
        });
        initialized = true;

        renderedContainerId = containerId;
        renderButton(containerId);
    }

function reportUnavailable() {
        if (typeof handlers.onUnavailable === 'function') {
            handlers.onUnavailable();
            return;
        }
        document.getElementById(renderedContainerId)?.closest('.oauth-block')?.classList.add('hidden');
    }

    async function init(containerId, options) {
        handlers = options || {};
        renderedContainerId = containerId;

        const clientId = await fetchClientId();
        if (!clientId) {
            reportUnavailable();
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

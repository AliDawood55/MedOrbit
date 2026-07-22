/**
 * MedOrbit v2 - API Client
 * Owns the session (access/refresh token + user in localStorage), attaches
 * Authorization headers automatically, and transparently refreshes an
 * expired access token once on a 401 before retrying the original request.
 * Loaded on every page so login state and requests stay consistent.
 */
const API = (() => {

    // Derive from wherever the page was actually opened from (localhost vs
    // 127.0.0.1 are different origins to the browser/CORS even though they're
    // the same machine) so the API origin always agrees with the page's own
    // origin, rather than assuming one hardcoded hostname.
    const BASE_URL = window.MEDORBIT_API_URL ||
        (window.location.hostname ? `${window.location.protocol}//${window.location.hostname}:3001/api` : 'http://127.0.0.1:3001/api');

    const ACCESS_KEY = 'accessToken';
    const REFRESH_KEY = 'refreshToken';
    const USER_KEY = 'user';

    // Dedupe concurrent refresh attempts — only one /auth/refresh in flight at a time.
    let refreshPromise = null;

    // ================= SESSION =================

    function getAccessToken() {
        return localStorage.getItem(ACCESS_KEY);
    }

    function getRefreshToken() {
        return localStorage.getItem(REFRESH_KEY);
    }

    function getUser() {
        try {
            const raw = localStorage.getItem(USER_KEY);
            return raw ? JSON.parse(raw) : null;
        } catch {
            return null;
        }
    }

    function isAuthenticated() {
        return !!getAccessToken();
    }

    function setSession({ accessToken, refreshToken, user } = {}) {
        if (accessToken) localStorage.setItem(ACCESS_KEY, accessToken);
        if (refreshToken) localStorage.setItem(REFRESH_KEY, refreshToken);
        if (user) localStorage.setItem(USER_KEY, JSON.stringify(user));
        window.dispatchEvent(new CustomEvent('auth:changed'));
    }

    function clearSession() {
        localStorage.removeItem(ACCESS_KEY);
        localStorage.removeItem(REFRESH_KEY);
        localStorage.removeItem(USER_KEY);
        _cache.clear();
        window.dispatchEvent(new CustomEvent('auth:changed'));
    }

    /**
     * Guard for pages that require a logged-in user.
     * Redirects to login.html (with a return path) and returns false if not authenticated.
     */
    function requireAuth(redirectTo) {
        if (!isAuthenticated()) {
            const target = redirectTo || (window.location.pathname.split('/').pop() + window.location.search);
            window.location.href = 'login.html?redirect=' + encodeURIComponent(target);
            return false;
        }
        return true;
    }

    // ================= TTL CACHE (GET only) =================
    // Opt-in per call via { cacheTTL: ms } — for slow-changing, non-user-
    // specific lists (clinics, doctors) where a short-lived stale read is
    // harmless. Never applied unless the caller explicitly asks for it, so
    // user-specific endpoints (profile, conversations) are never cached.
    const _cache = new Map(); // url -> { data, expiresAt }

    function _cacheGet(key) {
        const entry = _cache.get(key);
        if (!entry) return undefined;
        if (Date.now() > entry.expiresAt) {
            _cache.delete(key);
            return undefined;
        }
        return entry.data;
    }

    function _cacheSet(key, data, ttl) {
        _cache.set(key, { data, expiresAt: Date.now() + ttl });
    }

    /**
     * Clears cached GET responses. Pass a path prefix (e.g. '/clinics') to
     * clear just that family, or omit to clear everything.
     */
    function clearCache(prefix) {
        if (!prefix) { _cache.clear(); return; }
        for (const key of _cache.keys()) {
            if (key.includes(prefix)) _cache.delete(key);
        }
    }

    // ================= CORE REQUEST =================

    async function request(path, options = {}) {

        const {
            method = 'GET',
            body,
            query,
            signal,
            auth = true,
            cacheTTL,
            _retry = false
        } = options;

        let url = BASE_URL + path;

        if (query && typeof query === 'object') {
            const params = Object.entries(query)
                .filter(([, v]) => v !== undefined && v !== null && v !== '')
                .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
            if (params.length) url += (url.includes('?') ? '&' : '?') + params.join('&');
        }

        if (method === 'GET' && cacheTTL) {
            const cached = _cacheGet(url);
            if (cached !== undefined) return cached;
        }

        const headers = { 'Content-Type': 'application/json' };

        if (auth) {
            const token = getAccessToken();
            if (token) headers['Authorization'] = 'Bearer ' + token;
        }

        const response = await fetch(url, {
            method,
            headers,
            body: body ? JSON.stringify(body) : undefined,
            signal
        });

        let data = null;
        try {
            data = await response.json();
        } catch {
            data = null;
        }

        // Access token expired — refresh once and retry the original request.
        if (response.status === 401 && auth && !_retry && path !== '/auth/refresh') {
            const refreshed = await refreshAccessToken();
            if (refreshed) {
                return request(path, { ...options, _retry: true });
            }
        }

        if (!response.ok) {
            const err = new Error(data?.error?.message || 'Request failed');
            err.code = data?.error?.code;
            err.status = response.status;
            throw err;
        }

        if (method === 'GET' && cacheTTL) {
            _cacheSet(url, data, cacheTTL);
        }

        return data;
    }

    /**
     * Multipart upload (avatar, etc.) — request() always JSON-stringifies its
     * body, so uploads need their own path. Same auto-refresh-on-401 pattern
     * as request(), minus a Content-Type header (the browser sets the
     * multipart boundary itself when given a FormData body).
     */
    async function uploadFile(path, fieldName, file, options = {}) {
        const { _retry = false } = options;
        const url = BASE_URL + path;

        const formData = new FormData();
        formData.append(fieldName, file);

        const headers = {};
        const token = getAccessToken();
        if (token) headers['Authorization'] = 'Bearer ' + token;

        const response = await fetch(url, { method: 'POST', headers, body: formData });

        let data = null;
        try {
            data = await response.json();
        } catch {
            data = null;
        }

        if (response.status === 401 && !_retry) {
            const refreshed = await refreshAccessToken();
            if (refreshed) {
                return uploadFile(path, fieldName, file, { _retry: true });
            }
        }

        if (!response.ok) {
            const err = new Error(data?.error?.message || 'Upload failed');
            err.code = data?.error?.code;
            err.status = response.status;
            throw err;
        }

        return data;
    }

    async function refreshAccessToken() {
        const token = getRefreshToken();
        if (!token) {
            clearSession();
            return false;
        }

        if (!refreshPromise) {
            refreshPromise = request('/auth/refresh', {
                method: 'POST',
                body: { refreshToken: token },
                auth: false,
                _retry: true
            })
                .then(res => {
                    setSession({
                        accessToken: res?.data?.accessToken,
                        refreshToken: res?.data?.refreshToken
                    });
                    return true;
                })
                .catch(() => {
                    // Refresh failed — only real way out is logging out.
                    clearSession();
                    return false;
                })
                .finally(() => {
                    refreshPromise = null;
                });
        }

        return refreshPromise;
    }

    async function logout() {
        const token = getRefreshToken();
        if (token) {
            try {
                await request('/auth/logout', {
                    method: 'POST',
                    body: { refreshToken: token },
                    auth: false
                });
            } catch {
                // Best-effort — clear the local session regardless.
            }
        }
        clearSession();
    }

    // ================= VERBS =================

    function get(path, query, options = {}) {
        return request(path, { ...options, method: 'GET', query });
    }

    function post(path, body, options = {}) {
        return request(path, { ...options, method: 'POST', body });
    }

    function put(path, body, options = {}) {
        return request(path, { ...options, method: 'PUT', body });
    }

    function del(path, options = {}) {
        return request(path, { ...options, method: 'DELETE' });
    }

    // ================= CHAT =================

    async function sendChatMessage(params) {
        // Extract signal from params (not sent to server)
        const { signal, ...body } = params;
        const res = await post('/chat/message', body, { signal });
        return res.data;
    }

    function makeCancellable() {
        return new AbortController();
    }

    // ================= CONVERSATIONS (JWT required) =================

    const conversations = {
        list: (query, options) => get('/conversations', query, options),
        create: (body, options) => post('/conversations', body, options),
        search: (q, options) => get('/conversations/search', { q }, options),
        get: (id, query, options) => get(`/conversations/${id}`, query, options),
        rename: (id, title, options) => put(`/conversations/${id}`, { title }, options),
        remove: (id, options) => del(`/conversations/${id}`, options)
    };

    // ================= DOCTORS (public read) =================

    const doctors = {
        list: (query, options) => get('/doctors', query, options),
        get: (id, options) => get(`/doctors/${id}`, null, options),
        availability: (id, query, options) => get(`/doctors/${id}/availability`, query, options)
    };

    // ================= CLINICS (public read) =================

    const clinics = {
        list: (query, options) => get('/clinics', query, options),
        nearby: (query, options) => get('/clinics/nearby', query, options),
        get: (id, options) => get(`/clinics/${id}`, null, options)
    };

    // ================= USERS (JWT required) =================

    const users = {
        me: (options) => get('/users/me', null, options),
        updateMe: (body, options) => put('/users/me', body, options),
        updatePreferences: (body, options) => put('/users/me/preferences', body, options),
        uploadAvatar: (file, options) => uploadFile('/users/me/avatar', 'avatar', file, options),
        savedPlaces: (options) => get('/users/me/saved-places', null, options)
    };

    function getOrigin() {
        return BASE_URL.replace(/\/api\/?$/, '');
    }

    return {
        request, get, post, put, del,
        sendChatMessage, makeCancellable, conversations, doctors, clinics, users,
        isAuthenticated, getUser, getAccessToken, getRefreshToken,
        setSession, clearSession, requireAuth, logout, getOrigin, clearCache
    };

})();

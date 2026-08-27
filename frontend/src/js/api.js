/**
 * MedOrbit v2 - API Client
 * Owns the session (access/refresh token + user in localStorage), attaches
 * Authorization headers automatically, and transparently refreshes an
 * expired access token once on a 401 before retrying the original request.
 * Loaded on every page so login state and requests stay consistent.
 */
const API = (() => {

    function trimTrailingSlash(value) {
        return String(value || '').replace(/\/+$/, '');
    }

    function resolveServiceOrigin(port, override) {
        const configured = trimTrailingSlash(override);
        if (configured) return configured;

        if (!window.location.hostname) {
            throw new Error(`Cannot resolve MedOrbit service on port ${port} without an HTTP(S) hostname`);
        }

        // HTTPS deployments are served behind the public reverse proxy. The
        // browser must use its own origin so Caddy can forward /api to the
        // private backend; :3001 is intentionally not public in staging.
        if (window.location.protocol === 'https:') {
            return window.location.origin;
        }

        return `http://${window.location.hostname}:${port}`;
    }

    // HTTP development uses the matching backend port. HTTPS deployments use
    // Caddy's same-origin /api proxy unless an explicit override is supplied.
    const API_ORIGIN = resolveServiceOrigin(3001, window.MEDORBIT_API_URL).replace(/\/api\/?$/, '');
    const BASE_URL = API_ORIGIN + '/api';

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
     * Per-page guard, kept as defense-in-depth behind the global gate.
     * Returns false when there is no session, which is what every caller uses
     * to abort its own boot.
     *
     * When auth-gate.js is present it owns the redirect decision (Home + auth
     * modal, intended destination preserved), so this must not navigate too —
     * two competing redirects for one failure is how loops start. The standalone
     * login.html redirect is retained for any page loaded without the gate.
     */
    function requireAuth(redirectTo) {
        if (isAuthenticated()) return true;

        if (typeof AuthGate !== 'undefined') return false;

        const target = redirectTo || (window.location.pathname.split('/').pop() + window.location.search);
        window.location.href = 'login.html?redirect=' + encodeURIComponent(target);
        return false;
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

    function retryAfterSeconds(response) {
        const value = response.headers.get('Retry-After');
        if (!value) return null;

        const seconds = Number(value);
        if (Number.isFinite(seconds)) return Math.max(0, Math.ceil(seconds));

        const retryAt = Date.parse(value);
        return Number.isNaN(retryAt) ? null : Math.max(0, Math.ceil((retryAt - Date.now()) / 1000));
    }

    function responseError(response, data, fallback) {
        const isRateLimited = response.status === 429;
        const isArabic = typeof I18n !== 'undefined' && I18n.getLang?.() === 'ar';
        const message = isRateLimited
            ? (isArabic
                ? 'تم إرسال طلبات كثيرة خلال وقت قصير. حاول مرة أخرى بعد قليل.'
                : 'Too many requests. Please try again shortly.')
            : (data?.error?.message || fallback);
        const err = new Error(message);
        err.code = data?.error?.code;
        err.status = response.status;
        // Entitlement denials carry server-computed metadata (remaining,
        // resets_at, next_free_at). Surfaced here so quota UI can render an
        // accurate countdown from authoritative timestamps instead of guessing.
        err.details = data?.error?.details || null;
        err.retryAfterSeconds = isRateLimited ? retryAfterSeconds(response) : null;
        return err;
    }

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
            throw responseError(response, data, 'Request failed');
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
            throw responseError(response, data, 'Upload failed');
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

    function patch(path, body, options = {}) {
        return request(path, { ...options, method: 'PATCH', body });
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
        availability: (id, query, options) => get(`/doctors/${id}/availability`, query, options),
        myProfile: (options) => get('/doctors/me/profile', null, options),
        updateMyProfile: (body, options) => put('/doctors/me/profile', body, options),
        mySchedule: (options) => get('/doctors/me/schedule', null, options),
        addAvailability: (body, options) => post('/doctors/me/availability', body, options),
        updateAvailability: (id, body, options) => put(`/doctors/me/availability/${id}`, body, options),
        deleteAvailability: (id, options) => del(`/doctors/me/availability/${id}`, options)
    };

    const patientProfiles = {
        me: (options) => get('/patients/me/profile', null, options),
        updateMe: (body, options) => put('/patients/me/profile', body, options),
        discover: (query, options) => get('/patients/discover', query, options)
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

    // ================= APPOINTMENTS (JWT required) =================

    const appointments = {
        list: (options) => get('/appointments', null, options),
        get: (id, options) => get(`/appointments/${id}`, null, options),
        create: (body, options) => post('/appointments', body, options),
        cancel: (id, body, options) => put(`/appointments/${id}/cancel`, body, options),
        confirm: (id, options) => put(`/appointments/${id}/confirm`, {}, options),
        complete: (id, options) => put(`/appointments/${id}/complete`, {}, options),
        availableSlots: (query, options) => get('/appointments/available-slots', query, options)
    };

    // ================= NOTIFICATIONS (JWT required) =================

    const notifications = {
        list: (options) => get('/notifications', null, options),
        unreadCount: (options) => get('/notifications/unread-count', null, options),
        markRead: (id, options) => put(`/notifications/${id}/read`, null, options),
        markAllRead: (options) => patch('/notifications/read-all', null, options),
        remove: (id, options) => del(`/notifications/${id}`, options)
    };

    // Human text messaging is separate from `conversations` (AI chatbot).
    const messaging = {
        list: (query, options) => get('/messages/conversations', query, options),
        start: (counterpartId, options) => post('/messages/conversations', { counterpartId }, options),
        history: (id, query, options) => get(`/messages/conversations/${id}/messages`, query, options),
        send: (id, body, clientMessageId, options) => post(`/messages/conversations/${id}/messages`, { body, client_message_id: clientMessageId }, options),
        markRead: (id, messageId, options) => post(`/messages/conversations/${id}/read`, messageId ? { message_id: messageId } : {}, options),
        accept: (id, options) => post(`/messages/conversations/${id}/accept`, {}, options),
        decline: (id, options) => post(`/messages/conversations/${id}/decline`, {}, options)
    };

    // ================= ANALYTICS (JWT required, admin/super_admin only) =================
    // GET /api/dashboard/stats — real response shape (backend/src/services/report.service.js):
    //   {
    //     users: { total, patients, doctors },
    //     appointments: { total, completed, cancelled, scheduled },
    //     medical_records: { total }, prescriptions: { total }, ratings: { average },
    //     analytics: {
    //       usersByRole:          { data: { labels: string[], counts: number[] } } | { error: true }
    //       appointmentsOverTime: { data: { labels: string[] (week-start ISO dates), counts: number[] } } | { error: true }
    //       topSpecialties:       { data: { items: { nameAr, nameEn, count }[] } } | { error: true }
    //       conversationsPerWeek: { data: { labels: string[] (week-start ISO dates), counts: number[] } } | { error: true }
    //       triageLevels:         { data: { labels: string[], counts: number[] } } | { error: true }
    //       clinicTypes:          { data: { labels: string[], counts: number[] } } | { error: true }
    //     }
    //   }
    // Each analytics.* section is independent: one query failing server-side
    // only marks that one section { error: true } instead of failing the
    // whole request — analytics.js renders a per-card "unavailable" state for
    // just that section.
    const analytics = {
        dashboardStats: (options) => get('/dashboard/stats', null, options)
    };

    // ================= CARE (JWT required) =================
    // All LIVE — backend/src/routes/doctor.routes.js and patient.routes.js.
    // Every one of these resolves the caller's own doctor_id / patient_id
    // server-side from the JWT, and every :patientId /:doctorId route
    // verifies a real appointment relationship exists before returning
    // anything (404, not 403, if not) — see the isolation notes in
    // patient-detail.js / my-doctor.js / doctor.routes.js.
    const care = {
        // Public doctor-posts read (doctor.html's Posts tab) — published only
        doctorPosts: (doctorId, options) => get(`/doctors/${doctorId}/posts`, null, options),
        // Doctor's own posts, every status (doctor-posts.html)
        myPosts: (options) => get('/doctors/me/posts', null, options),
        createPost: (body, options) => post('/doctors/me/posts', body, options),
        updatePost: (postId, body, options) => put(`/doctors/me/posts/${postId}`, body, options),
        deletePost: (postId, options) => del(`/doctors/me/posts/${postId}`, options),
        // Doctor's patient list + one patient's file, incl. session notes
        // (my-patients.html, patient-detail.html)
        myPatients: (query, options) => get('/doctors/me/patients', query, options),
        patientDetail: (patientId, options) => get(`/doctors/me/patients/${patientId}`, null, options),
        addPatientNote: (patientId, body, options) => post(`/doctors/me/patients/${patientId}/notes`, body, options),
        // Doctor-only clinical authoring. The backend validates appointment
        // ownership and an active care relationship before creating anything.
        createPrescription: (body, options) => post('/prescriptions', body, options),
        // Patient's view of their own doctor(s) + notes a doctor explicitly
        // shared (visible_to_patient=true) — my-doctor.html
        myDoctors: (options) => get('/patients/me/doctors', null, options),
        sharedNotes: (doctorId, options) => get(`/patients/me/doctors/${doctorId}/notes`, null, options),
        // Patient's own medical records / prescriptions — the safe,
        // ownership-scoped equivalents of the generic GET /medical-records
        // and GET /prescriptions/:id, which have no ownership filtering at all.
        myMedicalRecords: (query, options) => get('/patients/me/medical-records', query, options),
        medicalRecordDetail: (id, options) => get(`/patients/me/medical-records/${id}`, null, options),
        // Combined timeline (appointments + records + prescriptions) — my-records.html
        myRecordsTimeline: (query, options) => get('/patients/me/records', query, options),
        myPrescriptions: (query, options) => get('/patients/me/prescriptions', query, options),
        prescriptionDetail: (id, options) => get(`/patients/me/prescriptions/${id}`, null, options)
    };

    const social = {
        feed: (query, options) => get('/feed/posts', query, options),
        comments: (postId, options) => get(`/feed/posts/${postId}/comments`, null, options),
        addComment: (postId, body, options) => post(`/feed/posts/${postId}/comments`, body, options),
        like: (postId, options) => post(`/feed/posts/${postId}/like`, {}, options),
        unlike: (postId, options) => del(`/feed/posts/${postId}/like`, options),
        view: (postId, options) => post(`/feed/posts/${postId}/view`, {}, options),
        follow: (doctorId, options) => post(`/doctors/${doctorId}/follow`, {}, options),
        unfollow: (doctorId, options) => del(`/doctors/${doctorId}/follow`, options),
        doctorView: (doctorId, options) => post(`/doctors/${doctorId}/view`, {}, options),
        specialtySearch: (specialtyId, options) => post(`/recommendations/specialties/${specialtyId}/search`, {}, options),
        moderationPosts: (query, options) => get('/admin/social/posts', query, options),
        moderatePost: (id, action, options) => post(`/admin/social/posts/${id}/moderate`, { action }, options),
        moderationComments: (query, options) => get('/admin/social/comments', query, options),
        moderateComment: (id, action, options) => post(`/admin/social/comments/${id}/moderate`, { action }, options)
    };

    function getOrigin() {
        return API_ORIGIN;
    }

    /**
     * Resolves backend-owned media paths (for example `/uploads/avatars/...`)
     * against the API origin. Public profile responses intentionally contain
     * relative paths, while the static frontend is served from a different
     * origin in production. Absolute/data/blob URLs are already complete.
     */
    function assetUrl(value) {
        const source = String(value || '').trim();
        if (!source) return '';
        if (/^(?:https?:|data:|blob:)/i.test(source)) return source;
        return API_ORIGIN + '/' + source.replace(/^\/+/, '');
    }

    // Platform feedback (feedback.html) — POST /api/feedback,
    // backend/src/routes/feedback.routes.js. Any authenticated user
    // (patient or doctor), user_id resolved server-side from the JWT.
    // GET /api/feedback/stats is public (home.html's feedback dashboard):
    // { total, averageRating, ratingDistribution:[{rating,count}],
    //   categoryAverages:{chatbot,clinics,booking,design},
    //   recommend:{yes,no}, users:[{id,nameAr,nameEn,avatarUrl}] }
    const feedback = {
        submit: (body, options) => post('/feedback', body, options),
        stats: (options) => get('/feedback/stats', null, options)
    };

    const contact = {
        submit: (body, options) => post('/contact', body, options),
        adminList: (query, options) => get('/admin/contact-messages', query, options),
        adminGet: (id, options) => get(`/admin/contact-messages/${id}`, null, options),
        markRead: (id, options) => post(`/admin/contact-messages/${id}/read`, {}, options),
        resolve: (id, options) => post(`/admin/contact-messages/${id}/resolve`, {}, options)
    };

    // ================= BILLING / ENTITLEMENTS (JWT required) =================
    //
    // Read-only by design. There is deliberately no client-side way to set a
    // plan or a quota: entitlement is decided by the backend, and this module
    // only reports what it decided.
    const billing = {
        entitlements: (options) => get('/billing/entitlements', null, options),
        plans: (options) => get('/billing/plans', null, options),
        config: (options) => get('/billing/config', null, options),
        subscription: (options) => get('/billing/subscription', null, options),
        history: (options) => get('/billing/history', null, options),

        // Starts an upgrade. Sends a plan_code and where to come back to —
        // never a price, an amount or a status. The backend resolves what the
        // plan costs from its own catalogue, so there is nothing here worth
        // tampering with.
        checkout: (planCode, returnPath, options) =>
            post('/billing/checkout', { plan_code: planCode, return_path: returnPath || null }, options),

        // No subscription id is sent. The backend acts on the caller's own
        // subscription, resolved from their token, which is why one account
        // cannot cancel another's.
        cancel: (options) => post('/billing/subscription/cancel', {}, options),
        resume: (options) => post('/billing/subscription/resume', {}, options),
        changePlan: (planCode, options) => post('/billing/subscription/plan', { plan_code: planCode }, options),

        // Sandbox only. These paths do not exist in a production process, so
        // calling them there is an ordinary 404 rather than a disabled
        // feature — nothing about the UI can turn them back on.
        sandbox: {
            checkout: (token, options) => get(`/billing/sandbox/checkout/${encodeURIComponent(token)}`, null, options),
            complete: (token, outcome, options) =>
                post(`/billing/sandbox/checkout/${encodeURIComponent(token)}/complete`, { outcome }, options),
            simulate: (kind, options) => post('/billing/sandbox/simulate', { kind }, options)
        }
    };

    // ================= VIRTUAL DOCTOR (JWT required) =================
    //
    // Every call goes through the authenticated MedOrbit backend, which checks
    // entitlement and then talks to the AI service over an internal credential
    // a browser cannot hold. The old path — the browser calling port 8001
    // directly with `user_id: null` — is gone, and the AI service now rejects
    // it outright.
    const virtualDoctor = {
        start: (language, options) => post('/virtual-doctor/start', { language }, options),
        message: (sessionId, message, options) =>
            post('/virtual-doctor/message', { session_id: sessionId, message }, options),
        session: (sessionId, options) => get(`/virtual-doctor/session/${sessionId}`, null, options),
        endSession: (sessionId, options) => post(`/virtual-doctor/session/${sessionId}/end`, {}, options),
        report: (sessionId, options) => post(`/virtual-doctor/report/${sessionId}`, {}, options),
        reportDownloadUrl: (reportId) => `${BASE_URL}/virtual-doctor/report/${reportId}/download`,
        warmup: (kind, language) => {
            const q = language ? `?language=${encodeURIComponent(language)}` : '';
            return post(`/virtual-doctor/${kind}/warmup${q}`, {});
        }
    };

    const adminInvitations = {
        list: (options) => get('/admin/invitations', null, options),
        create: (email, options) => post('/admin/invitations', { email }, options),
        revoke: (id, options) => del(`/admin/invitations/${id}`, options)
    };

    return {
        request, get, post, put, del, patch, uploadFile,
        sendChatMessage, makeCancellable, conversations, messaging, doctors, patientProfiles, clinics, users, appointments, notifications, analytics, care, social, feedback, contact, adminInvitations, billing, virtualDoctor,
        isAuthenticated, getUser, getAccessToken, getRefreshToken,
        setSession, clearSession, requireAuth, logout, getOrigin, assetUrl, resolveServiceOrigin, clearCache
    };

})();

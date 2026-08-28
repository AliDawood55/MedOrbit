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

if (window.location.protocol === 'https:') {
            return window.location.origin;
        }

        return `http://${window.location.hostname}:${port}`;
    }

const API_ORIGIN = resolveServiceOrigin(3001, window.MEDORBIT_API_URL).replace(/\/api\/?$/, '');
    const BASE_URL = API_ORIGIN + '/api';

    const ACCESS_KEY = 'accessToken';
    const REFRESH_KEY = 'refreshToken';
    const USER_KEY = 'user';

let refreshPromise = null;

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

    /**
     * Updates the browser's one canonical signed-in identity with the profile
     * returned by `/users/me` or a successful profile/avatar mutation.  The
     * login payload is intentionally small, so treating it as the source of
     * truth made headers keep an old name or photo until the next login.
     */
    function updateCurrentUser(profile) {
        if (!profile || typeof profile !== 'object') return getUser();

        const current = getUser() || {};
        const avatar = profile.avatar_url || profile.profile_image_url || current.avatar_url || current.profile_image_url || null;
        const merged = {
            ...current,
            ...profile,
            ...(avatar ? { avatar_url: avatar, profile_image_url: avatar } : {})
        };
        localStorage.setItem(USER_KEY, JSON.stringify(merged));
        window.dispatchEvent(new CustomEvent('profile:changed', { detail: { user: merged } }));
        return merged;
    }

    /** Fetches and stores the server-authoritative profile for this tab. */
    async function refreshCurrentUser(options) {
        if (!isAuthenticated()) return null;
        const response = await get('/users/me', null, options);
        return updateCurrentUser(response?.data || null);
    }

    /** Locale-aware name used by every shared identity surface. */
    function displayName(user, language) {
        const value = user || {};
        const lang = language || (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar');
        const primary = lang === 'ar'
            ? [value.first_name_ar, value.last_name_ar]
            : [value.first_name_en, value.last_name_en];
        const fallback = lang === 'ar'
            ? [value.first_name_en, value.last_name_en]
            : [value.first_name_ar, value.last_name_ar];
        return primary.filter(Boolean).join(' ').trim()
            || fallback.filter(Boolean).join(' ').trim()
            || String(value.name || value.email || '').trim();
    }

    function clearSession() {
        localStorage.removeItem(ACCESS_KEY);
        localStorage.removeItem(REFRESH_KEY);
        localStorage.removeItem(USER_KEY);
        _cache.clear();
        window.dispatchEvent(new CustomEvent('auth:changed'));
    }

function requireAuth(redirectTo) {
        if (isAuthenticated()) return true;

        if (typeof AuthGate !== 'undefined') return false;

        const target = redirectTo || (window.location.pathname.split('/').pop() + window.location.search);
        window.location.href = 'login.html?redirect=' + encodeURIComponent(target);
        return false;
    }

const _cache = new Map();

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

function clearCache(prefix) {
        if (!prefix) { _cache.clear(); return; }
        for (const key of _cache.keys()) {
            if (key.includes(prefix)) _cache.delete(key);
        }
    }

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

            }
        }
        clearSession();
    }

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

async function sendChatMessage(params) {

        const { signal, ...body } = params;
        const res = await post('/chat/message', body, { signal });
        return res.data;
    }

    function makeCancellable() {
        return new AbortController();
    }

const conversations = {
        list: (query, options) => get('/conversations', query, options),
        create: (body, options) => post('/conversations', body, options),
        search: (q, options) => get('/conversations/search', { q }, options),
        get: (id, query, options) => get(`/conversations/${id}`, query, options),
        rename: (id, title, options) => put(`/conversations/${id}`, { title }, options),
        remove: (id, options) => del(`/conversations/${id}`, options)
    };

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

const clinics = {
        list: (query, options) => get('/clinics', query, options),
        nearby: (query, options) => get('/clinics/nearby', query, options),
        get: (id, options) => get(`/clinics/${id}`, null, options)
    };

const users = {
        me: (options) => get('/users/me', null, options),
        updateMe: (body, options) => put('/users/me', body, options),
        updatePreferences: (body, options) => put('/users/me/preferences', body, options),
        uploadAvatar: (file, options) => uploadFile('/users/me/avatar', 'avatar', file, options),
        savedPlaces: (options) => get('/users/me/saved-places', null, options)
    };

const appointments = {
        list: (options) => get('/appointments', null, options),
        get: (id, options) => get(`/appointments/${id}`, null, options),
        create: (body, options) => post('/appointments', body, options),
        cancel: (id, body, options) => put(`/appointments/${id}/cancel`, body, options),
        confirm: (id, options) => put(`/appointments/${id}/confirm`, {}, options),
        complete: (id, options) => put(`/appointments/${id}/complete`, {}, options),
        availableSlots: (query, options) => get('/appointments/available-slots', query, options)
    };

const notifications = {
        list: (options) => get('/notifications', null, options),
        unreadCount: (options) => get('/notifications/unread-count', null, options),
        markRead: (id, options) => put(`/notifications/${id}/read`, null, options),
        markAllRead: (options) => patch('/notifications/read-all', null, options),
        remove: (id, options) => del(`/notifications/${id}`, options)
    };

const messaging = {
        list: (query, options) => get('/messages/conversations', query, options),
        start: (counterpartId, options) => post('/messages/conversations', { counterpartId }, options),
        history: (id, query, options) => get(`/messages/conversations/${id}/messages`, query, options),
        send: (id, body, clientMessageId, options) => post(`/messages/conversations/${id}/messages`, { body, client_message_id: clientMessageId }, options),
        markRead: (id, messageId, options) => post(`/messages/conversations/${id}/read`, messageId ? { message_id: messageId } : {}, options),
        accept: (id, options) => post(`/messages/conversations/${id}/accept`, {}, options),
        decline: (id, options) => post(`/messages/conversations/${id}/decline`, {}, options)
    };

const analytics = {
        dashboardStats: (options) => get('/dashboard/stats', null, options)
    };

const care = {

        doctorPosts: (doctorId, options) => get(`/doctors/${doctorId}/posts`, null, options),

        myPosts: (options) => get('/doctors/me/posts', null, options),
        createPost: (body, options) => post('/doctors/me/posts', body, options),
        updatePost: (postId, body, options) => put(`/doctors/me/posts/${postId}`, body, options),
        deletePost: (postId, options) => del(`/doctors/me/posts/${postId}`, options),

myPatients: (query, options) => get('/doctors/me/patients', query, options),
        patientDetail: (patientId, options) => get(`/doctors/me/patients/${patientId}`, null, options),

        addPatientNote: (patientId, body, options) =>
            post(`/doctors/me/patients/${patientId}/notes`, body, options),

createMedicalRecord: (body, options) =>
            post('/medical-records', body, options),

getMedicalRecord: (id, options) =>
            get(`/medical-records/${id}`, null, options),

        updateMedicalRecord: (id, body, options) =>
            put(`/medical-records/${id}`, body, options),

        deleteMedicalRecord: (id, options) =>
            del(`/medical-records/${id}`, options),

createPrescription: (body, options) => post('/prescriptions', body, options),

myDoctors: (options) => get('/patients/me/doctors', null, options),
        sharedNotes: (doctorId, options) => get(`/patients/me/doctors/${doctorId}/notes`, null, options),

myMedicalRecords: (query, options) => get('/patients/me/medical-records', query, options),
        medicalRecordDetail: (id, options) => get(`/patients/me/medical-records/${id}`, null, options),

        myRecordsTimeline: (query, options) => get('/patients/me/records', query, options),
        myPrescriptions: (query, options) => get('/patients/me/prescriptions', query, options),
        prescriptionDetail: (id, options) => get(`/patients/me/prescriptions/${id}`, null, options)
    };

const recommendations = {
        doctors: (limit, options) => get('/recommendations/doctors', { limit }, options)
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

function assetUrl(value) {
        const source = String(value || '').trim();
        if (!source) return '';
        if (/^(?:https?:|data:|blob:)/i.test(source)) return source;
        return API_ORIGIN + '/' + source.replace(/^\/+/, '');
    }

    /**
     * Resolves the current photo and carries its profile update version where
     * available, preventing a browser from reusing an old avatar response.
     */
    function profileAvatarUrl(user) {
        const value = user && (user.avatar_url || user.profile_image_url);
        const url = assetUrl(value);
        if (!url) return '';
        const version = user?.profile_updated_at || user?.avatar_updated_at || user?.avatar_version;
        if (!version) return url;
        const separator = url.includes('?') ? '&' : '?';
        return url + separator + 'v=' + encodeURIComponent(String(version));
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

const billing = {
        entitlements: (options) => get('/billing/entitlements', null, options),
        plans: (options) => get('/billing/plans', null, options),
        config: (options) => get('/billing/config', null, options),
        subscription: (options) => get('/billing/subscription', null, options),
        history: (options) => get('/billing/history', null, options),

checkout: (planCode, returnPath, options) =>
            post('/billing/checkout', { plan_code: planCode, return_path: returnPath || null }, options),

cancel: (options) => post('/billing/subscription/cancel', {}, options),
        resume: (options) => post('/billing/subscription/resume', {}, options),
        changePlan: (planCode, options) => post('/billing/subscription/plan', { plan_code: planCode }, options),

sandbox: {
            checkout: (token, options) => get(`/billing/sandbox/checkout/${encodeURIComponent(token)}`, null, options),
            complete: (token, outcome, options) =>
                post(`/billing/sandbox/checkout/${encodeURIComponent(token)}/complete`, { outcome }, options),
            simulate: (kind, options) => post('/billing/sandbox/simulate', { kind }, options)
        }
    };

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

    const adminUsers = {
        list: (query, options) => get('/admin/users', query, options),
        deactivate: (id, options) => put(`/admin/users/${id}/deactivate`, {}, options),
        reactivate: (id, options) => put(`/admin/users/${id}/reactivate`, {}, options)
    };

    return {
        request, get, post, put, del, patch, uploadFile,
        sendChatMessage, makeCancellable, conversations, messaging, doctors, recommendations, patientProfiles, clinics, users, appointments, notifications, analytics, care, social, feedback, contact, adminInvitations, adminUsers, billing, virtualDoctor,
        isAuthenticated, getUser, getAccessToken, getRefreshToken,
        setSession, updateCurrentUser, refreshCurrentUser, displayName, profileAvatarUrl,
        clearSession, requireAuth, logout, getOrigin, assetUrl, resolveServiceOrigin, clearCache
    };

})();

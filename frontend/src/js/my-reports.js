/**
 * MedOrbit v2 - My Reports
 * A personal summary built from endpoints that already work:
 *   GET /users/me, GET /appointments, GET /conversations,
 *   GET /users/me/saved-places
 * Prescriptions/medical-records have their own dedicated pages
 * (my-prescriptions.html / my-records.html) and are out of scope here.
 * Printing is plain browser window.print() against the print stylesheet
 * in reports.css — no PDF library.
 */
const MyReports = (() => {

    const STATUS_KEY = {
        scheduled: 'appt.statusScheduled',
        confirmed: 'appt.statusConfirmed',
        in_progress: 'appt.statusInProgress',
        completed: 'appt.statusCompleted',
        cancelled: 'appt.statusCancelled',
        no_show: 'appt.statusNoShow'
    };

    const doctorCache = new Map();

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function name(d, arKey, enKey) {
        const ar = isAr();
        return ((ar ? d[arKey] : d[enKey]) || d[arKey] || d[enKey] || '').trim();
    }

    function doctorName(d) {
        const full = (name(d, 'first_name_ar', 'first_name_en') + ' ' + name(d, 'last_name_ar', 'last_name_en')).trim();
        return full || d.email || '';
    }

    function toDateOnlyStr(v) {
        if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
        const d = new Date(v);
        d.setUTCHours(d.getUTCHours() + 12);
        return d.toISOString().slice(0, 10);
    }

    function pad2(n) {
        return String(n).padStart(2, '0');
    }

    function todayKey() {
        const d = new Date();
        return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
    }

    function formatDate(v) {
        return new Date(v).toLocaleDateString(isAr() ? 'ar' : 'en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    function formatDateOnly(dateOnlyStr) {
        return new Date(dateOnlyStr + 'T00:00:00').toLocaleDateString(isAr() ? 'ar' : 'en-US', {
            year: 'numeric', month: 'short', day: 'numeric'
        });
    }

    function statRow(items) {
        return items.map((it) =>
            '<div class="report-stat"><div class="value">' + escapeHtml(String(it.value)) + '</div><div class="label">' + escapeHtml(it.label) + '</div></div>'
        ).join('');
    }

    // ================= PERSONAL INFO =================

    function renderPersonalInfo(profile) {
        const fullName = isAr()
            ? [profile.first_name_ar, profile.last_name_ar].filter(Boolean).join(' ')
            : [profile.first_name_en, profile.last_name_en].filter(Boolean).join(' ');

        const items = [
            { label: t('reports.fullName'), value: fullName || profile.email },
            { label: t('auth.email'), value: profile.email },
            { label: t('auth.phone'), value: profile.phone || '—' },
            { label: t('profile.city'), value: profile.city || '—' },
            { label: t('profile.memberSince'), value: profile.created_at ? formatDate(profile.created_at) : '—' },
            { label: t('profile.sectionLanguage'), value: profile.preferred_language === 'en' ? t('profile.languageEn') : t('profile.languageAr') }
        ];

        document.getElementById('reportInfoGrid').innerHTML = items.map((it) =>
            '<div class="report-info-item"><div class="label">' + escapeHtml(it.label) + '</div><div class="value">' + escapeHtml(it.value) + '</div></div>'
        ).join('');
    }

    // ================= APPOINTMENTS =================

    async function enrichDoctors(appts) {
        const ids = [...new Set(appts.map((a) => a.doctor_id).filter(Boolean))]
            .filter((id) => !doctorCache.has(id));

        await Promise.all(ids.map(async (id) => {
            try {
                const res = await API.doctors.get(id);
                doctorCache.set(id, res.data.doctor);
            } catch {
                doctorCache.set(id, null);
            }
        }));
    }

    async function loadAppointmentsSection() {
        try {
            const res = await API.appointments.list();
            const appts = res?.data || [];

            const upcoming = appts.filter((a) => !['cancelled', 'completed', 'no_show'].includes(a.status) && toDateOnlyStr(a.scheduled_date) >= todayKey()).length;
            const completed = appts.filter((a) => a.status === 'completed').length;
            const cancelled = appts.filter((a) => a.status === 'cancelled').length;

            document.getElementById('apptStatsRow').innerHTML = statRow([
                { value: appts.length, label: t('reports.statTotal') },
                { value: upcoming, label: t('dashboard.statUpcoming') },
                { value: completed, label: t('appt.statusCompleted') },
                { value: cancelled, label: t('appt.statusCancelled') }
            ]);

            const listEl = document.getElementById('apptReportList');
            const emptyEl = document.getElementById('apptReportEmpty');

            if (!appts.length) {
                listEl.innerHTML = '';
                emptyEl.classList.remove('hidden');
                return;
            }
            emptyEl.classList.add('hidden');

            const recent = [...appts].sort((a, b) => {
                const da = toDateOnlyStr(a.scheduled_date), db = toDateOnlyStr(b.scheduled_date);
                return da < db ? 1 : da > db ? -1 : 0;
            }).slice(0, 10);

            await enrichDoctors(recent);

            listEl.innerHTML = recent.map((a) => {
                const doctor = doctorCache.get(a.doctor_id);
                const doctorLabel = doctor ? doctorName(doctor) : ('#' + String(a.doctor_id || '').slice(0, 8));
                return (
                    '<div class="report-list-item">' +
                        '<span class="title">' + escapeHtml(doctorLabel) + ' · ' + escapeHtml(t(STATUS_KEY[a.status] || a.status)) + '</span>' +
                        '<span class="meta">' + escapeHtml(formatDateOnly(toDateOnlyStr(a.scheduled_date))) + '</span>' +
                    '</div>'
                );
            }).join('');
        } catch (err) {
            console.error('MyReports: failed to load appointments', err);
            document.getElementById('apptStatsRow').innerHTML = statRow([{ value: 0, label: t('reports.statTotal') }]);
            document.getElementById('apptReportEmpty').classList.remove('hidden');
        }
    }

    // ================= CONVERSATIONS =================

    async function loadConversationsSection() {
        try {
            const res = await API.conversations.list({ limit: 10 });
            const conversations = res?.data?.conversations || [];
            const total = res?.data?.pagination?.total ?? conversations.length;

            document.getElementById('convoStatsRow').innerHTML = statRow([
                { value: total, label: t('reports.statTotal') }
            ]);

            const listEl = document.getElementById('convoReportList');
            const emptyEl = document.getElementById('convoReportEmpty');

            if (!conversations.length) {
                listEl.innerHTML = '';
                emptyEl.classList.remove('hidden');
                return;
            }
            emptyEl.classList.add('hidden');

            listEl.innerHTML = conversations.map((c) =>
                '<div class="report-list-item">' +
                    '<span class="title">' + escapeHtml(c.title || t('dashboard.newChat')) + '</span>' +
                    '<span class="meta">' + escapeHtml(c.last_message_at ? formatDate(c.last_message_at) : (c.started_at ? formatDate(c.started_at) : '')) + '</span>' +
                '</div>'
            ).join('');
        } catch (err) {
            console.error('MyReports: failed to load conversations', err);
            document.getElementById('convoStatsRow').innerHTML = statRow([{ value: 0, label: t('reports.statTotal') }]);
            document.getElementById('convoReportEmpty').classList.remove('hidden');
        }
    }

    // ================= SAVED PLACES =================

    async function loadSavedPlacesSection() {
        try {
            const res = await API.users.savedPlaces();
            const places = res?.data?.places || [];

            const listEl = document.getElementById('placesReportList');
            const emptyEl = document.getElementById('placesReportEmpty');

            if (!places.length) {
                listEl.innerHTML = '';
                emptyEl.classList.remove('hidden');
                return;
            }
            emptyEl.classList.add('hidden');

            listEl.innerHTML = places.map((p) =>
                '<div class="report-list-item">' +
                    '<span class="title">' + escapeHtml(p.place_name || '') + '</span>' +
                    '<span class="meta">' + escapeHtml(p.address || '') + '</span>' +
                '</div>'
            ).join('');
        } catch (err) {
            console.error('MyReports: failed to load saved places', err);
            document.getElementById('placesReportEmpty').classList.remove('hidden');
        }
    }

    // ================= INIT =================

    async function load() {
        document.getElementById('reportLoading').classList.remove('hidden');
        document.getElementById('reportError').classList.add('hidden');
        document.getElementById('reportContent').classList.add('hidden');

        try {
            const res = await API.users.me();
            renderPersonalInfo(res.data);

            document.getElementById('reportGeneratedAt').textContent =
                t('reports.generatedAt') + ' ' + new Date().toLocaleString(isAr() ? 'ar' : 'en-US');

            document.getElementById('reportLoading').classList.add('hidden');
            document.getElementById('reportContent').classList.remove('hidden');

            loadAppointmentsSection();
            loadConversationsSection();
            loadSavedPlacesSection();
        } catch (err) {
            console.error('MyReports: failed to load profile', err);
            document.getElementById('reportLoading').classList.add('hidden');
            document.getElementById('reportError').classList.remove('hidden');
        }
    }

    function init() {
        if (!API.requireAuth()) return;

        document.getElementById('reportRetryBtn')?.addEventListener('click', load);
        document.getElementById('printBtn')?.addEventListener('click', () => window.print());

        window.addEventListener('languageChanged', () => {
            if (!document.getElementById('reportContent').classList.contains('hidden')) {
                load();
            }
        });

        load();
    }

    return { init };

})();

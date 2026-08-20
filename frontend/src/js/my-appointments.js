/**
 * MedOrbit v2 - My Appointments
 * GET /api/appointments returns raw appointment rows (doctor_id/clinic_id
 * only, no joined names) — this module enriches each row with a display
 * name by calling the existing public GET /doctors/:id and GET /clinics/:id
 * endpoints once per unique id. Tabs (upcoming/past/cancelled) are computed
 * client-side from status + scheduled_date since there's no dedicated
 * endpoint per bucket.
 */
const MyAppointments = (() => {

    const STATUS_KEY = {
        scheduled: 'appt.statusScheduled',
        confirmed: 'appt.statusConfirmed',
        in_progress: 'appt.statusInProgress',
        completed: 'appt.statusCompleted',
        cancelled: 'appt.statusCancelled',
        no_show: 'appt.statusNoShow'
    };

    const STATUS_BADGE = {
        scheduled: 'badge-info',
        confirmed: 'badge-primary',
        in_progress: 'badge-warning',
        completed: 'badge-success',
        cancelled: 'badge-danger',
        no_show: 'badge-danger'
    };

    const EMPTY_COPY = {
        upcoming: ['myAppts.emptyUpcomingTitle', 'myAppts.emptyUpcomingHint'],
        past: ['myAppts.emptyPastTitle', 'myAppts.emptyPastHint'],
        cancelled: ['myAppts.emptyCancelledTitle', 'myAppts.emptyCancelledHint']
    };

    const state = {
        appointments: [],
        activeTab: 'upcoming',
        doctorCache: new Map(),
        clinicCache: new Map()
    };

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

    function pad2(n) {
        return String(n).padStart(2, '0');
    }

    function todayKey() {
        const d = new Date();
        return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
    }

    function toDateOnlyStr(v) {
        if (typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v)) return v;

        // scheduled_date (a DATE column) round-trips through the backend as a
        // UTC instant built from the server's local midnight, so it can land
        // a few hours on either side of the UTC day boundary (e.g. local
        // midnight at UTC+3 serializes as "...T21:00:00.000Z" the day
        // before). Rounding to the nearest day recovers the intended
        // calendar date regardless of the server's offset.
        const d = new Date(v);
        d.setUTCHours(d.getUTCHours() + 12);
        return d.toISOString().slice(0, 10);
    }

    function formatDateDisplay(dateOnlyStr) {
        return new Date(dateOnlyStr + 'T00:00:00').toLocaleDateString(isAr() ? 'ar' : 'en-US', {
            year: 'numeric', month: 'short', day: 'numeric'
        });
    }

    function formatTimeRange(start, end) {
        return String(start).slice(0, 5) + ' – ' + String(end).slice(0, 5);
    }

    function isOnlineMessageAvailable(a) {
        return a.appointment_type === 'telemedicine'
            && ['scheduled','confirmed','in_progress'].includes(a.status);
    }

    // ================= LOAD + ENRICH =================

    async function enrich(appts) {
        const doctorIds = [...new Set(appts.map((a) => a.doctor_id).filter(Boolean))]
            .filter((id) => !state.doctorCache.has(id));
        const clinicIds = [...new Set(appts.map((a) => a.clinic_id).filter(Boolean))]
            .filter((id) => !state.clinicCache.has(id));

        await Promise.all([
            ...doctorIds.map(async (id) => {
                try {
                    const res = await API.doctors.get(id);
                    state.doctorCache.set(id, res.data.doctor);
                } catch {
                    state.doctorCache.set(id, null);
                }
            }),
            ...clinicIds.map(async (id) => {
                try {
                    const res = await API.clinics.get(id);
                    state.clinicCache.set(id, res.data?.clinic || res.data);
                } catch {
                    state.clinicCache.set(id, null);
                }
            })
        ]);
    }

    async function load() {
        document.getElementById('apptLoading').classList.remove('hidden');
        document.getElementById('apptError').classList.add('hidden');
        document.getElementById('apptContent').classList.add('hidden');

        try {
            const res = await API.appointments.list();
            const appts = res?.data || [];
            await enrich(appts);

            state.appointments = appts;
            document.getElementById('apptLoading').classList.add('hidden');
            document.getElementById('apptContent').classList.remove('hidden');
            render();
        } catch (err) {
            console.error('MyAppointments: failed to load appointments', err);
            document.getElementById('apptLoading').classList.add('hidden');
            document.getElementById('apptError').classList.remove('hidden');
        }
    }

    // ================= CLASSIFY / SORT =================

    function classify(a) {
        if (a.status === 'cancelled') return 'cancelled';
        const isPastDate = toDateOnlyStr(a.scheduled_date) < todayKey();
        if (a.status === 'completed' || a.status === 'no_show' || isPastDate) return 'past';
        return 'upcoming';
    }

    function sortAppointments(list, tab) {
        const sorted = [...list].sort((a, b) => {
            const da = toDateOnlyStr(a.scheduled_date) + (a.start_time || '');
            const db = toDateOnlyStr(b.scheduled_date) + (b.start_time || '');
            return da < db ? -1 : da > db ? 1 : 0;
        });
        return tab === 'upcoming' ? sorted : sorted.reverse();
    }

    // ================= RENDER =================

    function renderCard(a) {
        const doctor = state.doctorCache.get(a.doctor_id);
        const clinic = state.clinicCache.get(a.clinic_id);
        const doctorLabel = doctor ? doctorName(doctor) : ('#' + String(a.doctor_id || '').slice(0, 8));
        const clinicLabel = clinic ? name(clinic, 'name_ar', 'name_en') : ('#' + String(a.clinic_id || '').slice(0, 8));
        const dateOnly = toDateOnlyStr(a.scheduled_date);
        const canCancel = state.activeTab === 'upcoming' && (a.status === 'scheduled' || a.status === 'confirmed');
        const canOpenMessage = isOnlineMessageAvailable(a);
        const counterpartId = a.doctor_id;

        return (
            '<div class="appt-card">' +
                '<div class="appt-card-icon"><i class="fas ' + (a.appointment_type === 'telemedicine' ? 'fa-comments' : 'fa-hospital') + '"></i></div>' +
                '<div class="appt-card-body">' +
                    '<div class="appt-card-header">' +
                        '<span class="appt-card-number">' + escapeHtml(a.appointment_number || '') + '</span>' +
                        '<span class="badge ' + (STATUS_BADGE[a.status] || 'badge-info') + '">' + escapeHtml(t(STATUS_KEY[a.status] || a.status)) + '</span>' +
                    '</div>' +
                    '<div class="appt-card-meta">' +
                        '<span><i class="fas fa-user-doctor"></i>' + escapeHtml(doctorLabel) + '</span>' +
                        '<span><i class="fas fa-hospital"></i>' + escapeHtml(clinicLabel) + '</span>' +
                        '<span><i class="fas fa-calendar"></i>' + escapeHtml(formatDateDisplay(dateOnly)) + '</span>' +
                        '<span><i class="fas fa-clock"></i>' + escapeHtml(formatTimeRange(a.start_time, a.end_time)) + '</span>' +
                    '</div>' +
                    (a.reason_for_visit ? '<div class="appt-card-reason">' + escapeHtml(a.reason_for_visit) + '</div>' : '') +
                    ((canCancel || (canOpenMessage && counterpartId)) ? (
                        '<div class="appt-card-actions">' +
                            ((canOpenMessage && counterpartId) ? '<a class="btn btn-primary btn-sm" href="direct-messages.html?counterpart=' + encodeURIComponent(counterpartId) + '"><i class="fas fa-message"></i> ' + (isAr() ? 'فتح المحادثة الآمنة' : 'Open secure conversation') + '</a>' : '') +
                            (canCancel ? (
                            '<button type="button" class="btn btn-secondary btn-sm" data-cancel-id="' + escapeHtml(a.id) + '">' +
                                '<i class="fas fa-xmark"></i> ' + escapeHtml(t('myAppts.cancelBtn')) +
                            '</button>') : '') +
                        '</div>'
                    ) : '') +
                '</div>' +
            '</div>'
        );
    }

    function render() {
        document.querySelectorAll('.appt-tab').forEach((btn) => {
            btn.classList.toggle('active', btn.dataset.tab === state.activeTab);
        });

        const list = state.appointments.filter((a) => classify(a) === state.activeTab);
        const sorted = sortAppointments(list, state.activeTab);

        const listEl = document.getElementById('apptList');
        const emptyEl = document.getElementById('apptEmpty');

        if (!sorted.length) {
            listEl.innerHTML = '';
            listEl.classList.add('hidden');
            emptyEl.classList.remove('hidden');

            const [titleKey, hintKey] = EMPTY_COPY[state.activeTab];
            document.getElementById('apptEmptyTitle').textContent = t(titleKey);
            document.getElementById('apptEmptyHint').textContent = t(hintKey);
            return;
        }

        emptyEl.classList.add('hidden');
        listEl.classList.remove('hidden');
        listEl.innerHTML = sorted.map(renderCard).join('');

        listEl.querySelectorAll('[data-cancel-id]').forEach((btn) => {
            btn.addEventListener('click', () => openCancelModal(btn.dataset.cancelId));
        });
    }

    // ================= CANCEL MODAL =================

    function openCancelModal(id) {
        const backdrop = document.createElement('div');
        backdrop.className = 'modal-backdrop';
        backdrop.innerHTML =
            '<div class="modal-box">' +
                '<h3>' + escapeHtml(t('myAppts.cancelModalTitle')) + '</h3>' +
                '<p>' + escapeHtml(t('myAppts.cancelModalHint')) + '</p>' +
                '<textarea class="wizard-textarea" id="cancelReasonInput" placeholder="' + escapeHtml(t('myAppts.cancelReasonPlaceholder')) + '"></textarea>' +
                '<div class="alert" id="cancelModalAlert"></div>' +
                '<div class="modal-actions">' +
                    '<button type="button" class="btn btn-secondary" id="cancelDismissBtn">' + escapeHtml(t('myAppts.cancelDismiss')) + '</button>' +
                    '<button type="button" class="btn btn-primary" id="cancelConfirmBtn">' +
                        '<span class="btn-label">' + escapeHtml(t('myAppts.cancelConfirmBtn')) + '</span>' +
                        '<span class="spinner spinner-sm btn-spinner"></span>' +
                    '</button>' +
                '</div>' +
            '</div>';

        document.body.appendChild(backdrop);
        if (typeof Dom !== 'undefined') Dom.lockScroll();

        const close = () => {
            backdrop.remove();
            if (typeof Dom !== 'undefined') Dom.unlockScroll();
        };

        backdrop.addEventListener('click', (e) => {
            if (e.target === backdrop) close();
        });
        document.getElementById('cancelDismissBtn').addEventListener('click', close);
        document.getElementById('cancelConfirmBtn').addEventListener('click', () => confirmCancel(id, close));
    }

    async function confirmCancel(id, closeFn) {
        const btn = document.getElementById('cancelConfirmBtn');
        const alertBox = document.getElementById('cancelModalAlert');
        const reason = document.getElementById('cancelReasonInput').value.trim() || undefined;

        alertBox.className = 'alert';
        alertBox.textContent = '';
        btn.classList.add('loading');

        try {
            await API.appointments.cancel(id, { reason });
            const appt = state.appointments.find((a) => a.id === id);
            if (appt) appt.status = 'cancelled';
            if (typeof Toast !== 'undefined') Toast.success(t('myAppts.cancelSuccess'));
            closeFn();
            render();
        } catch (err) {
            console.error('MyAppointments: cancel failed', err);
            alertBox.classList.add('error');
            alertBox.textContent = t('myAppts.cancelError');
        } finally {
            btn.classList.remove('loading');
        }
    }

    // ================= INIT =================

    function init() {
        if (!API.requireAuth()) return;

        document.getElementById('apptTabs')?.addEventListener('click', (e) => {
            const btn = e.target.closest('.appt-tab');
            if (!btn) return;
            state.activeTab = btn.dataset.tab;
            render();
        });

        document.getElementById('apptRetryBtn')?.addEventListener('click', load);

        window.addEventListener('languageChanged', () => {
            if (!document.getElementById('apptContent').classList.contains('hidden')) {
                render();
            }
        });

        load();
    }

    return { init, isOnlineMessageAvailable };

})();

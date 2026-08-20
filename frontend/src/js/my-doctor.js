/**
 * MedOrbit v2 - My Doctor (patient's view of their treating doctor(s))
 *
 * GET /patients/me/doctors (backend/src/routes/patient.routes.js) — patient
 * id resolved server-side from the JWT, derived from appointment history,
 * same approach as my-patients.js's doctor-side mirror. "Upcoming
 * appointments with them" reuses the existing ownership-scoped
 * GET /appointments (API.appointments.list) rather than a new endpoint,
 * filtered client-side to the doctors in the list above.
 *
 * "Shared notes" calls GET /patients/me/doctors/:doctorId/notes once per
 * treating doctor and merges the results — only rows a doctor explicitly
 * marked visible_to_patient=true ever come back; doctor_notes never does
 * (see the isolation note in patient.routes.js).
 */
const MyDoctor = (() => {

    const STATUS_KEY = {
        scheduled: 'appt.statusScheduled',
        confirmed: 'appt.statusConfirmed',
        in_progress: 'appt.statusInProgress',
        completed: 'appt.statusCompleted',
        cancelled: 'appt.statusCancelled',
        no_show: 'appt.statusNoShow'
    };

    let doctors = [];

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

    function fmtDate(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return String(value);
        return d.toLocaleDateString(isAr() ? 'ar' : 'en-US', { year: 'numeric', month: 'short', day: 'numeric' });
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
        const d = new Date(v);
        d.setUTCHours(d.getUTCHours() + 12);
        return d.toISOString().slice(0, 10);
    }

    function isUpcoming(a) {
        if (a.status === 'cancelled' || a.status === 'completed' || a.status === 'no_show') return false;
        return toDateOnlyStr(a.scheduled_date) >= todayKey();
    }

    function doctorName(d) {
        const ar = isAr();
        const first = (ar ? d.first_name_ar : d.first_name_en) || d.first_name_ar || d.first_name_en || '';
        const last = (ar ? d.last_name_ar : d.last_name_en) || d.last_name_ar || d.last_name_en || '';
        return (first + ' ' + last).trim() || d.email || '';
    }

    function specialtyName(d) {
        return (isAr() ? d.specialty_ar : d.specialty_en) || d.specialty_ar || d.specialty_en || '';
    }

    function renderEmpty(icon, text) {
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas ' + icon + '"></i></div>' +
            '<h3>' + escapeHtml(text) + '</h3>' +
        '</div>';
    }

    function renderError(text) {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(text) + '</p>' +
        '</div>';
    }

    // ================= RENDER: DOCTORS =================

    function renderDoctors() {
        const el = document.getElementById('doctorsList');
        if (!el) return;
        if (!doctors.length) {
            el.innerHTML = renderEmpty('fa-user-doctor', t('myDoctor.noDoctors'));
            return;
        }
        el.innerHTML = '<div class="care-card-grid">' + doctors.map(renderDoctorCard).join('') + '</div>';
    }

    function renderDoctorCard(d) {
        const ar = isAr();
        const name = escapeHtml(doctorName(d));
        const initials = (doctorName(d) || '?').trim().charAt(0).toUpperCase();
        const specialty = escapeHtml(specialtyName(d));

        return (
            '<div class="care-person-card">' +
                '<div class="care-person-avatar">' +
                    (d.profile_image_url ? '<img src="' + escapeHtml(API.assetUrl(d.profile_image_url)) + '" alt="">' : escapeHtml(initials)) +
                '</div>' +
                '<div class="care-person-info">' +
                    '<div class="care-person-name" title="' + name + '">' + name + '</div>' +
                    (specialty ? '<div class="care-person-subtitle">' + specialty + '</div>' : '') +
                    '<div class="care-person-meta">' +
                        (d.next_appointment_date ? '<span><i class="fas fa-calendar-check"></i>' + escapeHtml(t('myPatients.nextVisit')) + ': ' + escapeHtml(fmtDate(d.next_appointment_date)) + '</span>' : '') +
                        (d.last_appointment_date ? '<span><i class="fas fa-clock-rotate-left"></i>' + escapeHtml(t('myPatients.lastVisit')) + ': ' + escapeHtml(fmtDate(d.last_appointment_date)) + '</span>' : '') +
                    '</div>' +
                    '<div class="care-person-actions">' +
                        '<a class="btn btn-primary btn-sm" href="doctor.html?id=' + encodeURIComponent(d.id) + '">' +
                            '<i class="fas fa-arrow-' + (ar ? 'left' : 'right') + '"></i> ' + escapeHtml(t('doctors.viewProfile')) +
                        '</a>' +
                        '<a class="btn btn-secondary btn-sm" href="direct-messages.html?counterpart=' + encodeURIComponent(d.id) + '">' +
                            '<i class="fas fa-message"></i> ' + (ar ? 'راسل الطبيب' : 'Message doctor') +
                        '</a>' +
                    '</div>' +
                '</div>' +
            '</div>'
        );
    }

    // ================= RENDER: UPCOMING APPOINTMENTS =================

    function renderUpcoming(list) {
        const el = document.getElementById('upcomingWithThemList');
        if (!el) return;
        if (!list.length) {
            el.innerHTML = renderEmpty('fa-calendar-xmark', t('myDoctor.noUpcoming'));
            return;
        }
        el.innerHTML = '<div class="records-real-list">' + list.map(({ a, d }) => (
            '<div class="records-real-card" style="cursor:default;">' +
                '<span class="records-real-icon"><i class="fas ' + (a.appointment_type === 'telemedicine' ? 'fa-comments' : 'fa-hospital') + '"></i></span>' +
                '<span class="records-real-card-main">' +
                    '<span class="records-real-title">' + escapeHtml(d ? doctorName(d) : '') + '</span>' +
                    '<span class="records-real-meta">' +
                        '<span class="records-real-badge ' + escapeHtml(String(a.status || '').toLowerCase()) + '">' + escapeHtml(t(STATUS_KEY[a.status] || a.status)) + '</span>' +
                        '<span><i class="fas fa-calendar"></i> ' + escapeHtml(fmtDate(a.scheduled_date)) + '</span>' +
                    '</span>' +
                '</span>' +
            '</div>'
        )).join('') + '</div>';
    }

    async function loadUpcoming() {
        const el = document.getElementById('upcomingWithThemList');
        if (!el) return;
        if (!doctors.length) {
            el.innerHTML = renderEmpty('fa-calendar-xmark', t('myDoctor.noUpcoming'));
            return;
        }
        try {
            const res = await API.appointments.list();
            const appts = Array.isArray(res?.data) ? res.data : [];
            const doctorMap = new Map(doctors.map((d) => [d.id, d]));
            const upcoming = appts
                .filter((a) => doctorMap.has(a.doctor_id) && isUpcoming(a))
                .sort((a, b) => (toDateOnlyStr(a.scheduled_date) < toDateOnlyStr(b.scheduled_date) ? -1 : 1))
                .map((a) => ({ a, d: doctorMap.get(a.doctor_id) }));
            renderUpcoming(upcoming);
        } catch (err) {
            console.error('MyDoctor: failed to load appointments', err);
            el.innerHTML = renderError(t('myDoctor.error'));
        }
    }

    // ================= LOAD =================

    // ================= RENDER: SHARED NOTES =================

    const RECORD_TYPE_KEY = {
        consultation: 'patientDetail.typeConsultation',
        follow_up: 'patientDetail.typeFollowUp',
        procedure: 'patientDetail.typeProcedure'
    };

    function renderSharedNotes(list) {
        const el = document.getElementById('sharedNotesList');
        if (!el) return;
        if (!list.length) {
            el.innerHTML = renderEmpty('fa-notes-medical', t('myDoctor.noSharedNotes'));
            return;
        }
        el.innerHTML = '<div class="note-timeline">' + list.map(({ n, d }) => (
            '<div class="note-timeline-item">' +
                '<div class="note-timeline-dot"></div>' +
                '<div class="note-card">' +
                    '<div class="note-card-header">' +
                        '<span>' + escapeHtml(d ? doctorName(d) : '') + ' — ' + escapeHtml(t(RECORD_TYPE_KEY[n.record_type] || n.record_type)) + '</span>' +
                        '<span>' + escapeHtml(fmtDate(n.created_at)) + '</span>' +
                    '</div>' +
                    '<div class="note-card-body">' +
                        (n.diagnosis ? '<strong>' + escapeHtml(t('patientDetail.diagnosis')) + ':</strong> ' + escapeHtml(n.diagnosis) + '<br>' : '') +
                        (n.clinical_notes ? escapeHtml(n.clinical_notes) : '') +
                    '</div>' +
                '</div>' +
            '</div>'
        )).join('') + '</div>';
    }

    async function loadSharedNotes() {
        const el = document.getElementById('sharedNotesList');
        if (!el) return;
        if (!doctors.length) {
            el.innerHTML = renderEmpty('fa-notes-medical', t('myDoctor.noSharedNotes'));
            return;
        }
        try {
            const results = await Promise.all(doctors.map((d) =>
                API.care.sharedNotes(d.id).then((res) => ({ d, notes: Array.isArray(res?.data) ? res.data : [] })).catch(() => ({ d, notes: [] }))
            ));
            const merged = results
                .flatMap(({ d, notes }) => notes.map((n) => ({ n, d })))
                .sort((a, b) => new Date(b.n.created_at) - new Date(a.n.created_at));
            renderSharedNotes(merged);
        } catch (err) {
            console.error('MyDoctor: failed to load shared notes', err);
            el.innerHTML = renderError(t('myDoctor.error'));
        }
    }

    async function load() {
        const doctorsList = document.getElementById('doctorsList');

        try {
            const res = await API.care.myDoctors();
            doctors = Array.isArray(res?.data) ? res.data : [];
            renderDoctors();
            await Promise.all([loadUpcoming(), loadSharedNotes()]);
        } catch (err) {
            console.error('MyDoctor: failed to load doctors', err);
            if (doctorsList) doctorsList.innerHTML = renderError(t('myDoctor.error'));
            const upcomingEl = document.getElementById('upcomingWithThemList');
            if (upcomingEl) upcomingEl.innerHTML = '';
            const notesEl = document.getElementById('sharedNotesList');
            if (notesEl) notesEl.innerHTML = '';
        }
    }

    async function init() {
        if (!API.requireAuth()) return;

        let isPatient = false;
        try {
            const res = await API.users.me();
            isPatient = res?.data?.role === 'patient';
        } catch (err) {
            console.error('MyDoctor: failed to verify role', err);
        }

        if (!isPatient) {
            document.getElementById('restrictedNotice').classList.remove('hidden');
            return;
        }

        document.getElementById('myDoctorContent').classList.remove('hidden');
        load();
    }

    return { init };

})();

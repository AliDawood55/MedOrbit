/**
 * MedOrbit v2 - Patient Detail (one patient's file, as seen by their doctor)
 *
 * GET/POST /doctors/me/patients/:patientId(/notes) (backend/src/routes/
 * doctor.routes.js) — the doctor id is resolved server-side from the JWT,
 * and every request is gated on a real doctor<->patient relationship check
 * (an appointment must exist between them) that runs before any patient
 * data is queried. A patient id with no such relationship 404s, same as one
 * that doesn't exist at all, so a doctor probing random ids learns nothing.
 */
const PatientDetail = (() => {

    const STATUS_KEY = {
        scheduled: 'appt.statusScheduled',
        confirmed: 'appt.statusConfirmed',
        in_progress: 'appt.statusInProgress',
        completed: 'appt.statusCompleted',
        cancelled: 'appt.statusCancelled',
        no_show: 'appt.statusNoShow'
    };

    const RECORD_TYPE_KEY = {
        consultation: 'patientDetail.typeConsultation',
        follow_up: 'patientDetail.typeFollowUp',
        procedure: 'patientDetail.typeProcedure'
    };

    let notes = [];

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function label(ar, en) {
        return isAr() ? ar : en;
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
        if (!value) return label('غير محدد', 'Not set');
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return String(value);
        return d.toLocaleDateString(isAr() ? 'ar' : 'en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    function fmtTimeRange(start, end) {
        if (!start || !end) return '';
        return String(start).slice(0, 5) + ' – ' + String(end).slice(0, 5);
    }

    function patientName(p) {
        const ar = isAr();
        const first = (ar ? p.first_name_ar : p.first_name_en) || p.first_name_ar || p.first_name_en || '';
        const last = (ar ? p.last_name_ar : p.last_name_en) || p.last_name_ar || p.last_name_en || '';
        return (first + ' ' + last).trim() || p.email || '';
    }

    function getPatientIdFromUrl() {
        return new URLSearchParams(window.location.search).get('id');
    }

    function renderSectionEmpty(icon, text) {
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas ' + icon + '"></i></div>' +
            '<h3>' + escapeHtml(text) + '</h3>' +
        '</div>';
    }

    function renderSectionError() {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('patientDetail.loadError')) + '</p>' +
        '</div>';
    }

    // ================= RENDER =================

    function renderHeader(p) {
        const header = document.getElementById('patientHeader');
        if (!header) return;
        const name = escapeHtml(patientName(p));
        const initials = (patientName(p) || '?').trim().charAt(0).toUpperCase();
        header.innerHTML =
            '<div class="care-detail-avatar">' +
                (p.profile_image_url ? '<img src="' + escapeHtml(p.profile_image_url) + '" alt="">' : escapeHtml(initials)) +
            '</div>' +
            '<div>' +
                '<div class="care-detail-name">' + name + '</div>' +
                '<div class="care-detail-subtitle">' + escapeHtml(p.email || '') + (p.phone ? ' · ' + escapeHtml(p.phone) : '') + '</div>' +
            '</div>';
    }

    function renderAppointments(list) {
        const el = document.getElementById('appointmentHistoryList');
        if (!el) return;
        if (!list.length) {
            el.innerHTML = renderSectionEmpty('fa-calendar-xmark', t('patientDetail.noAppointments'));
            return;
        }
        el.innerHTML = '<div class="records-real-list">' + list.map((a) => {
            const status = String(a.status || '').toLowerCase();
            return (
                '<div class="records-real-card" style="cursor:default;">' +
                    '<span class="records-real-icon"><i class="fas ' + (a.appointment_type === 'telemedicine' ? 'fa-video' : 'fa-hospital') + '"></i></span>' +
                    '<span class="records-real-card-main">' +
                        '<span class="records-real-title">' + escapeHtml(fmtDate(a.scheduled_date)) + '</span>' +
                        '<span class="records-real-meta">' +
                            '<span class="records-real-badge ' + escapeHtml(status) + '">' + escapeHtml(t(STATUS_KEY[a.status] || a.status)) + '</span>' +
                            (a.start_time ? '<span><i class="fas fa-clock"></i> ' + escapeHtml(fmtTimeRange(a.start_time, a.end_time)) + '</span>' : '') +
                        '</span>' +
                        (a.reason_for_visit ? '<span class="records-real-subtitle">' + escapeHtml(a.reason_for_visit) + '</span>' : '') +
                    '</span>' +
                '</div>'
            );
        }).join('') + '</div>';
    }

    function renderNotes(list) {
        const el = document.getElementById('notesTimeline');
        if (!el) return;
        if (!list.length) {
            el.innerHTML = renderSectionEmpty('fa-notes-medical', t('patientDetail.noNotes'));
            return;
        }
        el.innerHTML = list.map((n) => (
            '<div class="note-timeline-item">' +
                '<div class="note-timeline-dot"></div>' +
                '<div class="note-card">' +
                    '<div class="note-card-header">' +
                        '<span>' + escapeHtml(t(RECORD_TYPE_KEY[n.record_type] || n.record_type)) + '</span>' +
                        '<span>' + escapeHtml(fmtDate(n.created_at)) + (n.is_draft ? ' · ' + escapeHtml(t('patientDetail.draftBadge')) : '') + (n.visible_to_patient ? ' · ' + escapeHtml(t('patientDetail.sharedBadge')) : '') + '</span>' +
                    '</div>' +
                    '<div class="note-card-body">' +
                        (n.chief_complaint ? '<strong>' + escapeHtml(t('patientDetail.chiefComplaint')) + ':</strong> ' + escapeHtml(n.chief_complaint) + '<br>' : '') +
                        (n.diagnosis ? '<strong>' + escapeHtml(t('patientDetail.diagnosis')) + ':</strong> ' + escapeHtml(n.diagnosis) + '<br>' : '') +
                        (n.clinical_notes ? escapeHtml(n.clinical_notes) : '') +
                    '</div>' +
                '</div>' +
            '</div>'
        )).join('');
    }

    function renderPrescriptions(list) {
        const el = document.getElementById('prescriptionsList');
        if (!el) return;
        if (!list.length) {
            el.innerHTML = renderSectionEmpty('fa-prescription-bottle-medical', t('patientDetail.noPrescriptions'));
            return;
        }
        el.innerHTML = '<div class="records-real-list">' + list.map((rx) => {
            const status = String(rx.status || '').toLowerCase();
            return (
                '<div class="records-real-card" style="cursor:default;">' +
                    '<span class="records-real-icon"><i class="fas fa-prescription-bottle-medical"></i></span>' +
                    '<span class="records-real-card-main">' +
                        '<span class="records-real-title">' + escapeHtml(rx.prescription_number || '') + '</span>' +
                        '<span class="records-real-meta">' +
                            '<span class="records-real-badge ' + escapeHtml(status) + '">' + escapeHtml(status) + '</span>' +
                            '<span><i class="fas fa-calendar"></i> ' + escapeHtml(fmtDate(rx.prescription_date)) + '</span>' +
                        '</span>' +
                        (rx.diagnosis ? '<span class="records-real-subtitle">' + escapeHtml(rx.diagnosis) + '</span>' : '') +
                    '</span>' +
                '</div>'
            );
        }).join('') + '</div>';
    }

    // ================= ADD NOTE FORM =================

    function validateNote() {
        const complaint = document.getElementById('noteChiefComplaint').value.trim();
        const clinical = document.getElementById('noteClinicalNotes').value.trim();
        if (!complaint && !clinical) return t('patientDetail.errorNoteRequired');
        return null;
    }

    function clearNoteForm() {
        document.getElementById('noteRecordType').value = 'consultation';
        document.getElementById('noteDiagnosis').value = '';
        document.getElementById('noteChiefComplaint').value = '';
        document.getElementById('noteClinicalNotes').value = '';
        document.getElementById('noteDraftToggle').checked = false;
        document.getElementById('noteShareToggle').checked = false;
    }

    function showNoteResult(ok) {
        const icon = document.getElementById('noteFormResultIcon');
        icon.className = 'feedback-result-icon ' + (ok ? 'success' : 'error');
        icon.innerHTML = '<i class="fas ' + (ok ? 'fa-circle-check' : 'fa-triangle-exclamation') + '"></i>';
        document.getElementById('noteFormResultTitle').textContent = t(ok ? 'patientDetail.noteSavedTitle' : 'patientDetail.noteErrorTitle');
        document.getElementById('noteFormResultHint').textContent = t(ok ? 'patientDetail.noteSavedHint' : 'patientDetail.noteErrorHint');
        document.getElementById('noteFormResult').classList.remove('hidden');
    }

    async function submitNote(patientId) {
        const alertBox = document.getElementById('noteFormAlert');
        alertBox.className = 'alert';

        const err = validateNote();
        if (err) {
            alertBox.classList.add('error');
            alertBox.textContent = err;
            return;
        }

        const btn = document.getElementById('noteSubmitBtn');
        btn.classList.add('loading');

        const body = {
            record_type: document.getElementById('noteRecordType').value,
            diagnosis: document.getElementById('noteDiagnosis').value.trim(),
            chief_complaint: document.getElementById('noteChiefComplaint').value.trim(),
            clinical_notes: document.getElementById('noteClinicalNotes').value.trim(),
            is_draft: document.getElementById('noteDraftToggle').checked,
            visible_to_patient: document.getElementById('noteShareToggle').checked
        };

        try {
            const res = await API.care.addPatientNote(patientId, body);
            notes = [res.data, ...notes];
            renderNotes(notes);
            clearNoteForm();
            showNoteResult(true);
        } catch (err2) {
            console.error('PatientDetail: failed to save note', err2);
            showNoteResult(false);
        }

        btn.classList.remove('loading');
    }

    // ================= LOAD =================

    async function loadPatient(patientId) {
        try {
            const res = await API.care.patientDetail(patientId);
            const data = res?.data || {};
            notes = Array.isArray(data.notes) ? data.notes : [];
            renderHeader(data.patient || {});
            renderAppointments(Array.isArray(data.appointments) ? data.appointments : []);
            renderNotes(notes);
            renderPrescriptions(Array.isArray(data.prescriptions) ? data.prescriptions : []);
        } catch (err) {
            if (err?.status === 404) {
                document.getElementById('patientDetailContent').classList.add('hidden');
                document.getElementById('notFoundNotice').classList.remove('hidden');
                return;
            }
            console.error('PatientDetail: failed to load patient', err);
            ['appointmentHistoryList', 'notesTimeline', 'prescriptionsList'].forEach((id) => {
                const el = document.getElementById(id);
                if (el) el.innerHTML = renderSectionError();
            });
        }
    }

    // ================= INIT =================

    async function init() {
        if (!API.requireAuth()) return;

        const patientId = getPatientIdFromUrl();
        if (!patientId) {
            document.getElementById('noIdNotice').classList.remove('hidden');
            return;
        }

        let isDoctor = false;
        try {
            const res = await API.users.me();
            isDoctor = res?.data?.role === 'doctor';
        } catch (err) {
            console.error('PatientDetail: failed to verify role', err);
        }

        if (!isDoctor) {
            document.getElementById('restrictedNotice').classList.remove('hidden');
            return;
        }

        document.getElementById('patientDetailContent').classList.remove('hidden');
        loadPatient(patientId);

        document.getElementById('noteSubmitBtn').addEventListener('click', () => submitNote(patientId));
        document.getElementById('noteFormResultCloseBtn').addEventListener('click', () => {
            document.getElementById('noteFormResult').classList.add('hidden');
        });
    }

    return { init };

})();

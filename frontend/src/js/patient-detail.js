/**
 * MedOrbit v2 - Patient Detail (one patient's file, as seen by their doctor)
 *
 * GET /doctors/me/patients/:patientId (backend/src/routes/doctor.routes.js)
 * — the doctor id is resolved server-side from the JWT, and every request
 * is gated on a real doctor<->patient relationship check (an appointment
 * must exist between them) that runs before any patient data is queried.
 * A patient id with no such relationship 404s, same as one that doesn't
 * exist at all, so a doctor probing random ids learns nothing.
 *
 * Medical-record authoring on this page submits through the canonical
 * POST /api/medical-records (backend/src/routes/medicalRecord.routes.js)
 * rather than doctor.routes.js's notes endpoint, so every field the form
 * collects is one the backend actually persists (including appointment_id,
 * symptoms, treatment_plan, prognosis, doctor_notes — none of which the
 * notes endpoint accepted).
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
    let appointments = [];
    let prescriptions = [];
    let currentPatientId = null;
    let rxItemSeq = 0;

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
                (p.profile_image_url ? '<img src="' + escapeHtml(API.assetUrl(p.profile_image_url)) + '" alt="" data-fallback-initials="' + escapeHtml(initials) + '" onerror="PatientDetail.__avatarFallback(this)">' : escapeHtml(initials)) +
            '</div>' +
            '<div>' +
                '<h1 class="care-detail-name">' + name + '</h1>' +
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
                    '<span class="records-real-icon"><i class="fas ' + (a.appointment_type === 'telemedicine' ? 'fa-comments' : 'fa-hospital') + '"></i></span>' +
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
                    '<div class="care-person-actions" style="margin-top:10px;">' +
                        '<button type="button" class="btn btn-secondary btn-sm" data-edit-record-id="' + escapeHtml(n.id) + '"><i class="fas fa-pen"></i> ' + escapeHtml(t('patientDetail.editRecord')) + '</button>' +
                        '<button type="button" class="btn btn-secondary btn-sm" data-delete-record-id="' + escapeHtml(n.id) + '"><i class="fas fa-trash"></i> ' + escapeHtml(t('patientDetail.deleteRecord')) + '</button>' +
                    '</div>' +
                '</div>' +
            '</div>'
        )).join('');

        el.querySelectorAll('[data-edit-record-id]').forEach((btn) => {
            btn.addEventListener('click', () => openEditRecordModal(btn.dataset.editRecordId));
        });
        el.querySelectorAll('[data-delete-record-id]').forEach((btn) => {
            btn.addEventListener('click', () => openDeleteRecordModal(btn.dataset.deleteRecordId));
        });
    }

    // ================= EDIT / DELETE MEDICAL RECORD =================
    // Both mutate through PUT/DELETE /api/medical-records/:id (backend/src/
    // routes/medicalRecord.routes.js), which the backend scopes to records
    // owned by the calling doctor (doctor_id match) — every record in this
    // timeline already satisfies that, since GET /doctors/me/patients/:id
    // filters its notes query by doctor_id AND patient_id too.
    //
    // PUT there is full-field, not partial: it always overwrites diagnosis,
    // treatment_plan, clinical_notes, doctor_notes, vitals and is_draft from
    // the request body, so an omitted field would be persisted as NULL. The
    // notes list backing this timeline doesn't carry every one of those
    // fields (vitals is missing), so edit always loads the canonical record
    // via GET /api/medical-records/:id first and round-trips its vitals
    // unchanged rather than risk wiping it.
    //
    // record_type/chief_complaint/symptoms/prognosis are NOT columns the PUT
    // query touches, so they stay read-only here (visible on the card, not
    // editable in this form).

    function openEditRecordModal(id) {
        const backdrop = document.createElement('div');
        backdrop.className = 'modal-backdrop';
        backdrop.innerHTML =
            '<div class="modal-box" style="max-width:560px;">' +
                '<h3>' + escapeHtml(t('patientDetail.editRecordTitle')) + '</h3>' +
                '<div class="alert" id="editRecordModalAlert"></div>' +
                '<div id="editRecordLoading" style="padding:24px 0;text-align:center;"><span class="spinner spinner-sm"></span></div>' +
                '<div id="editRecordForm" class="hidden">' +
                    '<div class="form-group">' +
                        '<label for="editRecordDiagnosis">' + escapeHtml(t('patientDetail.diagnosis')) + '</label>' +
                        '<div class="input-wrapper">' +
                            '<i class="fas fa-stethoscope"></i>' +
                            '<input type="text" id="editRecordDiagnosis">' +
                        '</div>' +
                    '</div>' +
                    '<div class="form-group">' +
                        '<label for="editRecordTreatmentPlan">' + escapeHtml(t('patientDetail.treatmentPlan')) + '</label>' +
                        '<textarea class="feedback-textarea" id="editRecordTreatmentPlan" style="min-height:60px;"></textarea>' +
                    '</div>' +
                    '<div class="form-group">' +
                        '<label for="editRecordClinicalNotes">' + escapeHtml(t('patientDetail.clinicalNotes')) + '</label>' +
                        '<textarea class="feedback-textarea" id="editRecordClinicalNotes"></textarea>' +
                    '</div>' +
                    '<div class="form-group">' +
                        '<label for="editRecordDoctorNotes">' + escapeHtml(t('patientDetail.doctorNotes')) + '</label>' +
                        '<textarea class="feedback-textarea" id="editRecordDoctorNotes"></textarea>' +
                    '</div>' +
                    '<label class="care-toggle-row">' +
                        '<input type="checkbox" id="editRecordDraftToggle">' +
                        '<span>' + escapeHtml(t('patientDetail.saveDraft')) + '</span>' +
                    '</label>' +
                '</div>' +
                '<div class="modal-actions">' +
                    '<button type="button" class="btn btn-secondary" id="editRecordDismissBtn">' + escapeHtml(t('patientDetail.cancelEdit')) + '</button>' +
                    '<button type="button" class="btn btn-primary hidden" id="editRecordSaveBtn">' +
                        '<span class="btn-label">' + escapeHtml(t('patientDetail.saveChanges')) + '</span>' +
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

        backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });
        document.getElementById('editRecordDismissBtn').addEventListener('click', close);

        API.care.getMedicalRecord(id).then((res) => {
            const canonical = res?.data;
            if (!canonical) throw new Error('empty medical record response');

            document.getElementById('editRecordDiagnosis').value = canonical.diagnosis || '';
            document.getElementById('editRecordTreatmentPlan').value = canonical.treatment_plan || '';
            document.getElementById('editRecordClinicalNotes').value = canonical.clinical_notes || '';
            document.getElementById('editRecordDoctorNotes').value = canonical.doctor_notes || '';
            document.getElementById('editRecordDraftToggle').checked = !!canonical.is_draft;

            document.getElementById('editRecordLoading').classList.add('hidden');
            document.getElementById('editRecordForm').classList.remove('hidden');
            const saveBtn = document.getElementById('editRecordSaveBtn');
            saveBtn.classList.remove('hidden');
            saveBtn.addEventListener('click', () => submitEditRecord(id, canonical, close));
        }).catch((err) => {
            console.error('PatientDetail: failed to load medical record for edit', err);
            document.getElementById('editRecordLoading').classList.add('hidden');
            const alertBox = document.getElementById('editRecordModalAlert');
            alertBox.className = 'alert';
            alertBox.classList.add('error');
            alertBox.textContent = t('patientDetail.editLoadError');
        });
    }

    async function submitEditRecord(id, canonical, closeFn) {
        const btn = document.getElementById('editRecordSaveBtn');
        const alertBox = document.getElementById('editRecordModalAlert');
        alertBox.className = 'alert';
        btn.classList.add('loading');
        btn.disabled = true;

        const body = {
            diagnosis: document.getElementById('editRecordDiagnosis').value.trim(),
            treatment_plan: document.getElementById('editRecordTreatmentPlan').value.trim(),
            clinical_notes: document.getElementById('editRecordClinicalNotes').value.trim(),
            doctor_notes: document.getElementById('editRecordDoctorNotes').value.trim(),
            vitals: canonical.vitals,
            is_draft: document.getElementById('editRecordDraftToggle').checked
        };

        try {
            const res = await API.care.updateMedicalRecord(id, body);
            const updated = res?.data;
            if (updated) {
                notes = notes.map((n) => (String(n.id) === String(id) ? { ...n, ...updated } : n));
                renderNotes(notes);
            }
            if (typeof Toast !== 'undefined') Toast.success(t('patientDetail.editSuccess'));
            closeFn();
        } catch (err) {
            console.error('PatientDetail: failed to update medical record', err);
            alertBox.classList.add('error');
            alertBox.textContent = t('patientDetail.editError');
            btn.classList.remove('loading');
            btn.disabled = false;
        }
    }

    function openDeleteRecordModal(id) {
        const record = notes.find((n) => String(n.id) === String(id));
        const context = record ? (record.diagnosis || record.record_number || '') : '';

        const backdrop = document.createElement('div');
        backdrop.className = 'modal-backdrop';
        backdrop.innerHTML =
            '<div class="modal-box">' +
                '<h3>' + escapeHtml(t('patientDetail.deleteModalTitle')) + '</h3>' +
                '<p>' + escapeHtml(t('patientDetail.deleteModalHint')) + (context ? ' — ' + escapeHtml(context) : '') + '</p>' +
                '<div class="alert" id="deleteRecordModalAlert"></div>' +
                '<div class="modal-actions">' +
                    '<button type="button" class="btn btn-secondary" id="deleteRecordDismissBtn">' + escapeHtml(t('patientDetail.deleteDismiss')) + '</button>' +
                    '<button type="button" class="btn btn-primary" id="deleteRecordConfirmBtn">' +
                        '<span class="btn-label">' + escapeHtml(t('patientDetail.deleteConfirmBtn')) + '</span>' +
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

        backdrop.addEventListener('click', (e) => { if (e.target === backdrop) close(); });
        document.getElementById('deleteRecordDismissBtn').addEventListener('click', close);
        document.getElementById('deleteRecordConfirmBtn').addEventListener('click', () => confirmDeleteRecord(id, close));
    }

    async function confirmDeleteRecord(id, closeFn) {
        const btn = document.getElementById('deleteRecordConfirmBtn');
        const alertBox = document.getElementById('deleteRecordModalAlert');
        alertBox.className = 'alert';
        btn.classList.add('loading');
        btn.disabled = true;

        try {
            await API.care.deleteMedicalRecord(id);
            notes = notes.filter((n) => String(n.id) !== String(id));
            renderNotes(notes);
            if (typeof Toast !== 'undefined') Toast.success(t('patientDetail.deleteSuccess'));
            closeFn();
        } catch (err) {
            console.error('PatientDetail: failed to delete medical record', err);
            alertBox.classList.add('error');
            alertBox.textContent = t('patientDetail.deleteError');
            btn.classList.remove('loading');
            btn.disabled = false;
        }
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

    // ================= ADD MEDICAL RECORD FORM =================
    // Submits through the canonical POST /api/medical-records contract
    // (API.care.createMedicalRecord) rather than the older freeform
    // /doctors/me/patients/:patientId/notes endpoint, so every field this
    // form collects is one the backend actually persists — see the field
    // mapping this was implemented from. appointment_id is required because
    // the backend resolves patient_id/doctor_id from that appointment and
    // 404s without a valid one; the select is populated only from this
    // doctor's real appointments with this patient (never free text).

    function renderAppointmentOptions(list) {
        const select = document.getElementById('noteAppointment');
        const btn = document.getElementById('noteSubmitBtn');
        if (!select) return;
        if (!list.length) {
            select.innerHTML = '<option value="">' + escapeHtml(t('patientDetail.noAppointmentForRecord')) + '</option>';
            select.disabled = true;
            if (btn) btn.disabled = true;
            return;
        }
        select.disabled = false;
        if (btn) btn.disabled = false;
        select.innerHTML = list.map((a) => (
            '<option value="' + escapeHtml(a.id) + '">' +
                escapeHtml(fmtDate(a.scheduled_date)) +
                (a.reason_for_visit ? ' — ' + escapeHtml(a.reason_for_visit) : '') +
            '</option>'
        )).join('');
    }

    function validateRecord() {
        const appointmentId = document.getElementById('noteAppointment').value;
        if (!appointmentId) return t('patientDetail.errorAppointmentRequired');
        const complaint = document.getElementById('noteChiefComplaint').value.trim();
        const clinical = document.getElementById('noteClinicalNotes').value.trim();
        if (!complaint && !clinical) return t('patientDetail.errorNoteRequired');
        return null;
    }

    function clearRecordForm() {
        document.getElementById('noteRecordType').value = 'consultation';
        document.getElementById('noteDiagnosis').value = '';
        document.getElementById('noteChiefComplaint').value = '';
        document.getElementById('noteSymptoms').value = '';
        document.getElementById('noteTreatmentPlan').value = '';
        document.getElementById('notePrognosis').value = '';
        document.getElementById('noteClinicalNotes').value = '';
        document.getElementById('noteDoctorNotes').value = '';
        document.getElementById('noteDraftToggle').checked = false;
    }

    function showRecordResult(ok) {
        const icon = document.getElementById('noteFormResultIcon');
        icon.className = 'feedback-result-icon ' + (ok ? 'success' : 'error');
        icon.innerHTML = '<i class="fas ' + (ok ? 'fa-circle-check' : 'fa-triangle-exclamation') + '"></i>';
        document.getElementById('noteFormResultTitle').textContent = t(ok ? 'patientDetail.noteSavedTitle' : 'patientDetail.noteErrorTitle');
        document.getElementById('noteFormResultHint').textContent = t(ok ? 'patientDetail.noteSavedHint' : 'patientDetail.noteErrorHint');
        document.getElementById('noteFormResult').classList.remove('hidden');
    }

    async function submitRecord() {
        const alertBox = document.getElementById('noteFormAlert');
        alertBox.className = 'alert';

        const err = validateRecord();
        if (err) {
            alertBox.classList.add('error');
            alertBox.textContent = err;
            return;
        }

        const btn = document.getElementById('noteSubmitBtn');
        btn.classList.add('loading');
        btn.disabled = true;

        const symptoms = document.getElementById('noteSymptoms').value
            .split(',')
            .map((s) => s.trim())
            .filter(Boolean);

        const body = {
            appointment_id: document.getElementById('noteAppointment').value,
            record_type: document.getElementById('noteRecordType').value,
            diagnosis: document.getElementById('noteDiagnosis').value.trim(),
            chief_complaint: document.getElementById('noteChiefComplaint').value.trim(),
            symptoms,
            treatment_plan: document.getElementById('noteTreatmentPlan').value.trim(),
            prognosis: document.getElementById('notePrognosis').value.trim(),
            clinical_notes: document.getElementById('noteClinicalNotes').value.trim(),
            doctor_notes: document.getElementById('noteDoctorNotes').value.trim(),
            is_draft: document.getElementById('noteDraftToggle').checked
        };

        try {
            const res = await API.care.createMedicalRecord(body);
            notes = [res.data, ...notes];
            renderNotes(notes);
            clearRecordForm();
            showRecordResult(true);
        } catch (err2) {
            console.error('PatientDetail: failed to save medical record', err2);
            showRecordResult(false);
        }

        btn.classList.remove('loading');
        btn.disabled = false;
    }

    // ================= CREATE PRESCRIPTION FORM =================
    // Submits through POST /api/prescriptions (backend/src/routes/prescription.routes.js).
    // Unlike medical-record creation, this contract requires patient_id
    // explicitly — sourced from the server-returned patient object (never
    // a URL/editable field) — plus appointment_id from this doctor's real
    // appointments with this patient. The backend re-verifies both before
    // writing anything, so this is a UX guard, not the authorization
    // boundary. Item fields mirror medorbit.prescription_items' NOT NULL
    // columns exactly (medication_name_ar/en, dosage, frequency, quantity);
    // duration/instructions are nullable there, so they stay optional here.

    function renderRxAppointmentOptions(list) {
        const select = document.getElementById('rxAppointment');
        const submitBtn = document.getElementById('rxSubmitBtn');
        const addBtn = document.getElementById('rxAddItemBtn');
        if (!select) return;
        if (!list.length) {
            select.innerHTML = '<option value="">' + escapeHtml(t('patientDetail.noAppointmentForRx')) + '</option>';
            select.disabled = true;
            if (submitBtn) submitBtn.disabled = true;
            if (addBtn) addBtn.disabled = true;
            return;
        }
        select.disabled = false;
        if (submitBtn) submitBtn.disabled = false;
        if (addBtn) addBtn.disabled = false;
        select.innerHTML = list.map((a) => (
            '<option value="' + escapeHtml(a.id) + '">' +
                escapeHtml(fmtDate(a.scheduled_date)) +
                (a.start_time ? ' · ' + escapeHtml(String(a.start_time).slice(0, 5)) : '') +
                (a.reason_for_visit ? ' — ' + escapeHtml(a.reason_for_visit) : '') +
            '</option>'
        )).join('');
    }

    function createRxItemRow() {
        rxItemSeq += 1;
        const row = Dom.el('div', { className: 'rx-item-card', dataset: { rxItem: String(rxItemSeq) } }, [
            Dom.el('button', {
                type: 'button',
                className: 'btn btn-ghost btn-sm btn-icon rx-item-remove',
                'aria-label': t('patientDetail.removeMedication'),
                onClick: () => removeRxItemRow(row)
            }, [Dom.el('i', { className: 'fas fa-xmark' })]),
            Dom.el('div', { className: 'form-row' }, [
                Dom.el('div', { className: 'form-group' }, [
                    Dom.el('label', { text: t('patientDetail.medicationNameAr') }),
                    Dom.el('input', { type: 'text', className: 'rx-item-name-ar' })
                ]),
                Dom.el('div', { className: 'form-group' }, [
                    Dom.el('label', { text: t('patientDetail.medicationNameEn') }),
                    Dom.el('input', { type: 'text', className: 'rx-item-name-en' })
                ])
            ]),
            Dom.el('div', { className: 'form-row' }, [
                Dom.el('div', { className: 'form-group' }, [
                    Dom.el('label', { text: t('patientDetail.dosage') }),
                    Dom.el('input', { type: 'text', className: 'rx-item-dosage' })
                ]),
                Dom.el('div', { className: 'form-group' }, [
                    Dom.el('label', { text: t('patientDetail.frequency') }),
                    Dom.el('input', { type: 'text', className: 'rx-item-frequency' })
                ])
            ]),
            Dom.el('div', { className: 'form-row' }, [
                Dom.el('div', { className: 'form-group' }, [
                    Dom.el('label', { text: t('patientDetail.duration') }),
                    Dom.el('input', { type: 'text', className: 'rx-item-duration' })
                ]),
                Dom.el('div', { className: 'form-group' }, [
                    Dom.el('label', { text: t('patientDetail.quantity') }),
                    Dom.el('input', { type: 'number', className: 'rx-item-quantity', min: '1', step: '1' })
                ])
            ]),
            Dom.el('div', { className: 'form-group' }, [
                Dom.el('label', { text: t('patientDetail.itemInstructions') }),
                Dom.el('textarea', { className: 'feedback-textarea rx-item-instructions', style: 'min-height:48px;' })
            ])
        ]);
        return row;
    }

    function updateRxRemoveButtons() {
        const container = document.getElementById('rxItemsContainer');
        const rows = Dom.$$('.rx-item-card', container);
        rows.forEach((row) => {
            const btn = Dom.$('.rx-item-remove', row);
            if (btn) btn.style.display = rows.length > 1 ? '' : 'none';
        });
    }

    function addRxItemRow() {
        const container = document.getElementById('rxItemsContainer');
        container.appendChild(createRxItemRow());
        updateRxRemoveButtons();
    }

    function removeRxItemRow(row) {
        const container = document.getElementById('rxItemsContainer');
        if (Dom.$$('.rx-item-card', container).length <= 1) return;
        row.remove();
        updateRxRemoveButtons();
    }

    function resetRxItems() {
        const container = document.getElementById('rxItemsContainer');
        container.innerHTML = '';
        addRxItemRow();
    }

    function collectRxItems() {
        const container = document.getElementById('rxItemsContainer');
        const rows = Dom.$$('.rx-item-card', container);
        const items = [];
        for (const row of rows) {
            const nameAr = Dom.$('.rx-item-name-ar', row).value.trim();
            const nameEn = Dom.$('.rx-item-name-en', row).value.trim();
            const dosage = Dom.$('.rx-item-dosage', row).value.trim();
            const frequency = Dom.$('.rx-item-frequency', row).value.trim();
            const duration = Dom.$('.rx-item-duration', row).value.trim();
            const quantityRaw = Dom.$('.rx-item-quantity', row).value;
            const instructions = Dom.$('.rx-item-instructions', row).value.trim();
            const quantity = quantityRaw === '' ? NaN : Number(quantityRaw);

            if (!nameAr || !nameEn || !dosage || !frequency || !Number.isInteger(quantity) || quantity < 1) {
                return { error: t('patientDetail.errorRxItemRequired') };
            }

            items.push({
                medication_name_ar: nameAr,
                medication_name_en: nameEn,
                dosage,
                frequency,
                duration: duration || null,
                quantity,
                instructions: instructions || null
            });
        }
        return { items };
    }

    function validateRx() {
        const appointmentId = document.getElementById('rxAppointment').value;
        if (!appointmentId) return { error: t('patientDetail.errorRxAppointmentRequired') };
        const { items, error: itemsError } = collectRxItems();
        if (itemsError) return { error: itemsError };
        return { appointmentId, items };
    }

    function clearRxForm() {
        document.getElementById('rxValidUntil').value = '';
        document.getElementById('rxDiagnosis').value = '';
        document.getElementById('rxInstructions').value = '';
        resetRxItems();
    }

    function showRxResult(ok) {
        const icon = document.getElementById('rxFormResultIcon');
        icon.className = 'feedback-result-icon ' + (ok ? 'success' : 'error');
        icon.innerHTML = '<i class="fas ' + (ok ? 'fa-circle-check' : 'fa-triangle-exclamation') + '"></i>';
        document.getElementById('rxFormResultTitle').textContent = t(ok ? 'patientDetail.rxSavedTitle' : 'patientDetail.rxErrorTitle');
        document.getElementById('rxFormResultHint').textContent = t(ok ? 'patientDetail.rxSavedHint' : 'patientDetail.rxErrorHint');
        document.getElementById('rxFormResult').classList.remove('hidden');
    }

    async function submitRx() {
        const alertBox = document.getElementById('rxFormAlert');
        alertBox.className = 'alert';

        const { error: validationError, appointmentId, items } = validateRx();
        if (validationError) {
            alertBox.classList.add('error');
            alertBox.textContent = validationError;
            return;
        }

        const btn = document.getElementById('rxSubmitBtn');
        btn.classList.add('loading');
        btn.disabled = true;

        const body = {
            patient_id: currentPatientId,
            appointment_id: appointmentId,
            valid_until: document.getElementById('rxValidUntil').value || null,
            diagnosis: document.getElementById('rxDiagnosis').value.trim() || null,
            instructions: document.getElementById('rxInstructions').value.trim() || null,
            items
        };

        try {
            const res = await API.care.createPrescription(body);
            prescriptions = [res.data, ...prescriptions];
            renderPrescriptions(prescriptions);
            clearRxForm();
            showRxResult(true);
        } catch (err2) {
            console.error('PatientDetail: failed to save prescription', err2);
            showRxResult(false);
        }

        btn.classList.remove('loading');
        btn.disabled = false;
    }

    // ================= LOAD =================

    async function loadPatient(patientId) {
        try {
            const res = await API.care.patientDetail(patientId);
            const data = res?.data || {};
            notes = Array.isArray(data.notes) ? data.notes : [];
            appointments = Array.isArray(data.appointments) ? data.appointments : [];
            prescriptions = Array.isArray(data.prescriptions) ? data.prescriptions : [];
            currentPatientId = data.patient?.id || null;
            renderHeader(data.patient || {});
            renderAppointments(appointments);
            renderAppointmentOptions(appointments);
            renderRxAppointmentOptions(appointments);
            renderNotes(notes);
            renderPrescriptions(prescriptions);
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

        const state = await AuthGate.verifySession();
        if (state !== 'valid') return;

        const isDoctor = AuthGate.getVerifiedUser()?.role === 'doctor';

        if (!isDoctor) {
            document.getElementById('restrictedNotice').classList.remove('hidden');
            return;
        }

        document.getElementById('patientDetailContent').classList.remove('hidden');
        resetRxItems();
        loadPatient(patientId);

        document.getElementById('noteSubmitBtn').addEventListener('click', submitRecord);
        document.getElementById('noteFormResultCloseBtn').addEventListener('click', () => {
            document.getElementById('noteFormResult').classList.add('hidden');
        });

        document.getElementById('rxAddItemBtn').addEventListener('click', addRxItemRow);
        document.getElementById('rxSubmitBtn').addEventListener('click', submitRx);
        document.getElementById('rxFormResultCloseBtn').addEventListener('click', () => {
            document.getElementById('rxFormResult').classList.add('hidden');
        });
    }

    // Swaps a broken avatar <img> for the same plain-text initials fallback
    // already used when no profile_image_url exists at all (mirrors
    // my-patients.js). Invoked from a static onerror="PatientDetail.__avatarFallback(this)"
    // attribute; the initials travel only as an HTML-escaped data attribute.
    function avatarFallback(img) {
        img.replaceWith(document.createTextNode(img.dataset.fallbackInitials || '?'));
    }

    return { init, __avatarFallback: avatarFallback };

})();

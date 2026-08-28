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

function renderAppointmentOptions(list) {
        const select = document.getElementById('noteAppointment');
        const btn = document.getElementById('noteSubmitBtn');
        if (!select) return;

        if (!list.length) {
            select.innerHTML = '<option value="">' +
                escapeHtml(t('patientDetail.noAppointmentForRecord')) +
                '</option>';
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

    function appointmentLabel(appointment) {
        const status = t(STATUS_KEY[appointment.status] || appointment.status || '');
        const reason = appointment.reason_for_visit ? ' · ' + appointment.reason_for_visit : '';
        return fmtDate(appointment.scheduled_date) +
            (appointment.start_time ? ' · ' + fmtTimeRange(appointment.start_time, appointment.end_time) : '') +
            (status ? ' · ' + status : '') + reason;
    }

    function populatePrescriptionAppointments() {
        const select = document.getElementById('prescriptionAppointment');
        if (!select) return;
        select.innerHTML = '<option value="">' + escapeHtml(t('patientDetail.prescriptionSelectAppointment')) + '</option>' +
            appointments.map((appointment) =>
                '<option value="' + escapeHtml(appointment.id) + '">' + escapeHtml(appointmentLabel(appointment)) + '</option>'
            ).join('');
    }

    function prescriptionItemHtml(number) {
        return '<div class="prescription-item">' +
            '<div class="prescription-item-heading">' +
                '<span><i class="fas fa-pills"></i> ' + escapeHtml(t('patientDetail.prescriptionItem')) + ' ' + number + '</span>' +
                '<button type="button" class="btn btn-ghost btn-sm prescription-remove-item" aria-label="' + escapeHtml(t('patientDetail.prescriptionRemoveItem')) + '">' +
                    '<i class="fas fa-trash"></i> <span>' + escapeHtml(t('patientDetail.prescriptionRemoveItem')) + '</span>' +
                '</button>' +
            '</div>' +
            '<div class="form-row">' +
                '<div class="form-group"><label>' + escapeHtml(t('patientDetail.prescriptionMedicationEnglish')) + '</label><div class="input-wrapper"><i class="fas fa-capsules"></i><input class="rx-medication-en" type="text" required></div></div>' +
                '<div class="form-group"><label>' + escapeHtml(t('patientDetail.prescriptionMedicationArabic')) + '</label><div class="input-wrapper"><i class="fas fa-language"></i><input class="rx-medication-ar" type="text"></div></div>' +
            '</div>' +
            '<div class="form-row">' +
                '<div class="form-group"><label>' + escapeHtml(t('patientDetail.prescriptionDosage')) + '</label><div class="input-wrapper"><i class="fas fa-prescription-bottle"></i><input class="rx-dosage" type="text" required placeholder="e.g. 500 mg"></div></div>' +
                '<div class="form-group"><label>' + escapeHtml(t('patientDetail.prescriptionFrequency')) + '</label><div class="input-wrapper"><i class="fas fa-clock"></i><input class="rx-frequency" type="text" required placeholder="e.g. Twice daily"></div></div>' +
            '</div>' +
            '<div class="form-row">' +
                '<div class="form-group"><label>' + escapeHtml(t('patientDetail.prescriptionDuration')) + '</label><div class="input-wrapper"><i class="fas fa-calendar-days"></i><input class="rx-duration" type="text" placeholder="e.g. 7 days"></div></div>' +
                '<div class="form-group"><label>' + escapeHtml(t('patientDetail.prescriptionQuantity')) + '</label><div class="input-wrapper"><i class="fas fa-box"></i><input class="rx-quantity" type="number" min="1" step="1" required></div></div>' +
            '</div>' +
            '<div class="form-group"><label>' + escapeHtml(t('patientDetail.prescriptionItemInstructions')) + '</label><textarea class="feedback-textarea rx-instructions" style="min-height:54px;"></textarea></div>' +
        '</div>';
    }

    function renumberPrescriptionItems() {
        document.querySelectorAll('#prescriptionItems .prescription-item').forEach((item, index) => {
            const heading = item.querySelector('.prescription-item-heading > span');
            if (heading) heading.innerHTML = '<i class="fas fa-pills"></i> ' + escapeHtml(t('patientDetail.prescriptionItem')) + ' ' + (index + 1);
            const removeButton = item.querySelector('.prescription-remove-item');
            if (removeButton) removeButton.disabled = index === 0 && document.querySelectorAll('#prescriptionItems .prescription-item').length === 1;
        });
    }

    function addPrescriptionItem() {
        const items = document.getElementById('prescriptionItems');
        if (!items) return;
        items.insertAdjacentHTML('beforeend', prescriptionItemHtml(items.children.length + 1));
        renumberPrescriptionItems();
    }

    function resetPrescriptionForm() {
        const form = document.getElementById('prescriptionForm');
        if (form) form.reset();
        const items = document.getElementById('prescriptionItems');
        if (items) {
            items.innerHTML = '';
            addPrescriptionItem();
        }
    }

    function collectPrescriptionItems() {
        return Array.from(document.querySelectorAll('#prescriptionItems .prescription-item')).map((item) => ({
            medication_name_en: item.querySelector('.rx-medication-en').value.trim(),
            medication_name_ar: item.querySelector('.rx-medication-ar').value.trim() || null,
            dosage: item.querySelector('.rx-dosage').value.trim(),
            frequency: item.querySelector('.rx-frequency').value.trim(),
            duration: item.querySelector('.rx-duration').value.trim() || null,
            quantity: item.querySelector('.rx-quantity').value.trim(),
            instructions: item.querySelector('.rx-instructions').value.trim() || null
        }));
    }

    function showPrescriptionAlert(kind, message) {
        const alertBox = document.getElementById('prescriptionFormAlert');
        if (!alertBox) return;
        alertBox.className = 'alert ' + kind;
        alertBox.textContent = message;
    }

    async function submitPrescription(patientId) {
        const appointmentId = document.getElementById('prescriptionAppointment').value;
        const items = collectPrescriptionItems();
        const itemIsIncomplete = items.some((item) => !item.medication_name_en || !item.dosage || !item.frequency || !item.quantity);
        if (!appointmentId || itemIsIncomplete) {
            showPrescriptionAlert('error', t('patientDetail.prescriptionValidation'));
            return;
        }

        const submitButton = document.getElementById('prescriptionSubmitBtn');
        submitButton.classList.add('loading');
        document.getElementById('prescriptionFormAlert').className = 'alert';

        try {
            const response = await API.care.createPrescription({
                patient_id: patientId,
                appointment_id: appointmentId,
                valid_until: document.getElementById('prescriptionValidUntil').value || null,
                diagnosis: document.getElementById('prescriptionDiagnosis').value.trim() || null,
                instructions: document.getElementById('prescriptionInstructions').value.trim() || null,
                doctor_notes: document.getElementById('prescriptionDoctorNotes').value.trim() || null,
                items
            });
            const prescription = response?.data;
            if (prescription) {
                prescriptions = [prescription, ...prescriptions];
                renderPrescriptions(prescriptions);
            }
            resetPrescriptionForm();

            const safety = prescription?.safety_check;
            if (safety?.status === 'warning') {
                showPrescriptionAlert('error', t('patientDetail.prescriptionSafetyWarning'));
            } else if (safety?.status === 'unavailable') {
                showPrescriptionAlert('error', t('patientDetail.prescriptionSafetyUnavailable'));
            } else {
                showPrescriptionAlert('success', t('patientDetail.prescriptionCreated'));
            }
        } catch (err) {
            console.error('PatientDetail: failed to create prescription', err);
            showPrescriptionAlert('error', err?.message || t('patientDetail.noteErrorHint'));
        } finally {
            submitButton.classList.remove('loading');
        }
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

async function loadPatient(patientId) {
        try {
            const res = await API.care.patientDetail(patientId);
            const data = res?.data || {};
            notes = Array.isArray(data.notes) ? data.notes : [];
            appointments = Array.isArray(data.appointments) ? data.appointments : [];
            prescriptions = Array.isArray(data.prescriptions) ? data.prescriptions : [];
            renderHeader(data.patient || {});
            renderAppointments(appointments);
            renderAppointmentOptions(appointments);
            renderNotes(notes);
            populatePrescriptionAppointments();
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

        loadPatient(patientId);

        document.getElementById('noteSubmitBtn').addEventListener('click', submitRecord);
        document.getElementById('noteFormResultCloseBtn').addEventListener('click', () => {
            document.getElementById('noteFormResult').classList.add('hidden');
        });
        document.getElementById('addPrescriptionItemBtn').addEventListener('click', addPrescriptionItem);

        document.getElementById('prescriptionItems').addEventListener('click', (event) => {
            const removeButton = event.target.closest('.prescription-remove-item');
            if (!removeButton || removeButton.disabled) return;

            removeButton.closest('.prescription-item').remove();
            renumberPrescriptionItems();
        });

        document.getElementById('prescriptionForm').addEventListener('submit', (event) => {
            event.preventDefault();
            submitPrescription(patientId);
        });

        resetPrescriptionForm();
    }

function avatarFallback(img) {
        img.replaceWith(document.createTextNode(img.dataset.fallbackInitials || '?'));
    }
    return { init, __avatarFallback: avatarFallback };

})();

/**
 * MedOrbit v2 - My Medical Records
 *
 * Fetches via GET /patients/me/records (backend/src/routes/patient.routes.js)
 * — a single ownership-scoped timeline that interleaves the patient's own
 * appointments, medical records (diagnoses) and prescriptions. Never call
 * the generic /api/medical-records or /api/prescriptions/:id from here —
 * those have no ownership filtering at all.
 */
const MyRecords = (() => {

    let entries = [];
    let selectedId = null;

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function label(ar, en) {
        return isAr() ? ar : en;
    }

    function escapeHtml(value) {
        if (value == null) return '';
        return String(value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function show(el, visible) {
        el?.classList.toggle('hidden', !visible);
    }

    function fmtDate(value) {
        if (!value) return label('غير محدد', 'Not set');
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return String(value);
        return d.toLocaleDateString(isAr() ? 'ar' : 'en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    function entryDate(item) {
        return item.entry_date || item.scheduled_date || item.prescription_date || item.created_at || '';
    }

    const ENTRY_LABELS = {
        appointment: ['موعد', 'Appointment'],
        record: ['سجل طبي', 'Medical record'],
        prescription: ['وصفة طبية', 'Prescription']
    };

    const ENTRY_ICONS = {
        appointment: 'fa-calendar-check',
        record: 'fa-stethoscope',
        prescription: 'fa-prescription-bottle-medical'
    };

    const RECORD_TYPE_LABELS = {
        consultation: ['استشارة', 'Consultation'],
        lab_result: ['نتيجة فحص', 'Lab result'],
        diagnosis: ['تشخيص', 'Diagnosis'],
        imaging: ['أشعة', 'Imaging'],
        procedure: ['إجراء', 'Procedure']
    };

    const RECORD_TYPE_ICONS = {
        consultation: 'fa-user-doctor',
        lab_result: 'fa-flask',
        diagnosis: 'fa-stethoscope',
        imaging: 'fa-x-ray',
        procedure: 'fa-briefcase-medical'
    };

    function entryLabel(item) {
        const pair = ENTRY_LABELS[item.entry_type];
        return pair ? label(pair[0], pair[1]) : label('سجل', 'Entry');
    }

    function recordSubtype(item) {
        return String(item.record_type || '').toLowerCase();
    }

    function entryIcon(item) {
        if (item.entry_type === 'record') {
            return RECORD_TYPE_ICONS[recordSubtype(item)] || ENTRY_ICONS.record;
        }
        return ENTRY_ICONS[item.entry_type] || 'fa-file-waveform';
    }

    function entryBadge(item) {
        if (item.entry_type === 'record') {
            const pair = RECORD_TYPE_LABELS[recordSubtype(item)];
            return pair ? label(pair[0], pair[1]) : entryLabel(item);
        }
        if (item.status) return String(item.status);
        return entryLabel(item);
    }

    function doctorName(item) {
        // Backend joins bilingual name columns (doctor_first_name_ar/en,
        // same suffix convention as everything else in this file) for
        // appointments/records. Prescriptions don't carry a doctor join
        // in this timeline, so this falls back to '' for those.
        const first = isAr() ? item.doctor_first_name_ar : item.doctor_first_name_en;
        const last = isAr() ? item.doctor_last_name_ar : item.doctor_last_name_en;
        return (
            item.doctor_name ||
            [first, last].filter(Boolean).join(' ') ||
            [item.doctor_first_name_en, item.doctor_last_name_en].filter(Boolean).join(' ') ||
            ''
        );
    }

    function medicationName(item) {
        const meds = Array.isArray(item.items) ? item.items : [];
        const first = meds[0] || {};
        return (
            (isAr() ? first.medication_name_ar : first.medication_name_en) ||
            first.medication_name_en ||
            first.medication_name_ar ||
            ''
        );
    }

    function entryTitle(item) {
        if (item.entry_type === 'appointment') {
            const specialty = isAr() ? item.specialty_ar : item.specialty_en;
            return item.reason_for_visit || specialty || label('موعد طبي', 'Medical appointment');
        }
        if (item.entry_type === 'prescription') {
            return medicationName(item) || item.diagnosis || item.prescription_number || label('وصفة طبية', 'Prescription');
        }
        return item.diagnosis || item.chief_complaint || entryBadge(item);
    }

    function normalizeEntry(raw) {
        return { ...raw };
    }

    function normalizeTimeline(payload) {
        const source =
            payload?.data?.timeline ||
            payload?.timeline ||
            [];
        return (Array.isArray(source) ? source : [])
            .map(normalizeEntry)
            .filter((e) => e.id && e.entry_type);
    }

    async function fetchRecords() {
        const res = await API.care.myRecordsTimeline();
        return normalizeTimeline(res);
    }

    function setFiltersEnabled(enabled) {
        document.getElementById('recordsFilters')?.classList.toggle('ready', enabled);
        const search = document.getElementById('recordSearchInput');
        const type = document.getElementById('recordTypeFilter');
        const date = document.getElementById('recordDateFilter');
        if (search) search.disabled = !enabled;
        if (type) type.disabled = !enabled;
        if (date) date.disabled = !enabled;
    }

    function setState(state, message) {
        show(document.getElementById('recordsLoading'), state === 'loading');
        show(document.getElementById('recordsError'), state === 'error');
        show(document.getElementById('recordsData'), state === 'data');
        show(document.getElementById('recordsEmpty'), state === 'empty');
        setFiltersEnabled(state === 'data' || state === 'empty');

        if (message) {
            const el = document.getElementById('recordsErrorText');
            if (el) el.textContent = message;
        }
    }

    function matchesDateFilter(item, filter) {
        if (filter === 'any') return true;
        const d = new Date(entryDate(item));
        if (Number.isNaN(d.getTime())) return false;
        const days = Number(filter);
        return Date.now() - d.getTime() <= days * 24 * 60 * 60 * 1000;
    }

    function filteredEntries() {
        const query = (document.getElementById('recordSearchInput')?.value || '').trim().toLowerCase();
        const type = document.getElementById('recordTypeFilter')?.value || 'all';
        const dateFilter = document.getElementById('recordDateFilter')?.value || 'any';

        return entries.filter((item) => {
            const haystack = [
                entryTitle(item),
                item.diagnosis,
                item.chief_complaint,
                item.reason_for_visit,
                item.notes,
                item.treatment_plan,
                doctorName(item),
                entryLabel(item),
                entryBadge(item)
            ].filter(Boolean).join(' ').toLowerCase();

            const matchesQuery = !query || haystack.includes(query);
            const matchesType = type === 'all' || item.entry_type === type;
            return matchesQuery && matchesType && matchesDateFilter(item, dateFilter);
        });
    }

    function renderCard(item) {
        const active = item.id === selectedId ? ' active' : '';
        const badge = entryBadge(item);
        return (
            '<button type="button" class="records-real-card' + active + '" data-id="' + escapeHtml(item.id) + '">' +
                '<span class="records-real-icon"><i class="fas ' + entryIcon(item) + '"></i></span>' +
                '<span class="records-real-card-main">' +
                    '<span class="records-real-title">' + escapeHtml(entryTitle(item)) + '</span>' +
                    '<span class="records-real-meta">' +
                        '<span class="records-real-badge ' + escapeHtml(item.entry_type) + '">' + escapeHtml(badge) + '</span>' +
                        (doctorName(item) ? '<span>' + escapeHtml(doctorName(item)) + '</span>' : '') +
                    '</span>' +
                    '<span class="records-real-subtitle">' + escapeHtml(fmtDate(entryDate(item))) + '</span>' +
                '</span>' +
            '</button>'
        );
    }

    function field(labelText, value) {
        return (
            '<div class="records-detail-field">' +
                '<div class="label">' + escapeHtml(labelText) + '</div>' +
                '<div class="value">' + escapeHtml(value || label('غير محدد', 'Not set')) + '</div>' +
            '</div>'
        );
    }

    function renderAttachments(item) {
        const files = Array.isArray(item.attachments) ? item.attachments : [];
        if (!files.length) return '';
        return (
            '<div class="records-detail-section">' +
                '<h3><i class="fas fa-paperclip"></i>' + escapeHtml(label('المرفقات', 'Attachments')) + '</h3>' +
                '<div class="records-medication-list">' +
                    files.map((f) => (
                        '<div class="records-medication-item">' +
                            '<strong>' + escapeHtml(f.file_name || f.name || label('ملف', 'File')) + '</strong>' +
                            (f.file_type ? '<span>' + escapeHtml(f.file_type) + '</span>' : '') +
                        '</div>'
                    )).join('') +
                '</div>' +
            '</div>'
        );
    }

    function renderMedicationItems(items) {
        if (!Array.isArray(items) || !items.length) {
            return '<div class="records-detail-field"><div class="value">' + escapeHtml(label('لا توجد أدوية مفصلة', 'No medication items listed')) + '</div></div>';
        }
        return (
            '<div class="records-medication-list">' +
                items.map((med) => {
                    const name =
                        (isAr() ? med.medication_name_ar : med.medication_name_en) ||
                        med.medication_name_en || med.medication_name_ar || label('دواء', 'Medication');
                    const meta = [med.dosage, med.frequency, med.duration, med.quantity].filter(Boolean).join(' - ');
                    return (
                        '<div class="records-medication-item">' +
                            '<strong>' + escapeHtml(name) + '</strong>' +
                            '<span>' + escapeHtml(meta || label('الجرعة غير محددة', 'Dosage not specified')) + '</span>' +
                            (med.instructions ? '<span>' + escapeHtml(med.instructions) + '</span>' : '') +
                        '</div>'
                    );
                }).join('') +
            '</div>'
        );
    }

    function renderDetailHeader(item) {
        return (
            '<div class="records-detail-header">' +
                '<div class="records-real-icon"><i class="fas ' + entryIcon(item) + '"></i></div>' +
                '<div>' +
                    '<h2 class="records-detail-title">' + escapeHtml(entryTitle(item)) + '</h2>' +
                    '<div class="records-real-meta">' +
                        '<span class="records-real-badge ' + escapeHtml(item.entry_type) + '">' + escapeHtml(entryBadge(item)) + '</span>' +
                        '<span>' + escapeHtml(fmtDate(entryDate(item))) + '</span>' +
                    '</div>' +
                '</div>' +
            '</div>'
        );
    }

    function renderAppointmentDetail(item) {
        const specialty = isAr() ? item.specialty_ar : item.specialty_en;
        return (
            renderDetailHeader(item) +
            '<div class="records-detail-section">' +
                '<h3><i class="fas fa-circle-info"></i>' + escapeHtml(label('تفاصيل الموعد', 'Appointment details')) + '</h3>' +
                '<div class="records-detail-grid">' +
                    field(label('التاريخ', 'Date'), fmtDate(item.scheduled_date)) +
                    field(label('الوقت', 'Time'), item.start_time) +
                    field(label('الطبيب', 'Doctor'), doctorName(item)) +
                    field(label('التخصص', 'Specialty'), specialty) +
                    field(label('نوع الموعد', 'Type'), item.appointment_type) +
                    field(label('سبب الزيارة', 'Reason for visit'), item.reason_for_visit) +
                '</div>' +
            '</div>'
        );
    }

    function renderRecordDetail(item) {
        return (
            renderDetailHeader(item) +
            '<div class="records-detail-section">' +
                '<h3><i class="fas fa-circle-info"></i>' + escapeHtml(label('تفاصيل السجل', 'Record details')) + '</h3>' +
                '<div class="records-detail-grid">' +
                    field(label('التاريخ', 'Date'), fmtDate(entryDate(item))) +
                    field(label('الطبيب', 'Doctor'), doctorName(item)) +
                    field(label('الشكوى الرئيسية', 'Chief complaint'), item.chief_complaint) +
                    field(label('التشخيص', 'Diagnosis'), item.diagnosis) +
                '</div>' +
            '</div>' +
            (item.treatment_plan
                ? '<div class="records-detail-section">' +
                      '<h3><i class="fas fa-notes-medical"></i>' + escapeHtml(label('العلاج', 'Treatment')) + '</h3>' +
                      '<div class="records-detail-grid">' + field(label('العلاج', 'Treatment'), item.treatment_plan) + '</div>' +
                  '</div>'
                : '') +
            renderAttachments(item)
        );
    }

    function renderPrescriptionDetail(item) {
        return (
            renderDetailHeader(item) +
            '<div class="records-detail-section">' +
                '<h3><i class="fas fa-circle-info"></i>' + escapeHtml(label('تفاصيل الوصفة', 'Prescription details')) + '</h3>' +
                '<div class="records-detail-grid">' +
                    field(label('تاريخ الوصفة', 'Prescription date'), fmtDate(item.prescription_date)) +
                    field(label('صالحة حتى', 'Valid until'), fmtDate(item.valid_until)) +
                    field(label('التشخيص', 'Diagnosis'), item.diagnosis) +
                    field(label('التعليمات', 'Instructions'), item.instructions) +
                '</div>' +
            '</div>' +
            '<div class="records-detail-section">' +
                '<h3><i class="fas fa-pills"></i>' + escapeHtml(label('الأدوية', 'Medications')) + '</h3>' +
                renderMedicationItems(item.items) +
            '</div>'
        );
    }

    function renderDetail(item) {
        const detail = document.getElementById('recordDetail');
        if (!detail) return;

        if (item.entry_type === 'appointment') {
            detail.innerHTML = renderAppointmentDetail(item);
        } else if (item.entry_type === 'prescription') {
            detail.innerHTML = renderPrescriptionDetail(item);
        } else {
            detail.innerHTML = renderRecordDetail(item);
        }
    }

    function selectRecord(id) {
        const item = entries.find((r) => String(r.id) === String(id)) || entries[0];
        selectedId = item?.id || null;
        render();
    }

    function render() {
        const list = filteredEntries();
        const listEl = document.getElementById('recordsList');

        if (!list.length) {
            setState('empty');
            return;
        }

        if (!selectedId || !list.some((r) => r.id === selectedId)) selectedId = list[0].id;

        setState('data');
        listEl.innerHTML = list.map(renderCard).join('');
        listEl.querySelectorAll('[data-id]').forEach((btn) => {
            btn.addEventListener('click', () => selectRecord(btn.dataset.id));
        });

        const selected = list.find((r) => String(r.id) === String(selectedId)) || list[0];
        renderDetail(selected);
    }

    async function load() {
        setState('loading');
        try {
            entries = await fetchRecords();
            selectedId = entries[0]?.id || null;
            render();
        } catch (err) {
            console.error('MyRecords: failed to load patient history', err);
            setState('error', label('تعذر تحميل السجلات. حاول مرة أخرى.', 'Could not load records. Please try again.'));
        }
    }

    function init() {
        if (!API.requireAuth()) return;

        document.getElementById('recordSearchInput')?.addEventListener('input', render);
        document.getElementById('recordTypeFilter')?.addEventListener('change', render);
        document.getElementById('recordDateFilter')?.addEventListener('change', render);
        document.getElementById('recordsRetryBtn')?.addEventListener('click', load);

        load();
    }

    return { init, fetchRecords };

})();

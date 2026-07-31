/**
 * MedOrbit v2 - My Medical Records
 *
 * Fetches via GET /patients/me/medical-records (backend/src/routes/
 * patient.routes.js) — ownership-scoped, unlike the generic
 * /api/medical-records/:id, which has no ownership filtering at all and
 * must never be called from here.
 */
const MyRecords = (() => {

    let records = [];
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

    function dateValue(item) {
        return item.record_date || item.visit_date || item.created_at || item.updated_at || '';
    }

    const TYPE_LABELS = {
        consultation: ['استشارة', 'Consultation'],
        lab_result: ['نتيجة فحص', 'Lab result'],
        diagnosis: ['تشخيص', 'Diagnosis'],
        imaging: ['أشعة', 'Imaging'],
        procedure: ['إجراء', 'Procedure']
    };

    const TYPE_ICONS = {
        consultation: 'fa-user-doctor',
        lab_result: 'fa-flask',
        diagnosis: 'fa-stethoscope',
        imaging: 'fa-x-ray',
        procedure: 'fa-briefcase-medical'
    };

    function recordType(item) {
        return String(item.record_type || item.type || '').toLowerCase();
    }

    function typeLabel(item) {
        const pair = TYPE_LABELS[recordType(item)];
        return pair ? label(pair[0], pair[1]) : (recordType(item) || label('سجل', 'Record'));
    }

    function typeIcon(item) {
        return TYPE_ICONS[recordType(item)] || 'fa-file-waveform';
    }

    function recordTitle(item) {
        return (
            item.title ||
            item.diagnosis ||
            item.chief_complaint ||
            typeLabel(item)
        );
    }

    function doctorName(item) {
        // Backend joins bilingual name columns (doctor_first_name_ar/en,
        // same suffix convention as everything else in this file), so pick
        // by current language the same way typeLabel()/medicationName()
        // already do — not a fixed field name.
        const first = isAr() ? item.doctor_first_name_ar : item.doctor_first_name_en;
        const last = isAr() ? item.doctor_last_name_ar : item.doctor_last_name_en;
        return (
            item.doctor_name ||
            [first, last].filter(Boolean).join(' ') ||
            [item.doctor_first_name_en, item.doctor_last_name_en].filter(Boolean).join(' ') ||
            ''
        );
    }

    function normalizeRecord(raw) {
        const record = raw?.record || raw || {};
        return {
            ...record,
            id: record.id || raw?.id || record.record_number
        };
    }

    function normalizeList(payload) {
        const source =
            payload?.records ||
            payload?.medical_records ||
            payload?.data?.records ||
            payload?.data ||
            payload ||
            [];
        return (Array.isArray(source) ? source : []).map(normalizeRecord).filter((r) => r.id);
    }

    async function fetchRecords() {
        const res = await API.care.myMedicalRecords();
        return normalizeList(res);
    }

    function setFiltersEnabled(enabled) {
        document.getElementById('recordsFilters')?.classList.toggle('ready', enabled);
        const search = document.getElementById('recordSearchInput');
        const type = document.getElementById('recordTypeFilter');
        const date = document.getElementById('recordDateFilter');
        if (search) search.disabled = !enabled;
        if (type) type.disabled = !enabled;
        if (date) date.disabled = !enabled;
        show(document.getElementById('recordsLockedTag'), !enabled);
    }

    function setState(state, message) {
        show(document.getElementById('recordsLoading'), state === 'loading');
        show(document.getElementById('recordsError'), state === 'error');
        show(document.getElementById('recordsData'), state === 'data');
        show(document.getElementById('recordsPreview'), state === 'empty');
        show(document.getElementById('recordsEmpty'), state === 'empty');
        setFiltersEnabled(state === 'data');

        if (message) {
            const el = document.getElementById('recordsErrorText');
            if (el) el.textContent = message;
        }
    }

    function matchesDateFilter(item, filter) {
        if (filter === 'any') return true;
        const d = new Date(dateValue(item));
        if (Number.isNaN(d.getTime())) return false;
        const days = Number(filter);
        return Date.now() - d.getTime() <= days * 24 * 60 * 60 * 1000;
    }

    function filteredRecords() {
        const query = (document.getElementById('recordSearchInput')?.value || '').trim().toLowerCase();
        const type = document.getElementById('recordTypeFilter')?.value || 'all';
        const dateFilter = document.getElementById('recordDateFilter')?.value || 'any';

        return records.filter((item) => {
            const haystack = [
                recordTitle(item),
                item.diagnosis,
                item.chief_complaint,
                item.notes,
                item.treatment_plan,
                doctorName(item),
                typeLabel(item)
            ].filter(Boolean).join(' ').toLowerCase();

            const matchesQuery = !query || haystack.includes(query);
            const matchesType = type === 'all' || recordType(item) === type;
            return matchesQuery && matchesType && matchesDateFilter(item, dateFilter);
        });
    }

    function renderCard(item) {
        const active = item.id === selectedId ? ' active' : '';
        const type = recordType(item) || 'record';
        return (
            '<button type="button" class="records-real-card' + active + '" data-id="' + escapeHtml(item.id) + '">' +
                '<span class="records-real-icon"><i class="fas ' + typeIcon(item) + '"></i></span>' +
                '<span class="records-real-card-main">' +
                    '<span class="records-real-title">' + escapeHtml(recordTitle(item)) + '</span>' +
                    '<span class="records-real-meta">' +
                        '<span class="records-real-badge ' + escapeHtml(type) + '">' + escapeHtml(typeLabel(item)) + '</span>' +
                        (doctorName(item) ? '<span>' + escapeHtml(doctorName(item)) + '</span>' : '') +
                    '</span>' +
                    '<span class="records-real-subtitle">' + escapeHtml(fmtDate(dateValue(item))) + '</span>' +
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

    function renderDetail(item) {
        const detail = document.getElementById('recordDetail');
        if (!detail) return;
        const type = recordType(item) || 'record';

        detail.innerHTML =
            '<div class="records-detail-header">' +
                '<div class="records-real-icon"><i class="fas ' + typeIcon(item) + '"></i></div>' +
                '<div>' +
                    '<h2 class="records-detail-title">' + escapeHtml(recordTitle(item)) + '</h2>' +
                    '<div class="records-real-meta">' +
                        '<span class="records-real-badge ' + escapeHtml(type) + '">' + escapeHtml(typeLabel(item)) + '</span>' +
                        '<span>' + escapeHtml(fmtDate(dateValue(item))) + '</span>' +
                    '</div>' +
                '</div>' +
            '</div>' +
            '<div class="records-detail-section">' +
                '<h3><i class="fas fa-circle-info"></i>' + escapeHtml(label('تفاصيل السجل', 'Record Details')) + '</h3>' +
                '<div class="records-detail-grid">' +
                    field(label('التاريخ', 'Date'), fmtDate(dateValue(item))) +
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
            (item.notes
                ? '<div class="records-detail-section">' +
                      '<h3><i class="fas fa-pen-to-square"></i>' + escapeHtml(label('ملاحظات', 'Notes')) + '</h3>' +
                      '<div class="records-detail-grid">' + field(label('ملاحظات', 'Notes'), item.notes) + '</div>' +
                  '</div>'
                : '') +
            renderAttachments(item);
    }

    function selectRecord(id) {
        const item = records.find((r) => String(r.id) === String(id)) || records[0];
        selectedId = item?.id || null;
        render();
    }

    function render() {
        const list = filteredRecords();
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
            const result = await fetchRecords();
            if (result?.blocked) {
                records = [];
                setState('empty');
                const timeline = document.querySelector('.records-timeline');
                if (timeline && typeof Motion !== 'undefined') {
                    Motion.staggerIn(timeline, '.records-timeline-item');
                }
                return;
            }

            records = normalizeList(result);
            selectedId = records[0]?.id || null;
            render();
        } catch (err) {
            console.error('MyRecords: failed to load medical records', err);
            setState('error', err?.message || label('تعذر تحميل السجلات', 'Could not load records'));
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

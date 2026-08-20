/**
 * MedOrbit v2 - My Prescriptions
 * Real list/detail UI is ready. Data fetching is intentionally blocked until
 * Omar adds a safe caller-scoped endpoint.
 */
const MyPrescriptions = (() => {

    let prescriptions = [];
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
        return item.prescription_date || item.created_at || item.updated_at || '';
    }

    function medicationName(item) {
        const meds = Array.isArray(item.items) ? item.items : [];
        const first = meds[0] || {};
        return (
            (isAr() ? first.medication_name_ar : first.medication_name_en) ||
            first.medication_name_en ||
            first.medication_name_ar ||
            item.diagnosis ||
            item.prescription_number ||
            label('وصفة طبية', 'Prescription')
        );
    }

    function normalizePrescription(raw) {
        const prescription = raw?.prescription || raw || {};
        return {
            ...prescription,
            id: prescription.id || raw?.id || prescription.prescription_number,
            items: raw?.items || prescription.items || []
        };
    }

    function normalizeList(payload) {
        const source =
            payload?.prescriptions ||
            payload?.data?.prescriptions ||
            payload?.data ||
            payload ||
            [];
        return (Array.isArray(source) ? source : []).map(normalizePrescription).filter((p) => p.id);
    }

    // GET /patients/me/prescriptions — ownership-scoped (backend/src/routes/
    // patient.routes.js), unlike the generic /api/prescriptions/:id, which
    // has no ownership filtering at all and must never be called from here.
    async function fetchPrescriptions() {
        const res = await API.care.myPrescriptions();
        return normalizeList(res);
    }

    function setFiltersEnabled(enabled) {
        document.getElementById('prescriptionsFilters')?.classList.toggle('ready', enabled);
        document.getElementById('prescriptionSearchInput').disabled = !enabled;
        document.getElementById('prescriptionStatusFilter').disabled = !enabled;
        document.getElementById('prescriptionDateFilter').disabled = !enabled;
        show(document.getElementById('prescriptionsLockedTag'), !enabled);
    }

    function setState(state, message) {
        show(document.getElementById('prescriptionsLoading'), state === 'loading');
        show(document.getElementById('prescriptionsError'), state === 'error');
        show(document.getElementById('prescriptionsData'), state === 'data');
        show(document.getElementById('prescriptionsPreview'), false);
        show(document.getElementById('prescriptionsEmpty'), state === 'empty');
        show(document.getElementById('prescriptionsFilters'), state === 'data');
        setFiltersEnabled(state === 'data');

        if (message) {
            document.getElementById('prescriptionsErrorText').textContent = message;
        }
    }

    function matchesDateFilter(item, filter) {
        if (filter === 'any') return true;
        const d = new Date(dateValue(item));
        if (Number.isNaN(d.getTime())) return false;
        const days = Number(filter);
        return Date.now() - d.getTime() <= days * 24 * 60 * 60 * 1000;
    }

    function filteredPrescriptions() {
        const query = document.getElementById('prescriptionSearchInput').value.trim().toLowerCase();
        const status = document.getElementById('prescriptionStatusFilter').value;
        const dateFilter = document.getElementById('prescriptionDateFilter').value;

        return prescriptions.filter((item) => {
            const haystack = [
                medicationName(item),
                item.prescription_number,
                item.diagnosis,
                item.instructions,
                ...(Array.isArray(item.items) ? item.items.map((m) => [m.medication_name_ar, m.medication_name_en].join(' ')) : [])
            ].join(' ').toLowerCase();

            const matchesQuery = !query || haystack.includes(query);
            const matchesStatus = status === 'all' || String(item.status || '').toLowerCase() === status;
            return matchesQuery && matchesStatus && matchesDateFilter(item, dateFilter);
        });
    }

    function renderCard(item) {
        const active = item.id === selectedId ? ' active' : '';
        const status = String(item.status || label('غير محدد', 'unknown')).toLowerCase();
        return (
            '<button type="button" class="records-real-card' + active + '" data-id="' + escapeHtml(item.id) + '">' +
                '<span class="records-real-icon"><i class="fas fa-prescription-bottle-medical"></i></span>' +
                '<span class="records-real-card-main">' +
                    '<span class="records-real-title">' + escapeHtml(medicationName(item)) + '</span>' +
                    '<span class="records-real-meta">' +
                        '<span>' + escapeHtml(item.prescription_number || label('بدون رقم', 'No number')) + '</span>' +
                        '<span class="records-real-badge ' + escapeHtml(status) + '">' + escapeHtml(status) + '</span>' +
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

    function renderMedicationItems(items) {
        if (!Array.isArray(items) || !items.length) {
            return '<div class="records-detail-field"><div class="value">' + escapeHtml(label('لا توجد أدوية مفصلة', 'No medication items listed')) + '</div></div>';
        }

        return (
            '<div class="records-medication-list">' +
                items.map((item) => {
                    const name =
                        (isAr() ? item.medication_name_ar : item.medication_name_en) ||
                        item.medication_name_en ||
                        item.medication_name_ar ||
                        label('دواء', 'Medication');
                    const meta = [item.dosage, item.frequency, item.duration, item.quantity].filter(Boolean).join(' - ');
                    return (
                        '<div class="records-medication-item">' +
                            '<strong>' + escapeHtml(name) + '</strong>' +
                            '<span>' + escapeHtml(meta || label('الجرعة غير محددة', 'Dosage not specified')) + '</span>' +
                            (item.instructions ? '<span>' + escapeHtml(item.instructions) + '</span>' : '') +
                        '</div>'
                    );
                }).join('') +
            '</div>'
        );
    }

    function renderDetail(item) {
        const detail = document.getElementById('prescriptionDetail');
        const status = String(item.status || label('غير محدد', 'unknown')).toLowerCase();
        detail.innerHTML =
            '<div class="records-detail-header">' +
                '<div class="records-real-icon"><i class="fas fa-prescription-bottle-medical"></i></div>' +
                '<div>' +
                    '<h2 class="records-detail-title">' + escapeHtml(medicationName(item)) + '</h2>' +
                    '<div class="records-real-meta">' +
                        '<span>' + escapeHtml(item.prescription_number || label('بدون رقم', 'No number')) + '</span>' +
                        '<span class="records-real-badge ' + escapeHtml(status) + '">' + escapeHtml(status) + '</span>' +
                    '</div>' +
                '</div>' +
            '</div>' +
            '<div class="records-detail-section">' +
                '<h3><i class="fas fa-circle-info"></i>' + escapeHtml(label('تفاصيل الوصفة', 'Prescription Details')) + '</h3>' +
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
            '</div>' +
            (item.doctor_notes ? '<div class="records-detail-section">' + field(label('ملاحظات الطبيب', 'Doctor notes'), item.doctor_notes) + '</div>' : '');
    }

    function selectPrescription(id) {
        selectedId = id;
        const item = prescriptions.find((p) => String(p.id) === String(id)) || prescriptions[0];
        selectedId = item?.id || null;
        render();
    }

    function render() {
        const list = filteredPrescriptions();
        const listEl = document.getElementById('prescriptionsList');

        if (!list.length) {
            setState('empty');
            return;
        }

        if (!selectedId || !list.some((p) => p.id === selectedId)) selectedId = list[0].id;

        setState('data');
        listEl.innerHTML = list.map(renderCard).join('');
        listEl.querySelectorAll('[data-id]').forEach((btn) => {
            btn.addEventListener('click', () => selectPrescription(btn.dataset.id));
        });

        const selected = list.find((p) => String(p.id) === String(selectedId)) || list[0];
        renderDetail(selected);
    }

    async function load() {
        setState('loading');
        try {
            const result = await fetchPrescriptions();
            if (result?.blocked) {
                prescriptions = [];
                setState('empty');
                return;
            }

            prescriptions = normalizeList(result);
            selectedId = prescriptions[0]?.id || null;
            render();
        } catch (err) {
            console.error('MyPrescriptions: failed to load prescriptions', err);
            setState('error', label('تعذر تحميل الوصفات. حاول مرة أخرى.', 'Could not load prescriptions. Please try again.'));
        }
    }

    function init() {
        if (!API.requireAuth()) return;

        document.getElementById('prescriptionSearchInput')?.addEventListener('input', render);
        document.getElementById('prescriptionStatusFilter')?.addEventListener('change', render);
        document.getElementById('prescriptionDateFilter')?.addEventListener('change', render);
        document.getElementById('prescriptionsRetryBtn')?.addEventListener('click', load);

        load();
    }

    return { init, fetchPrescriptions };

})();

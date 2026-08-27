/**
 * MedOrbit v2 - My Prescriptions
 * Fetches via GET /patients/me/prescriptions (backend/src/routes/
 * patient.routes.js), an ownership-scoped call that returns the patient's
 * prescription list and medication items in one request. The backend excludes
 * clinician-private doctor_notes before this page receives the data.
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
        // Patient-facing UI must never surface the doctor's internal notes;
        // drop it here so no downstream rendering code can reuse it.
        const { doctor_notes, ...rest } = raw || {};
        return { ...rest, items: Array.isArray(raw?.items) ? raw.items : [] };
    }

    function normalizeList(payload) {
        const source = Array.isArray(payload?.data) ? payload.data : [];
        return source.map(normalizePrescription).filter((p) => p.id);
    }

    // GET /patients/me/prescriptions — ownership-scoped (backend/src/routes/
    // patient.routes.js) and returns the patient's full list in one call.
    // The generic /api/prescriptions/:id is ownership-scoped too, but it's
    // single-record and would need one request per prescription here.
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

    // Swaps the shared empty-state container's copy between "no prescriptions
    // at all" (dataset-empty) and "no matches for the current filters"
    // (filtered-empty), so the two cases are never presented the same way.
    function setEmptyStateContent(isFiltered) {
        const container = document.getElementById('prescriptionsEmpty');
        if (!container) return;
        const titleEl = container.querySelector('h2');
        const hintEl = container.querySelector('p');
        const linkEl = container.querySelector('a');

        if (isFiltered) {
            if (titleEl) {
                titleEl.removeAttribute('data-i18n');
                titleEl.textContent = label('لا توجد نتائج مطابقة', 'No matching prescriptions');
            }
            if (hintEl) {
                hintEl.removeAttribute('data-i18n');
                hintEl.textContent = label('جرّب تغيير كلمة البحث أو الفلاتر.', 'Try changing your search or filters.');
            }
            show(linkEl, false);
        } else {
            const titleKey = 'prescriptions.emptyTitle';
            const hintKey = 'prescriptions.emptyHint';
            if (titleEl) {
                titleEl.setAttribute('data-i18n', titleKey);
                titleEl.textContent = (typeof I18n !== 'undefined' ? I18n.t(titleKey) : null)
                    || label('لا توجد وصفات طبية لعرضها', 'No prescriptions to show');
            }
            if (hintEl) {
                hintEl.setAttribute('data-i18n', hintKey);
                hintEl.textContent = (typeof I18n !== 'undefined' ? I18n.t(hintKey) : null)
                    || label('ستظهر هنا الوصفات الطبية التي تتم مشاركتها مع حسابك.', 'Prescriptions shared with your account will appear here.');
            }
            show(linkEl, true);
        }
    }

    function setState(state, message) {
        const isFilteredEmpty = state === 'filtered-empty';
        const isEmpty = state === 'empty' || isFilteredEmpty;
        const filtersVisible = state === 'data' || isFilteredEmpty;

        show(document.getElementById('prescriptionsLoading'), state === 'loading');
        show(document.getElementById('prescriptionsError'), state === 'error');
        show(document.getElementById('prescriptionsData'), state === 'data');
        show(document.getElementById('prescriptionsPreview'), false);
        show(document.getElementById('prescriptionsEmpty'), isEmpty);
        show(document.getElementById('prescriptionsFilters'), filtersVisible);
        setFiltersEnabled(filtersVisible);

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
            '</div>';
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
            const isFiltered = prescriptions.length > 0;
            setEmptyStateContent(isFiltered);
            setState(isFiltered ? 'filtered-empty' : 'empty');
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
            prescriptions = await fetchPrescriptions();
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
        // Static labels are translated by I18n, but prescription names and
        // dates are rendered from API data. Re-render them on a language
        // switch so medication_name_en is used in English and
        // medication_name_ar in Arabic whenever both values exist.
        window.addEventListener('languageChanged', render);

        load();
    }

    return { init, fetchPrescriptions };

})();

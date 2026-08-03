/**
 * MedOrbit v2 - Symptom Checker
 * Calls the AI service directly: POST <current-host>:8001/triage
 * (open CORS, no auth — this is not the Node backend on :3001).
 */
const SymptomChecker = (() => {

    const AI_BASE = API.getAiOrigin();

    // Matches real seeded symptom_specialty_mappings keywords so these
    // quick-add chips reliably produce a good triage result.
    const COMMON_SYMPTOMS = [
        { en: 'Chest pain', ar: 'ألم في الصدر' },
        { en: 'Headache', ar: 'صداع' },
        { en: 'Fever', ar: 'حمى' },
        { en: 'Stomach pain', ar: 'ألم في المعدة' },
        { en: 'Back pain', ar: 'ألم في الظهر' },
        { en: 'Cough', ar: 'سعال' },
        { en: 'Skin rash', ar: 'طفح جلدي' },
        { en: 'Joint pain', ar: 'ألم في المفاصل' }
    ];

    let chipInput = null;

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

    function showAlert(message) {
        const box = document.getElementById('formAlert');
        if (!box) return;
        box.className = 'alert error';
        box.textContent = message;
    }

    function clearAlert() {
        const box = document.getElementById('formAlert');
        if (box) box.className = 'alert';
    }

    function setLoading(loading) {
        document.getElementById('submitBtn')?.classList.toggle('loading', loading);
    }

    // ================= QUICK CHIPS =================

    function renderQuickChips() {
        const el = document.getElementById('quickChips');
        if (!el) return;
        const ar = isAr();

        el.innerHTML = COMMON_SYMPTOMS.map(s => {
            const label = ar ? s.ar : s.en;
            return '<button type="button" class="quick-chip" data-value="' + escapeHtml(label) + '">' + escapeHtml(label) + '</button>';
        }).join('');

        el.querySelectorAll('.quick-chip').forEach(btn => {
            btn.addEventListener('click', () => chipInput.addItem(btn.dataset.value));
        });
    }

    // ================= SUBMIT =================

    async function submit() {
        clearAlert();
        const symptoms = chipInput.getItems();

        if (symptoms.length === 0) {
            showAlert(t('symptomChecker.errorMinSymptoms'));
            return;
        }

        setLoading(true);
        showLoading();

        try {
            const res = await fetch(AI_BASE + '/triage', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ symptoms })
            });

            const data = await res.json().catch(() => null);

            if (!res.ok) {
                throw new Error(data?.detail || 'Request failed');
            }

            showResult(data);

        } catch (err) {
            console.error('SymptomChecker: request failed', err);
            showError();
        } finally {
            setLoading(false);
        }
    }

    // ================= RENDER: STATES =================

    function showLoading() {
        document.getElementById('formSection')?.classList.add('hidden');
        const result = document.getElementById('resultSection');
        if (!result) return;
        result.innerHTML =
            '<div class="tool-loading">' +
                '<div class="spinner spinner-lg"></div>' +
                '<p>' + escapeHtml(t('symptomChecker.loadingText')) + '</p>' +
            '</div>';
        result.classList.remove('hidden');
    }

    function showError() {
        const result = document.getElementById('resultSection');
        if (!result) return;
        result.innerHTML =
            '<div class="tool-error">' +
                '<i class="fas fa-triangle-exclamation"></i>' +
                '<p>' + escapeHtml(t('aitools.serverError')) + '</p>' +
                '<button type="button" class="btn btn-secondary btn-sm" id="retryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
            '</div>';
        document.getElementById('retryBtn')?.addEventListener('click', submit);
        result.classList.remove('hidden');
    }

    function showResult(data) {
        const ar = isAr();
        const level = data.triage_level || 'routine';

        const levelMeta = {
            emergency: { icon: 'fa-triangle-exclamation', titleKey: 'symptomChecker.emergencyTitle' },
            urgent: { icon: 'fa-clock', titleKey: 'symptomChecker.urgentTitle' },
            routine: { icon: 'fa-calendar-check', titleKey: 'symptomChecker.routineTitle' }
        }[level] || { icon: 'fa-info-circle', titleKey: 'symptomChecker.routineTitle' };

        const specialtyDisplay = (ar ? data.recommended_specialty_name_ar : data.recommended_specialty_name_en)
            || data.recommended_specialty_name_en || data.recommended_specialty_name_ar || '';
        const confidencePct = Math.max(0, Math.min(100, Math.round((data.confidence_score || 0) * 100)));

        let html = '';

        html += '<div class="triage-banner ' + level + '">' +
            '<div class="triage-banner-icon"><i class="fas ' + levelMeta.icon + '"></i></div>' +
            '<div>' +
                '<h2>' + escapeHtml(t(levelMeta.titleKey)) + '</h2>' +
                (level === 'emergency' ? '<p>' + escapeHtml(t('symptomChecker.emergencyMsg')) + '</p>' : '') +
            '</div>' +
        '</div>';

        html += '<div class="tool-card">';
        if (specialtyDisplay) {
            html += '<div class="triage-detail-row">' +
                '<span class="triage-detail-label">' + escapeHtml(t('symptomChecker.recommendedSpecialty')) + '</span>' +
                '<span class="triage-detail-value">' + escapeHtml(specialtyDisplay) + '</span>' +
            '</div>';
        }
        html += '<div class="triage-detail-row">' +
            '<span class="triage-detail-label">' + escapeHtml(t('symptomChecker.confidence')) + '</span>' +
            '<div class="confidence-bar"><div class="confidence-bar-fill" style="width:' + confidencePct + '%;"></div></div>' +
        '</div>';
        if (data.recommendations) {
            html += '<div style="margin-top:16px;">' +
                '<div class="triage-detail-label" style="margin-bottom:8px;">' + escapeHtml(t('symptomChecker.recommendations')) + '</div>' +
                '<p style="font-size:13.5px;color:var(--text-soft);line-height:1.6;">' + escapeHtml(data.recommendations) + '</p>' +
            '</div>';
        }
        html += '</div>';

        html += '<div class="result-actions">';
        if (data.recommended_specialty_name_en) {
            html += '<a class="btn btn-primary" href="find-doctors.html?specialty=' + encodeURIComponent(data.recommended_specialty_name_en) + '">' +
                '<i class="fas fa-user-doctor"></i> ' + escapeHtml(t('symptomChecker.findSpecialist')) +
            '</a>';
        }
        html += '<button type="button" class="btn btn-secondary" id="checkAnotherBtn">' +
            '<i class="fas fa-rotate-left"></i> ' + escapeHtml(t('symptomChecker.checkAnother')) +
        '</button>';
        html += '</div>';

        const result = document.getElementById('resultSection');
        if (result) {
            result.innerHTML = html;
            result.classList.remove('hidden');
        }

        document.getElementById('checkAnotherBtn')?.addEventListener('click', reset);
    }

    function reset() {
        chipInput.clear();
        clearAlert();
        const result = document.getElementById('resultSection');
        if (result) {
            result.innerHTML = '';
            result.classList.add('hidden');
        }
        document.getElementById('formSection')?.classList.remove('hidden');
    }

    // ================= INIT =================

    function init() {
        chipInput = ChipInput.create({
            inputId: 'symptomInput',
            addBtnId: 'addSymptomBtn',
            listId: 'symptomList'
        });

        renderQuickChips();

        document.getElementById('symptomForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            submit();
        });

        window.addEventListener('languageChanged', renderQuickChips);
    }

    return { init };

})();

const DrugChecker = (() => {

const COMMON_MEDICATIONS = [
        { en: 'Paracetamol', ar: 'باراسيتامول' },
        { en: 'Aspirin', ar: 'أسبرين' },
        { en: 'Warfarin', ar: 'وارفارين' },
        { en: 'Metformin', ar: 'ميتفورمين' },
        { en: 'Omeprazole', ar: 'أوميبرازول' },
        { en: 'Amlodipine', ar: 'أملوديبين' },
        { en: 'Diclofenac', ar: 'ديكلوفيناك' },
        { en: 'Azithromycin', ar: 'أزيثرومايسين' }
    ];

    const SEVERITY_ORDER = ['severe', 'moderate', 'mild', 'unknown'];
    const SEVERITY_META = {
        severe: { icon: 'fa-triangle-exclamation', labelKey: 'drugChecker.severitySevere' },
        moderate: { icon: 'fa-circle-exclamation', labelKey: 'drugChecker.severityModerate' },
        mild: { icon: 'fa-circle-info', labelKey: 'drugChecker.severityMild' },
        unknown: { icon: 'fa-question', labelKey: 'drugChecker.severityUnknown' }
    };

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

    function setLoading(loading) {
        document.getElementById('submitBtn')?.classList.toggle('loading', loading);
    }

    function drugName(drug) {
        return (isAr() ? drug.name_ar : drug.name_en) || drug.name_en || drug.name_ar || '';
    }

    function interactionDescription(interaction) {
        const description = interaction.description || '';

if (/^Severe - increased bleeding risk\./i.test(description)) {
            return t('drugChecker.bleedingRiskWarning');
        }
        return description;
    }

function renderQuickChips() {
        const el = document.getElementById('quickChips');
        if (!el) return;
        const ar = isAr();

el.innerHTML = COMMON_MEDICATIONS.map(m => {
            const label = ar ? m.ar : m.en;
            return '<button type="button" class="quick-chip" data-value="' + escapeHtml(label) + '">' + escapeHtml(label) + '</button>';
        }).join('');

        el.querySelectorAll('.quick-chip').forEach(btn => {
            btn.addEventListener('click', () => chipInput.addItem(btn.dataset.value));
        });
    }

async function submit() {
        FormAlert.clear();
        const medications = chipInput.getItems();

        if (medications.length < 2) {
            FormAlert.error(t('drugChecker.errorMinMeds'));
            return;
        }

        setLoading(true);
        showLoading();

        try {
            const response = await API.post('/ai/drug-interactions', {
                medication_names: medications
            });
            showResult(response?.data || response);

        } catch (err) {
            console.error('DrugChecker: request failed', err);
            showError();
        } finally {
            setLoading(false);
        }
    }

function showLoading() {
        document.getElementById('formSection')?.classList.add('hidden');
        const result = document.getElementById('resultSection');
        if (!result) return;
        result.innerHTML =
            '<div class="tool-loading">' +
                '<div class="spinner spinner-lg"></div>' +
                '<p>' + escapeHtml(t('drugChecker.loadingText')) + '</p>' +
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
        let html = '';

        if (!data.has_interactions || !data.interactions || data.interactions.length === 0) {
            html = '<div class="no-interactions">' +
                '<i class="fas fa-circle-check"></i>' +
                '<h3>' + escapeHtml(t('drugChecker.noInteractionsTitle')) + '</h3>' +
                '<p style="margin-top:6px;color:var(--text-mute);font-size:13.5px;">' + escapeHtml(t('drugChecker.noInteractionsDesc')) + '</p>' +
            '</div>';
        } else {
            const grouped = {};
            data.interactions.forEach(ix => {
                const sev = SEVERITY_META[ix.severity] ? ix.severity : 'unknown';
                (grouped[sev] = grouped[sev] || []).push(ix);
            });

            html += '<div class="tool-card">';
            SEVERITY_ORDER.forEach(sev => {
                const items = grouped[sev];
                if (!items || items.length === 0) return;

                const meta = SEVERITY_META[sev];
                html += '<div class="severity-group">' +
                    '<div class="severity-group-title"><i class="fas ' + meta.icon + '"></i> ' +
                        escapeHtml(t(meta.labelKey)) + ' (' + items.length + ')' +
                    '</div>';

                items.forEach(ix => {
                    const d1 = drugName(ix.drug_1);
                    const d2 = drugName(ix.drug_2);
                    html += '<div class="interaction-card ' + sev + '">' +
                        '<div class="interaction-card-icon"><i class="fas ' + meta.icon + '"></i></div>' +
                        '<div>' +
                            '<div class="interaction-card-title">' + escapeHtml(d1) + ' + ' + escapeHtml(d2) + '</div>' +
                            (ix.description ? '<div class="interaction-card-desc">' + escapeHtml(interactionDescription(ix)) + '</div>' : '') +
                        '</div>' +
                    '</div>';
                });

                html += '</div>';
            });
            html += '</div>';
        }

        html += '<div class="result-actions">' +
            '<button type="button" class="btn btn-secondary" id="checkAnotherBtn">' +
                '<i class="fas fa-rotate-left"></i> ' + escapeHtml(t('drugChecker.checkAnother')) +
            '</button>' +
        '</div>';

        const result = document.getElementById('resultSection');
        if (result) {
            result.innerHTML = html;
            result.classList.remove('hidden');
        }

        document.getElementById('checkAnotherBtn')?.addEventListener('click', reset);
    }

    function reset() {
        chipInput.clear();
        FormAlert.clear();
        const result = document.getElementById('resultSection');
        if (result) {
            result.innerHTML = '';
            result.classList.add('hidden');
        }
        document.getElementById('formSection')?.classList.remove('hidden');
    }

function init() {
        chipInput = ChipInput.create({
            inputId: 'medInput',
            addBtnId: 'addMedBtn',
            listId: 'medList'
        });

        renderQuickChips();

        document.getElementById('drugForm')?.addEventListener('submit', (e) => {
            e.preventDefault();
            submit();
        });

        window.addEventListener('languageChanged', renderQuickChips);
    }

    return { init };

})();

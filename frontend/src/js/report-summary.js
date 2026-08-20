/**
 * MedOrbit v2 - Medical Report Summarizer
 * Calls the AI service directly: POST <current-host>:8001/summarize
 * (multipart/form-data, open CORS, no auth — this is not the Node backend).
 */
const ReportSummary = (() => {

    const MAX_SIZE_BYTES = 10 * 1024 * 1024; // 10MB
    const ALLOWED_EXT = ['pdf', 'jpg', 'jpeg', 'png'];

    let selectedFile = null;
    let activeTab = 'ar';

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

    function formatSize(bytes) {
        if (bytes < 1024) return bytes + ' B';
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
        return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
    }

    function setLoading(loading) {
        document.getElementById('submitBtn')?.classList.toggle('loading', loading);
    }

    // ================= FILE SELECTION =================

    function validateFile(file) {
        const ext = (file.name || '').split('.').pop().toLowerCase();
        if (!ALLOWED_EXT.includes(ext)) {
            return t('reportSummary.errorFileType');
        }
        if (file.size > MAX_SIZE_BYTES) {
            return t('reportSummary.errorFileSize');
        }
        return null;
    }

    function selectFile(file) {
        clearAlert();
        if (!file) return;

        const error = validateFile(file);
        if (error) {
            showAlert(error);
            return;
        }

        selectedFile = file;

        document.getElementById('dropzone')?.classList.add('hidden');
        const chip = document.getElementById('fileChip');
        chip?.classList.remove('hidden');
        document.getElementById('fileName').textContent = file.name;
        document.getElementById('fileSize').textContent = formatSize(file.size);
        document.getElementById('submitBtn').disabled = false;
    }

    function clearFile() {
        selectedFile = null;
        document.getElementById('dropzone')?.classList.remove('hidden');
        document.getElementById('fileChip')?.classList.add('hidden');
        document.getElementById('submitBtn').disabled = true;
        const input = document.getElementById('fileInput');
        if (input) input.value = '';
    }

    // ================= SUBMIT =================

    async function submit() {
        if (!selectedFile) return;
        clearAlert();

        setLoading(true);
        showLoading();

        try {
            const data = await API.uploadFile('/ai/summarize', 'file', selectedFile);

            showResult(data);

        } catch (err) {
            console.error('ReportSummary: request failed', err);
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
                '<p>' + escapeHtml(t('reportSummary.loadingText')) + '</p>' +
                '<p class="loading-hint">' + escapeHtml(t('reportSummary.loadingHint')) + '</p>' +
            '</div>';
        result.classList.remove('hidden');
    }

    function showError() {
        const result = document.getElementById('resultSection');
        if (!result) return;

        const message = t('aitools.serverError');

        result.innerHTML =
            '<div class="tool-error">' +
                '<i class="fas fa-triangle-exclamation"></i>' +
                '<p>' + escapeHtml(message) + '</p>' +
                '<button type="button" class="btn btn-secondary btn-sm" id="retryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
            '</div>';
        document.getElementById('retryBtn')?.addEventListener('click', submit);
        result.classList.remove('hidden');
    }

    function showResult(data) {
        activeTab = isAr() ? 'ar' : 'en';

        const html =
            '<div class="summary-tabs">' +
                '<div class="summary-tab' + (activeTab === 'ar' ? ' active' : '') + '" data-tab="ar" data-i18n="reportSummary.tabAr"></div>' +
                '<div class="summary-tab' + (activeTab === 'en' ? ' active' : '') + '" data-tab="en" data-i18n="reportSummary.tabEn"></div>' +
            '</div>' +
            '<div class="summary-content" id="summaryContent" dir="' + (activeTab === 'ar' ? 'rtl' : 'ltr') + '"></div>' +

            (data.extracted_text ? (
                '<div class="collapsible-toggle" id="extractedToggle">' +
                    '<i class="fas fa-chevron-down"></i>' +
                    '<span data-i18n="reportSummary.extractedTextToggle"></span>' +
                '</div>' +
                '<div class="collapsible-content" id="extractedContent"></div>'
            ) : '') +

            '<div class="result-actions">' +
                '<button type="button" class="btn btn-secondary" id="summarizeAnotherBtn">' +
                    '<i class="fas fa-rotate-left"></i> ' + escapeHtml(t('reportSummary.summarizeAnother')) +
                '</button>' +
            '</div>';

        const result = document.getElementById('resultSection');
        if (!result) return;
        result.innerHTML = html;
        result.classList.remove('hidden');

        if (typeof I18n !== 'undefined') I18n.apply();

        function renderTabContent() {
            const content = document.getElementById('summaryContent');
            if (!content) return;
            content.dir = activeTab === 'ar' ? 'rtl' : 'ltr';
            content.textContent = (activeTab === 'ar' ? data.summary_ar : data.summary_en) || '';
        }
        renderTabContent();

        result.querySelectorAll('.summary-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                activeTab = tab.dataset.tab;
                result.querySelectorAll('.summary-tab').forEach(el => el.classList.toggle('active', el === tab));
                renderTabContent();
            });
        });

        if (data.extracted_text) {
            document.getElementById('extractedContent').textContent = data.extracted_text;
            document.getElementById('extractedToggle')?.addEventListener('click', function () {
                this.classList.toggle('open');
                document.getElementById('extractedContent')?.classList.toggle('open');
            });
        }

        document.getElementById('summarizeAnotherBtn')?.addEventListener('click', reset);
    }

    function reset() {
        clearFile();
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
        const dropzone = document.getElementById('dropzone');
        const fileInput = document.getElementById('fileInput');

        dropzone?.addEventListener('click', () => fileInput?.click());

        fileInput?.addEventListener('change', () => {
            if (fileInput.files && fileInput.files[0]) selectFile(fileInput.files[0]);
        });

        ['dragenter', 'dragover'].forEach(evt => {
            dropzone?.addEventListener(evt, (e) => {
                e.preventDefault();
                dropzone.classList.add('drag-over');
            });
        });

        ['dragleave', 'drop'].forEach(evt => {
            dropzone?.addEventListener(evt, (e) => {
                e.preventDefault();
                dropzone.classList.remove('drag-over');
            });
        });

        dropzone?.addEventListener('drop', (e) => {
            const file = e.dataTransfer?.files?.[0];
            if (file) selectFile(file);
        });

        document.getElementById('removeFileBtn')?.addEventListener('click', (e) => {
            e.stopPropagation();
            clearFile();
        });

        document.getElementById('submitBtn')?.addEventListener('click', submit);
    }

    return { init };

})();

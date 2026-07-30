/**
 * MedOrbit v2 - AI Virtual Doctor
 * Calls the AI service directly: POST/GET http://127.0.0.1:8001/virtual-doctor/*
 * (open CORS, no auth on the ai-service side — this page itself is
 * auth-guarded via API.requireAuth(), same as the other protected pages).
 */
const VirtualDoctor = (() => {

    const AI_BASE = window.MEDORBIT_AI_URL ||
        (window.location.hostname ? `${window.location.protocol}//${window.location.hostname}:8001` : 'http://127.0.0.1:8001');

    const PHASES = ['greeting', 'interviewing', 'reasoning', 'complete'];

    // profile_snapshot carries a couple of internal bookkeeping fields that
    // aren't meant for the patient-facing panel (mirrors report_generator.py's
    // _EXCLUDED_PROFILE_KEYS on the ai-service side).
    const EXCLUDED_PROFILE_KEYS = new Set(['chief_complaint_description', 'associated_symptoms_detected']);

    let sessionId = null;
    let isSending = false;
    let isComplete = false;

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

    // ================= START / RESTART =================

    async function startConsultation() {
        setStartLoading(true);
        try {
            const user = typeof API !== 'undefined' ? API.getUser() : null;
            const res = await fetch(AI_BASE + '/virtual-doctor/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ language: isAr() ? 'ar' : 'en', user_id: user?.id || null })
            });

            const data = await res.json().catch(() => null);
            if (!res.ok) throw new Error(data?.detail || 'Request failed');

            sessionId = data.session_id;
            resetConsultationUi();
            showConsultation();
            updateStepper(data.phase);
            appendDoctorMessage(data.reply);
            focusInput();

        } catch (err) {
            console.error('VirtualDoctor: failed to start', err);
            if (typeof Toast !== 'undefined') Toast.error(t('virtualDoctor.startError'));
        } finally {
            setStartLoading(false);
        }
    }

    function restart() {
        startConsultation();
    }

    // ================= SEND MESSAGE =================

    async function sendMessage(text) {
        if (!text || isSending || !sessionId || isComplete) return;

        isSending = true;
        setSendingState(true);
        appendUserMessage(text);
        showTyping();

        try {
            const res = await fetch(AI_BASE + '/virtual-doctor/message', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ session_id: sessionId, message: text })
            });

            const data = await res.json().catch(() => null);
            if (!res.ok) throw new Error(data?.detail || 'Request failed');

            hideTyping();
            appendDoctorMessage(data.reply);
            updateStepper(data.phase);
            updateProfilePanel(data.profile_snapshot, data.chief_complaint);

            if (data.phase === 'complete') {
                isComplete = true;
                renderCompletion(data);
                disableInput();
            }

        } catch (err) {
            hideTyping();
            console.error('VirtualDoctor: send failed', err);
            appendErrorMessage(t('virtualDoctor.sendError'));
        } finally {
            isSending = false;
            setSendingState(false);
        }
    }

    // ================= MESSAGES =================

    function appendUserMessage(text) {
        const el = document.getElementById('vdMessages');
        if (!el) return;
        const div = document.createElement('div');
        div.className = 'message user';
        div.innerHTML = '<div class="message-bubble">' + escapeHtml(text) + '</div>';
        el.appendChild(div);
        scrollMessages(el);
    }

    function appendDoctorMessage(text) {
        if (!text) return;
        const el = document.getElementById('vdMessages');
        if (!el) return;
        const div = document.createElement('div');
        div.className = 'message bot';
        div.innerHTML = '<div class="message-bubble">' + escapeHtml(text).replace(/\n/g, '<br/>') + '</div>';
        el.appendChild(div);
        scrollMessages(el);
    }

    function appendErrorMessage(text) {
        const el = document.getElementById('vdMessages');
        if (!el) return;
        const div = document.createElement('div');
        div.className = 'message bot error';
        div.innerHTML = '<div class="message-bubble">' + escapeHtml(text) + '</div>';
        el.appendChild(div);
        scrollMessages(el);
    }

    function scrollMessages(el) {
        el.scrollTop = el.scrollHeight;
    }

    function showTyping() {
        const el = document.getElementById('vdTyping');
        if (el) el.style.display = 'flex';
    }

    function hideTyping() {
        const el = document.getElementById('vdTyping');
        if (el) el.style.display = 'none';
    }

    // ================= STEPPER =================

    function updateStepper(phase) {
        const idx = PHASES.indexOf(phase);
        document.querySelectorAll('.vd-step').forEach((stepEl) => {
            const stepIdx = PHASES.indexOf(stepEl.dataset.phase);
            stepEl.classList.remove('done', 'current');
            if (stepIdx < idx) stepEl.classList.add('done');
            else if (stepIdx === idx) stepEl.classList.add('current');
        });
    }

    // ================= PROFILE PANEL =================

    function slotLabelKey(key) {
        const camel = key.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
        return 'virtualDoctor.slot.' + camel;
    }

    function updateProfilePanel(profile, chiefComplaint) {
        const el = document.getElementById('vdProfileContent');
        if (!el) return;
        profile = profile || {};

        let rows = '';

        if (chiefComplaint) {
            rows += '<div class="vd-profile-row"><span class="vd-profile-label">' +
                escapeHtml(t('virtualDoctor.chiefComplaintLabel')) + '</span><span class="vd-profile-value">' +
                escapeHtml(chiefComplaint) + '</span></div>';
        }

        Object.keys(profile).forEach((key) => {
            if (EXCLUDED_PROFILE_KEYS.has(key)) return;
            const value = profile[key];
            if (!value || typeof value !== 'string') return;
            rows += '<div class="vd-profile-row"><span class="vd-profile-label">' +
                escapeHtml(t(slotLabelKey(key))) + '</span><span class="vd-profile-value">' +
                escapeHtml(value) + '</span></div>';
        });

        el.innerHTML = rows || '<p class="vd-profile-empty">' + escapeHtml(t('virtualDoctor.profileEmpty')) + '</p>';
    }

    // ================= COMPLETION =================

    function renderCompletion(data) {
        const el = document.getElementById('vdCompletionSection');
        if (!el) return;

        const ar = isAr();
        const level = data.urgency_level || 'routine';
        const levelMeta = {
            emergency: { icon: 'fa-triangle-exclamation', titleKey: 'symptomChecker.emergencyTitle' },
            urgent: { icon: 'fa-clock', titleKey: 'symptomChecker.urgentTitle' },
            routine: { icon: 'fa-calendar-check', titleKey: 'symptomChecker.routineTitle' }
        }[level] || { icon: 'fa-info-circle', titleKey: 'symptomChecker.routineTitle' };

        const specialtyDisplay = (ar ? data.recommended_specialty_name_ar : data.recommended_specialty_name_en) || '';
        const differential = data.differential || {};
        const conditions = Array.isArray(differential.conditions) ? differential.conditions : [];
        const nextStep = differential.next_step || '';
        const confidencePct = typeof data.confidence === 'number'
            ? Math.max(0, Math.min(100, Math.round(data.confidence * 100)))
            : null;

        const isEmergency = level === 'emergency';
        let html = '';

        html += '<div class="triage-banner ' + level + (isEmergency ? ' vd-emergency-pulse' : '') + '"' +
            ' role="' + (isEmergency ? 'alert' : 'status') + '"' + (isEmergency ? ' aria-live="assertive"' : '') + '>' +
            '<div class="triage-banner-icon"><i class="fas ' + levelMeta.icon + '"></i></div>' +
            '<div>' +
                '<h2>' + escapeHtml(t(levelMeta.titleKey)) + '</h2>' +
                (isEmergency ? '<p>' + escapeHtml(t('symptomChecker.emergencyMsg')) + '</p>' : '') +
            '</div>' +
        '</div>';

        if (specialtyDisplay || confidencePct != null) {
            html += '<div class="tool-card">';
            if (specialtyDisplay) {
                html += '<div class="triage-detail-row"><span class="triage-detail-label">' +
                    escapeHtml(t('symptomChecker.recommendedSpecialty')) + '</span><span class="triage-detail-value">' +
                    escapeHtml(specialtyDisplay) + '</span></div>';
            }
            if (confidencePct != null) {
                html += '<div class="triage-detail-row"><span class="triage-detail-label">' +
                    escapeHtml(t('symptomChecker.confidence')) + '</span><div class="confidence-bar">' +
                    '<div class="confidence-bar-fill" style="width:' + confidencePct + '%;"></div></div></div>';
            }
            html += '</div>';
        }

        if (conditions.length > 0) {
            html += '<div class="tool-card">';
            html += '<div class="triage-detail-label" style="margin-bottom:10px;">' +
                escapeHtml(t('virtualDoctor.differentialTitle')) + '</div>';
            html += '<ul class="vd-differential-list">';
            conditions.forEach((c) => {
                const likelihoodKey = {
                    high: 'virtualDoctor.likelihoodHigh',
                    medium: 'virtualDoctor.likelihoodMedium',
                    low: 'virtualDoctor.likelihoodLow'
                }[c?.likelihood] || null;
                html += '<li><span class="vd-cond-name">' + escapeHtml(c?.condition || '') + '</span>' +
                    (likelihoodKey ? '<span class="vd-cond-likelihood ' + escapeHtml(c.likelihood) + '">' +
                        escapeHtml(t(likelihoodKey)) + '</span>' : '') +
                '</li>';
            });
            html += '</ul></div>';
        }

        if (nextStep) {
            html += '<div class="tool-card">';
            html += '<div class="triage-detail-label" style="margin-bottom:8px;">' +
                escapeHtml(t('virtualDoctor.nextStepLabel')) + '</div>';
            html += '<p style="font-size:13.5px;color:var(--text-soft);line-height:1.6;">' +
                escapeHtml(nextStep) + '</p></div>';
        }

        html += '<div class="result-actions">';
        html += '<button type="button" class="btn btn-primary vd-download-btn" id="vdDownloadBtn">' +
            '<i class="fas fa-file-arrow-down"></i> <span class="btn-label">' +
            escapeHtml(t('virtualDoctor.downloadReportBtn')) + '</span>' +
            '<span class="spinner spinner-sm btn-spinner"></span></button>';
        html += '<button type="button" class="btn btn-secondary" id="vdRestartBtn2">' +
            '<i class="fas fa-rotate-left"></i> ' + escapeHtml(t('virtualDoctor.restartBtn')) + '</button>';
        html += '</div>';

        el.innerHTML = html;
        el.classList.remove('hidden');

        document.getElementById('vdDownloadBtn')?.addEventListener('click', downloadReport);
        document.getElementById('vdRestartBtn2')?.addEventListener('click', restart);

        el.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }

    async function downloadReport() {
        if (!sessionId) return;
        const btn = document.getElementById('vdDownloadBtn');
        btn?.classList.add('loading');

        try {
            const res = await fetch(AI_BASE + '/virtual-doctor/report/' + sessionId, { method: 'POST' });
            const data = await res.json().catch(() => null);
            if (!res.ok) throw new Error(data?.detail || 'Request failed');

            const a = document.createElement('a');
            a.href = AI_BASE + data.download_url;
            a.target = '_blank';
            a.rel = 'noopener';
            document.body.appendChild(a);
            a.click();
            a.remove();

        } catch (err) {
            console.error('VirtualDoctor: report generation failed', err);
            if (typeof Toast !== 'undefined') Toast.error(t('virtualDoctor.reportError'));
        } finally {
            btn?.classList.remove('loading');
        }
    }

    // ================= UI STATE HELPERS =================

    function showConsultation() {
        document.getElementById('vdIdleCard')?.classList.add('hidden');
        document.getElementById('vdConsultation')?.classList.remove('hidden');
    }

    function resetConsultationUi() {
        isComplete = false;

        const messages = document.getElementById('vdMessages');
        if (messages) messages.innerHTML = '';

        hideTyping();

        const completion = document.getElementById('vdCompletionSection');
        if (completion) {
            completion.innerHTML = '';
            completion.classList.add('hidden');
        }

        updateProfilePanel({}, null);
        updateStepper('greeting');
        enableInput();

        const input = document.getElementById('vdInput');
        if (input) input.value = '';
    }

    function enableInput() {
        const input = document.getElementById('vdInput');
        const form = document.getElementById('vdForm');
        const note = document.getElementById('vdEndedNote');
        const btn = document.getElementById('vdSendBtn');
        if (input) input.disabled = false;
        if (form) form.classList.remove('hidden');
        if (note) note.classList.add('hidden');
        if (btn) btn.disabled = true;
    }

    function disableInput() {
        const input = document.getElementById('vdInput');
        const form = document.getElementById('vdForm');
        const note = document.getElementById('vdEndedNote');
        if (input) input.disabled = true;
        if (form) form.classList.add('hidden');
        if (note) note.classList.remove('hidden');
    }

    function setSendingState(sending) {
        const btn = document.getElementById('vdSendBtn');
        const input = document.getElementById('vdInput');
        if (input) input.disabled = sending;
        if (btn) btn.disabled = sending || !input?.value.trim();
    }

    function setStartLoading(loading) {
        document.getElementById('vdStartBtn')?.classList.toggle('loading', loading);
    }

    function focusInput() {
        document.getElementById('vdInput')?.focus();
    }

    // ================= INIT =================

    function init() {
        if (typeof API !== 'undefined' && !API.requireAuth()) return;

        document.getElementById('vdStartBtn')?.addEventListener('click', startConsultation);
        document.getElementById('vdRestartBtn')?.addEventListener('click', restart);

        document.getElementById('vdProfileToggle')?.addEventListener('click', () => {
            document.getElementById('vdProfileToggle')?.classList.toggle('open');
            document.getElementById('vdProfileContent')?.classList.toggle('open');
        });

        const form = document.getElementById('vdForm');
        const input = document.getElementById('vdInput');

        form?.addEventListener('submit', (e) => {
            e.preventDefault();
            const text = input?.value.trim();
            if (!text) return;
            if (input) input.value = '';
            setSendingState(true);
            sendMessage(text);
        });

        input?.addEventListener('input', () => {
            const btn = document.getElementById('vdSendBtn');
            if (btn) btn.disabled = isSending || !input.value.trim();
        });
    }

    return { init };

})();

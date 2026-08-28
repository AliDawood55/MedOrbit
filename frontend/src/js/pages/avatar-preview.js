(() => {
    'use strict';

    const els = {};
    let sessionActive = false;
    let ttsEnabled = true;
    let turnStartedAt = 0;
    let listeningSince = 0;
    let timerInterval = null;

    function logLine(msg) {
        const el = els.log;
        console.debug('[consult]', msg);
        if (!el) return;
        const line = document.createElement('div');
        line.textContent = '[' + new Date().toLocaleTimeString() + '] ' + msg;
        el.appendChild(line);
        el.scrollTop = el.scrollHeight;
    }

    function tr(key, fallback) {
        if (typeof I18n !== 'undefined' && I18n.t) {
            const val = I18n.t(key);
            if (val && val !== key) return val;
        }
        return fallback;
    }

    const STATE_KEYS = {
        connecting:     ['consult.stateConnecting', 'Connecting…',      'thinking'],
        listening:      ['consult.stateListening',  'Listening',        'listening'],
        capturing:      ['consult.stateCapturing',  'I can hear you',   'capturing'],
        transcribing:   ['consult.stateTranscribing', 'Understanding…', 'thinking'],
        thinking:       ['consult.stateThinking',   'Thinking…',        'thinking'],
        doctorSpeaking: ['consult.stateDoctor',     'Doctor is speaking', 'speaking'],
        complete:       ['consult.stateComplete',   'Consultation complete', 'idle'],
        idle:           ['consult.stateIdle',       'Ready',            'idle']
    };

    function setStatus(state) {
        const entry = STATE_KEYS[state] || STATE_KEYS.idle;
        els.statusStrip.className = 'avatar-status-strip state-' + entry[2];
        els.statusLabel.setAttribute('data-i18n', entry[0]);
        els.statusLabel.textContent = tr(entry[0], entry[1]);

        if (els.voiceStage) {
            const speakingAloud = els.statusStrip.classList.contains('is-speaking-aloud');
            els.voiceStage.className = 'voice-stage state-' + entry[2] +
                (speakingAloud ? ' is-speaking-aloud' : '');
            els.voiceLabel.setAttribute('data-i18n', entry[0]);
            els.voiceLabel.textContent = tr(entry[0], entry[1]);
        }

        if (state === 'listening') {
            listeningSince = Date.now();
            startTimer();
        } else if (state === 'capturing') {
            startTimer();
        } else {
            stopTimer();
        }
    }

    function startTimer() {
        if (timerInterval) return;
        timerInterval = setInterval(() => {
            const secs = Math.floor((Date.now() - listeningSince) / 1000);
            els.statusTimer.textContent = secs > 0
                ? String(Math.floor(secs / 60)).padStart(2, '0') + ':' + String(secs % 60).padStart(2, '0')
                : '';
        }, 250);
    }

    function stopTimer() {
        if (timerInterval) clearInterval(timerInterval);
        timerInterval = null;
        els.statusTimer.textContent = '';
    }

    function addBubble(role, text, lang) {
        const wrap = document.createElement('div');
        wrap.className = 'consult-bubble consult-bubble-' + role;
        const who = document.createElement('span');
        who.className = 'consult-bubble-who';
        who.textContent = role === 'doctor'
            ? tr('consult.doctorLabel', 'Doctor')
            : tr('consult.patientLabel', 'You');
        const body = document.createElement('p');
        body.textContent = text;
        if (lang) {
            body.setAttribute('lang', lang);
            body.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
        }
        wrap.appendChild(who);
        wrap.appendChild(body);
        els.conversation.appendChild(wrap);
        els.conversation.scrollTop = els.conversation.scrollHeight;
        return wrap;
    }

    function setMicStatus(text) {
        if (!text) { els.micStatus.hidden = true; els.micStatus.textContent = ''; return; }
        els.micStatus.hidden = false;
        els.micStatus.textContent = text;
    }

    function showError(detail) {
        els.micError.hidden = false;
        els.micErrorMsg.textContent = tr(detail.key, 'Microphone error.');
        els.micErrorHelp.hidden = !detail.showHelp;

        els.btnRetryMic.hidden = !detail.fatal;
        logLine('ERROR [' + detail.code + '] ' + (detail.detail || ''));
    }

    let voicePaywallTimer = null;

    function formatRemaining(ms) {
        const total = Math.max(Math.floor(ms / 1000), 0);
        const h = String(Math.floor(total / 3600)).padStart(2, '0');
        const m = String(Math.floor((total % 3600) / 60)).padStart(2, '0');
        const sec = String(total % 60).padStart(2, '0');
        return h + ':' + m + ':' + sec;
    }

    function showVoicePaywall({ code, nextFreeAt, upgradeAvailable }) {
        let panel = document.getElementById('voicePaywall');
        if (!panel) {
            panel = document.createElement('div');
            panel.id = 'voicePaywall';
            panel.className = 'voice-paywall';
            const anchor = els.btnStartConsult && els.btnStartConsult.parentElement;
            (anchor || document.body).appendChild(panel);
        }

        const isAr = (typeof I18n !== 'undefined' && I18n.getLang && I18n.getLang() === 'ar');
        const heading = code === 'VOICE_COOLDOWN'
            ? (isAr ? 'استشارتك المجانية القادمة ستكون متاحة خلال:'
                    : 'Your next free consultation will be available in:')
            : (isAr ? 'هذه الميزة تتطلب اشتراك Pro.' : 'This feature requires MedOrbit Pro.');

        panel.hidden = false;
        panel.innerHTML =
            '<div class="voice-paywall__heading">' + heading + '</div>'
            + (nextFreeAt ? '<div class="voice-paywall__countdown" id="voicePaywallCountdown">—</div>' : '')
            + (upgradeAvailable
                ? '<button type="button" class="voice-paywall__upgrade" data-action="upgrade">'
                + (isAr ? 'الترقية إلى Pro' : 'Upgrade to Pro') + '</button>'
                : '');

        if (voicePaywallTimer) clearInterval(voicePaywallTimer);
        if (nextFreeAt) {
            const target = new Date(nextFreeAt).getTime();
            const tick = () => {
                const remaining = target - Date.now();
                const node = document.getElementById('voicePaywallCountdown');
                if (!node) return;
                if (remaining <= 0) {
                    clearInterval(voicePaywallTimer);
                    voicePaywallTimer = null;
                    panel.hidden = true;
                    return;
                }
                node.textContent = formatRemaining(remaining);
            };
            tick();
            voicePaywallTimer = setInterval(tick, 1000);
        }
    }

    function hideVoicePaywall() {
        const panel = document.getElementById('voicePaywall');
        if (panel) panel.hidden = true;
        if (voicePaywallTimer) {
            clearInterval(voicePaywallTimer);
            voicePaywallTimer = null;
        }
    }

    document.addEventListener('click', (event) => {
        if (!event.target.closest('[data-action="upgrade"]')) return;
        if (typeof BillingUI !== 'undefined') {
            BillingUI.openPricing({ returnPath: 'avatar-preview.html' });
        } else {
            window.location.href = 'billing.html';
        }
    });

    function clearError() {
        hideVoicePaywall();
        els.micError.hidden = true;
        els.btnRetryMic.hidden = true;
    }

    function setSpeakingAloud(on) {
        els.statusStrip.classList.toggle('is-speaking-aloud', !!on);
        if (els.voiceStage) els.voiceStage.classList.toggle('is-speaking-aloud', !!on);
    }

    function showSubtitle(text, lang) {
        els.subtitleBar.hidden = false;
        els.subtitleText.textContent = text;
        els.subtitleText.setAttribute('lang', lang || '');
        els.subtitleText.setAttribute('dir', lang === 'ar' ? 'rtl' : 'ltr');
    }

    function hideSubtitle() {
        els.subtitleBar.hidden = true;
        els.subtitleText.textContent = '';
    }

    async function speakReply(text, lang) {
        if (!ttsEnabled) return;
        const startedAt = performance.now();

        VirtualDoctorSTT.setGateMode('bargein');

        const result = await VirtualDoctorTTS.speak(text, lang, {
            onStart: () => { setSpeakingAloud(true); },
            onSubtitle: ({ text: line, index, total }) => {
                showSubtitle(line, lang);
                if (index === 0) {
                    logLine('Speaking ' + total + ' sentence(s), first audio in ' +
                            Math.round(performance.now() - startedAt) + 'ms');
                }
            },
            onError: (detail) => {
                els.ttsWarning.hidden = false;
                logLine('TTS error: ' + (detail.detail || detail.key));
            },
            onEnd: () => { setSpeakingAloud(false); }
        });

        setSpeakingAloud(false);
        hideSubtitle();

        if (result && result.interrupted) logLine('Speech interrupted by patient');
        if (result && result.ok === false) {

            await new Promise((r) => setTimeout(r, 700));
        }
    }

    function onBargeIn() {
        if (!VirtualDoctorTTS.isSpeaking()) return;
        logLine('Barge-in detected — stopping speech');
        VirtualDoctorTTS.stop();
        hideSubtitle();
        setSpeakingAloud(false);
        VirtualDoctorSTT.setGateMode('open');
    }

    function renderSummary(result) {
        const lang = VirtualDoctorSession.getLanguage();
        const profile = result.profile || {};
        const urgency = result.urgencyLevel || 'routine';

        els.urgencyBadge.textContent = tr('consult.urgency.' + urgency, urgency);
        els.urgencyBadge.className = 'urgency-badge urgency-' + urgency;

        const rows = [
            [tr('consult.fieldName', 'Name'), profile.name || '—'],
            [tr('consult.fieldAge', 'Age'), profile.age != null ? String(profile.age) : '—'],
            [tr('consult.fieldComplaint', 'Chief complaint'),
            profile.chief_complaint_description || result.chiefComplaint || '—'],
            [tr('consult.fieldSpecialty', 'Recommended specialty'),
            (lang === 'ar' ? result.specialtyAr : result.specialtyEn) || '—']
        ];
        els.summaryGrid.innerHTML = '';
        rows.forEach(([label, value]) => {
            const dt = document.createElement('dt');
            dt.textContent = label;
            const dd = document.createElement('dd');
            dd.textContent = value;
            els.summaryGrid.appendChild(dt);
            els.summaryGrid.appendChild(dd);
        });

        els.summaryPanel.hidden = false;
        els.summaryPanel.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
    }

    async function offerReport() {
        els.btnDownloadReport.disabled = true;
        const res = await VirtualDoctorSession.requestReport();
        els.btnDownloadReport.disabled = false;

        if (res.ok) {
            els.reportUnavailable.hidden = true;
            logLine('Report ready: ' + res.reportId);
            const a = document.createElement('a');
            a.href = res.downloadUrl;
            a.target = '_blank';
            a.rel = 'noopener';
            a.click();
            return;
        }
        els.reportUnavailable.hidden = false;
        els.btnDownloadReport.disabled = res.reason === 'pdf_unavailable';
        logLine('Report unavailable (' + res.reason + '): ' + (res.detail || ''));
    }

    async function beginConsultation() {
        clearError();
        els.btnStartConsult.disabled = true;
        const unlocked = await VirtualDoctorTTS.unlock();
        if (!unlocked) logLine('Audio autoplay not unlocked; speech may be blocked');

        VirtualDoctorSTT.warmup();
        VirtualDoctorTTS.warmup().then((status) => {
            if (!status) {
                ttsEnabled = false;
                els.ttsWarning.hidden = false;
                logLine('TTS unavailable — continuing with text only');
            }
        });

        const started = await VirtualDoctorSTT.start();
        if (!started) {
            els.btnStartConsult.disabled = false;
            return;
        }

        els.startCard.hidden = true;
        els.consultShell.hidden = false;
        sessionActive = true;

        const lang = (typeof I18n !== 'undefined' && I18n.getLang) ? I18n.getLang() : 'ar';
        VirtualDoctorSTT.setLanguage(lang === 'ar' ? 'ar' : 'en');

        try {
            const res = await VirtualDoctorSession.start(lang === 'ar' ? 'ar' : 'en');
            if (!res || !sessionActive) return;
            VirtualDoctorSTT.setLanguage(res.language);
            logLine('Session ' + res.sessionId.slice(0, 8) + ' started (' + res.language + ')');
        } catch (err) {
            showError({ code: 'engine', key: 'consult.errStart', detail: err.message, fatal: true });
            sessionActive = false;
        }
    }
    async function endConsultation() {
        sessionActive = false;
        VirtualDoctorSTT.stop();
        VirtualDoctorTTS.stop();
        hideSubtitle();
        stopTimer();
        clearError();
        setMicStatus('');
        els.conversation.innerHTML = '';
        els.summaryGrid.innerHTML = '';
        els.summaryPanel.hidden = true;
        els.reportUnavailable.hidden = true;
        els.consultShell.hidden = true;
        els.startCard.hidden = false;
        els.btnStartConsult.disabled = true;
        setStatus('idle');

        const result = await VirtualDoctorSession.end();
        els.btnStartConsult.disabled = false;
        if (result.ended) {
            logLine('Consultation ended');
        } else if (result.reason === 'error') {

            logLine('Consultation ended locally; server cleanup failed: ' + (result.detail || ''));
        }
    }

    function initConsultation() {
        [
            'startCard', 'btnStartConsult', 'startNote', 'consultShell', 'statusStrip',
            'statusLabel', 'statusTimer', 'conversation', 'micStatus', 'micError',
            'micErrorMsg', 'micErrorHelp', 'btnRetryMic', 'micLevelFill',
            'summaryPanel', 'summaryGrid', 'urgencyBadge', 'btnDownloadReport',
            'reportUnavailable', 'log', 'btnEndConsult',
            'subtitleBar', 'subtitleText', 'ttsWarning',
            'voiceStage', 'voiceLabel'
        ].forEach((id) => { els[id] = document.getElementById(id); });

        VirtualDoctorSTT.init({
            onStateChange: (state, detail) => {
                if (!sessionActive) return;
                if (state === 'capturing' || state === 'listening' || state === 'transcribing') {
                    setStatus(state);
                }
                if (detail && detail.stillListening) {
                    setMicStatus(tr('consult.stillListening', 'Still listening — take your time.'));
                } else if (state === 'capturing') {
                    setMicStatus('');
                }
            },
            onLevel: (level, capturing) => {
                els.micLevelFill.style.width = Math.round(level * 100) + '%';
                els.micLevelFill.classList.toggle('is-capturing', !!capturing);

                if (els.voiceStage) {
                    els.voiceStage.style.setProperty('--level', level.toFixed(3));
                }
            },
            onTranscript: (result) => {
                setMicStatus('');
                addBubble('patient', result.text, result.language);
                logLine('Heard (' + result.processingSeconds + 's stt): "' + result.text + '"');
                turnStartedAt = performance.now();
                VirtualDoctorSTT.setGateMode('closed');
                VirtualDoctorSession.submit(result.text);
            },
            onBargeIn: onBargeIn,
            onError: (detail) => showError(detail)
        });

        VirtualDoctorSession.init({
            onState: ({ state }) => {
                setStatus(state);

                if (state === 'listening' && sessionActive) {
                    VirtualDoctorSTT.setGateMode('open');
                }
            },

            onDoctorTurn: ({ text, meta }) => {
                const lang = VirtualDoctorSession.getLanguage();
                addBubble('doctor', text, lang);
                if (meta && meta.elapsedMs) {
                    logLine('Doctor replied in ' + meta.elapsedMs + 'ms (turn ' + meta.turn + ')');
                }
                return speakReply(text, lang);
            },
            onPatientTurn: () => {},
            onComplete: (result) => {
                sessionActive = false;
                VirtualDoctorSTT.stop();
                hideSubtitle();
                setStatus('complete');
                setMicStatus('');
                renderSummary(result);
                offerReport();
                logLine('Consultation complete — urgency=' + result.urgencyLevel);
            },

            onPaywall:({ code, nextFreeAt, upgradeAvailable }) => {
                sessionActive = false;
                VirtualDoctorSTT.stop();
                VirtualDoctorTTS.stop();
                hideSubtitle();
                stopTimer();
                setMicStatus('');

                els.consultShell.hidden = true;
                els.startCard.hidden = false;
                els.btnStartConsult.disabled = false;
                setStatus('idle');

                showVoicePaywall({ code, nextFreeAt, upgradeAvailable });
                if (upgradeAvailable && typeof BillingUI !== 'undefined') {
                    BillingUI.openPricing({
                        returnPath: 'avatar-preview.html' ,
                        reason: code
                    });
                }

                logLine('Consultation blocked [' + code + ']' + (nextFreeAt ? ' until ' + nextFreeAt : ''));
            },

    onResumed: ({ sessionId }) => {
                logLine('Resumed existing consultation ' + sessionId);
            },
            onError: (detail) => {
                showError({ ...detail, code: 'engine', showHelp: false });
                VirtualDoctorSTT.setGateOpen(true);
            }
        });

        els.btnStartConsult.addEventListener('click', beginConsultation);
        els.btnRetryMic.addEventListener('click', () => {
            clearError();
            beginConsultation();
        });
        els.btnDownloadReport.addEventListener('click', offerReport);
        els.btnEndConsult.addEventListener('click', endConsultation);
    }

    document.addEventListener('DOMContentLoaded', () => {
        Layout.init();
        initConsultation();
    });

})();

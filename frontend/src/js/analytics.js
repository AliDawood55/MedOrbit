const Analytics = (() => {

    const charts = {};

let rawStats = null;

    const ROLE_LABEL_KEYS = {
        patient: 'analytics.rolePatient',
        doctor: 'analytics.roleDoctor',
        admin: 'analytics.roleAdmin',
        super_admin: 'analytics.roleSuperAdmin'
    };

    const CLINIC_TYPE_LABEL_KEYS = {
        clinic: 'analytics.clinicTypeClinic',
        hospital: 'analytics.clinicTypeHospital',
        pharmacy: 'analytics.clinicTypePharmacy',
        medical_center: 'analytics.clinicTypeMedicalCenter',
        laboratory: 'analytics.clinicTypeLaboratory',
        radiology: 'analytics.clinicTypeRadiology',
        dental: 'analytics.clinicTypeDental',
        emergency: 'analytics.clinicTypeEmergency',
        optical: 'analytics.clinicTypeOptical',
        vaccination_center: 'analytics.clinicTypeVaccinationCenter'
    };

    const TRIAGE_LABEL_KEYS = {
        emergency: 'analytics.triageEmergency',
        urgent: 'analytics.triageUrgent',
        routine: 'analytics.triageRoutine'
    };

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function label(ar, en) {
        return isAr() ? ar : en;
    }

    function reducedMotion() {
        return typeof Motion !== 'undefined' && Motion.reduced();
    }

    function toNumber(value) {
        const n = Number(value);
        return Number.isFinite(n) ? n : 0;
    }

    function hasCounts(counts) {
        return Array.isArray(counts) && counts.some((n) => toNumber(n) > 0);
    }

    function roleLabel(role) {
        const key = ROLE_LABEL_KEYS[role];
        return key ? t(key) : String(role || '');
    }

    function clinicTypeLabel(type) {
        const key = CLINIC_TYPE_LABEL_KEYS[type];
        return key ? t(key) : String(type || '');
    }

    function triageLabel(level) {
        const key = TRIAGE_LABEL_KEYS[level];
        return key ? t(key) : String(level || '');
    }

function formatWeekLabel(iso) {
        const date = new Date(iso + 'T00:00:00Z');
        if (Number.isNaN(date.getTime())) return iso;
        try {
            return new Intl.DateTimeFormat(isAr() ? 'ar-EG' : 'en-US', {
                month: 'short', day: 'numeric', timeZone: 'UTC'
            }).format(date);
        } catch {
            return iso;
        }
    }

function analyticsSection(key) {
        return rawStats?.analytics?.[key];
    }

function buildSummary(data) {
        const users = data.users || {};
        const appointments = data.appointments || {};
        const records = data.medical_records || {};
        const prescriptions = data.prescriptions || {};
        const ratings = data.ratings || {};

        const rating = ratings.average == null ? null : toNumber(ratings.average);

        return [
            { icon: 'fa-users', tone: 'primary', label: label('إجمالي المستخدمين', 'Total users'), value: toNumber(users.total) },
            { icon: 'fa-user-injured', tone: 'info', label: label('المرضى', 'Patients'), value: toNumber(users.patients) },
            { icon: 'fa-user-doctor', tone: 'info', label: label('الأطباء', 'Doctors'), value: toNumber(users.doctors) },
            { icon: 'fa-calendar-check', tone: 'primary', label: label('إجمالي المواعيد', 'Total appointments'), value: toNumber(appointments.total) },
            { icon: 'fa-circle-check', tone: 'success', label: label('مواعيد مكتملة', 'Completed'), value: toNumber(appointments.completed) },
            { icon: 'fa-clock', tone: 'warning', label: label('مواعيد مجدولة', 'Scheduled'), value: toNumber(appointments.scheduled) },
            { icon: 'fa-circle-xmark', tone: 'danger', label: label('مواعيد ملغاة', 'Cancelled'), value: toNumber(appointments.cancelled) },
            { icon: 'fa-file-medical', tone: 'info', label: label('السجلات الطبية', 'Medical records'), value: toNumber(records.total) },
            { icon: 'fa-prescription-bottle-medical', tone: 'info', label: label('الوصفات الطبية', 'Prescriptions'), value: toNumber(prescriptions.total) },
            {
                icon: 'fa-star', tone: 'warning',
                label: label('متوسط تقييم الأطباء', 'Avg doctor rating'),

                value: rating, text: rating == null ? '—' : rating.toFixed(2)
            }
        ];
    }

    function renderSummary(tiles) {
        const wrap = document.getElementById('analyticsKpis');
        if (!wrap) return;

        if (!Array.isArray(tiles) || !tiles.length) {
            wrap.classList.add('hidden');
            wrap.innerHTML = '';
            return;
        }

        const locale = isAr() ? 'ar-EG' : 'en-US';
        wrap.classList.remove('hidden');
        wrap.innerHTML = tiles.map((tile) => (
            '<div class="analytics-kpi">' +
                '<span class="analytics-kpi-icon tone-' + tile.tone + '"><i class="fas ' + tile.icon + '"></i></span>' +
                '<span class="analytics-kpi-body">' +
                    '<span class="analytics-kpi-value">' +
                        (tile.text != null ? tile.text : Number(tile.value || 0).toLocaleString(locale)) +
                    '</span>' +
                    '<span class="analytics-kpi-label">' + tile.label + '</span>' +
                '</span>' +
            '</div>'
        )).join('');
    }

function themeColors() {
        const cs = getComputedStyle(document.documentElement);
        const v = (name) => cs.getPropertyValue(name).trim();
        return {
            text: v('--text'),
            textMute: v('--text-mute'),
            border: v('--border'),
            primary: v('--primary'),
            secondary: v('--secondary'),
            accent: v('--accent'),
            info: v('--info'),
            danger: v('--danger'),
            success: v('--success'),
            catDoctor: v('--cat-doctor'),
            catPharmacy: v('--cat-pharmacy'),
            catHospital: v('--cat-hospital'),
            catClinic: v('--cat-clinic')
        };
    }

    function palette(colors) {
        return [colors.primary, colors.secondary, colors.accent, colors.info, colors.catDoctor, colors.danger];
    }

    function baseScaleOptions(colors) {
        return {
            grid: { color: colors.border },
            ticks: { color: colors.textMute, font: { size: 11 } }
        };
    }

function toggleOverlay(key, state) {
        const overlay = document.getElementById('overlay' + key);
        if (!overlay) return;

        if (!state) {
            overlay.classList.add('hidden');
            return;
        }

        const icon = overlay.querySelector('i');
        const text = overlay.querySelector('span');
        if (state === 'unavailable') {
            if (icon) icon.className = 'fas fa-triangle-exclamation';
            if (text) text.textContent = t('analytics.sectionUnavailable');
        } else {
            if (icon) icon.className = 'fas fa-plug-circle-exclamation';
            if (text) text.textContent = t('analytics.awaitingData');
        }
        overlay.classList.remove('hidden');
    }

    function destroy(key) {
        if (charts[key]) {
            charts[key].destroy();
            delete charts[key];
        }
    }

function renderAppointmentsOverTime() {
        const section = analyticsSection('appointmentsOverTime');
        destroy('appointments');

        if (!section || section.error) { toggleOverlay('Appointments', 'unavailable'); return; }

        const labels = (section.data?.labels || []).map(formatWeekLabel);
        const counts = section.data?.counts || [];
        const colors = themeColors();

        charts.appointments = new Chart(document.getElementById('chartAppointments'), {
            type: 'bar',
            data: {
                labels,
                datasets: [{
                    label: t('analytics.appointmentsOverTime'),
                    data: counts,
                    backgroundColor: colors.primary
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { display: false } },
                scales: {
                    x: { ...baseScaleOptions(colors), reverse: isAr() },
                    y: { ...baseScaleOptions(colors), beginAtZero: true, ticks: { ...baseScaleOptions(colors).ticks, precision: 0 } }
                }
            }
        });

        toggleOverlay('Appointments', hasCounts(counts) ? null : 'empty');
    }

    function renderUsersByRole() {
        const section = analyticsSection('usersByRole');
        destroy('usersByRole');

        if (!section || section.error) { toggleOverlay('UsersByRole', 'unavailable'); return; }

        const labels = (section.data?.labels || []).map(roleLabel);
        const counts = section.data?.counts || [];
        const colors = themeColors();

        charts.usersByRole = new Chart(document.getElementById('chartUsersByRole'), {
            type: 'doughnut',
            data: {
                labels,
                datasets: [{ data: counts, backgroundColor: palette(colors) }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { position: 'bottom', labels: { color: colors.textMute, font: { size: 11 } } } }
            }
        });

        toggleOverlay('UsersByRole', hasCounts(counts) ? null : 'empty');
    }

    function renderTopSpecialties() {
        const section = analyticsSection('topSpecialties');
        destroy('topSpecialties');

        if (!section || section.error) { toggleOverlay('TopSpecialties', 'unavailable'); return; }

        const items = section.data?.items || [];
        const labels = items.map((i) => label(i.nameAr, i.nameEn));
        const counts = items.map((i) => toNumber(i.count));
        const colors = themeColors();

        charts.topSpecialties = new Chart(document.getElementById('chartTopSpecialties'), {
            type: 'bar',
            data: {
                labels,
                datasets: [{ label: t('analytics.topSpecialties'), data: counts, backgroundColor: colors.primary }]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { display: false } },
                scales: {
                    x: { ...baseScaleOptions(colors), beginAtZero: true, reverse: isAr(), ticks: { ...baseScaleOptions(colors).ticks, precision: 0 } },
                    y: { ...baseScaleOptions(colors) }
                }
            }
        });

        toggleOverlay('TopSpecialties', hasCounts(counts) ? null : 'empty');
    }

    function renderConversationsPerWeek() {
        const section = analyticsSection('conversationsPerWeek');
        destroy('conversations');

        if (!section || section.error) { toggleOverlay('Conversations', 'unavailable'); return; }

        const labels = (section.data?.labels || []).map(formatWeekLabel);
        const counts = section.data?.counts || [];
        const colors = themeColors();

        charts.conversations = new Chart(document.getElementById('chartConversations'), {
            type: 'line',
            data: {
                labels,
                datasets: [{
                    label: t('analytics.conversationsPerWeek'),
                    data: counts,
                    borderColor: colors.success,
                    backgroundColor: colors.success,
                    tension: 0.3,
                    fill: false
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { display: false } },
                scales: {
                    x: { ...baseScaleOptions(colors), reverse: isAr() },
                    y: { ...baseScaleOptions(colors), beginAtZero: true, ticks: { ...baseScaleOptions(colors).ticks, precision: 0 } }
                }
            }
        });

        toggleOverlay('Conversations', hasCounts(counts) ? null : 'empty');
    }

    function renderTriageLevels() {
        const section = analyticsSection('triageLevels');
        destroy('triage');

        if (!section || section.error) { toggleOverlay('Triage', 'unavailable'); return; }

        const rawLabels = section.data?.labels || [];
        const labels = rawLabels.map(triageLabel);
        const counts = section.data?.counts || [];
        const colors = themeColors();
        const levelColor = { emergency: colors.danger, urgent: colors.accent, routine: colors.success };

        charts.triage = new Chart(document.getElementById('chartTriage'), {
            type: 'doughnut',
            data: {
                labels,
                datasets: [{
                    data: counts,
                    backgroundColor: rawLabels.map((lvl) => levelColor[lvl] || colors.primary)
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { position: 'bottom', labels: { color: colors.textMute, font: { size: 11 } } } }
            }
        });

        toggleOverlay('Triage', hasCounts(counts) ? null : 'empty');
    }

    function renderClinicTypes() {
        const section = analyticsSection('clinicTypes');
        destroy('clinicTypes');

        if (!section || section.error) { toggleOverlay('ClinicTypes', 'unavailable'); return; }

        const labels = (section.data?.labels || []).map(clinicTypeLabel);
        const counts = section.data?.counts || [];
        const colors = themeColors();

        charts.clinicTypes = new Chart(document.getElementById('chartClinicTypes'), {
            type: 'pie',
            data: {
                labels,
                datasets: [{ data: counts, backgroundColor: palette(colors) }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { position: 'bottom', labels: { color: colors.textMute, font: { size: 11 } } } }
            }
        });

        toggleOverlay('ClinicTypes', hasCounts(counts) ? null : 'empty');
    }

    function renderAll() {
        if (!rawStats) return;
        renderSummary(buildSummary(rawStats));
        renderAppointmentsOverTime();
        renderUsersByRole();
        renderTopSpecialties();
        renderConversationsPerWeek();
        renderTriageLevels();
        renderClinicTypes();
    }

let lastLoadError = undefined;

    function loadErrorMessage(err) {
        if (!err || err.status == null) return t('analytics.loadErrorNetwork');
        if (err.status === 401) return t('analytics.loadErrorUnauthorized');
        if (err.status === 403) return t('analytics.loadErrorForbidden');
        if (err.status >= 500) return t('analytics.loadErrorServer');
        return t('common.error');
    }

    function showLoadError(err) {
        lastLoadError = err;
        document.getElementById('analyticsKpis')?.classList.add('hidden');
        document.getElementById('analyticsGrid')?.classList.add('hidden');
        const banner = document.getElementById('analyticsLoadError');
        const msg = document.getElementById('analyticsLoadErrorMessage');
        if (msg) msg.textContent = loadErrorMessage(err);
        banner?.classList.remove('hidden');
    }

    function hideLoadError() {
        lastLoadError = undefined;
        document.getElementById('analyticsLoadError')?.classList.add('hidden');
        document.getElementById('analyticsGrid')?.classList.remove('hidden');
    }

    function onLanguageChanged() {
        renderAll();
        if (lastLoadError !== undefined) {
            const msg = document.getElementById('analyticsLoadErrorMessage');
            if (msg) msg.textContent = loadErrorMessage(lastLoadError);
        }
    }

async function loadStats() {
        try {
            const res = await API.analytics.dashboardStats();
            rawStats = res?.data || null;
            hideLoadError();
            renderAll();
        } catch (err) {
            console.error('Analytics: failed to load GET /api/dashboard/stats', err);
            rawStats = null;
            showLoadError(err);
        }
    }

async function init() {
        if (!API.requireAuth()) return;

        const state = await AuthGate.verifySession();
        if (state !== 'valid') return;

        const user = AuthGate.getVerifiedUser();
        const isAdmin = ['admin', 'super_admin'].includes(user?.role);

        document.getElementById('analyticsLoading').classList.add('hidden');

        if (!isAdmin) {
            document.getElementById('analyticsRestricted').classList.remove('hidden');
            return;
        }

        document.getElementById('analyticsContent').classList.remove('hidden');
        Motion.staggerIn(document.getElementById('analyticsGrid'), '.chart-card');

        await loadStats();

        document.getElementById('themeToggle')?.addEventListener('click', () => renderAll());
        document.getElementById('analyticsRetryBtn')?.addEventListener('click', () => loadStats());
        window.addEventListener('languageChanged', onLanguageChanged);
    }

    return { init };

})();

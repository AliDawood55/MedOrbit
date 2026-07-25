/**
 * MedOrbit v2 - Analytics
 * GET /api/dashboard/stats does not exist yet (see BACKEND_NEEDED.md) —
 * every chart below is built with a genuinely empty dataset (no hardcoded
 * arrays, no random numbers) and shows an explicit "awaiting backend data"
 * overlay. The fetch is written to work the moment the endpoint lands:
 * see the expected shape documented next to API.analytics in api.js.
 * Restricted to role === 'admin' (checked server-side via a fresh
 * GET /users/me call, not the cached login-time user object).
 */
const Analytics = (() => {

    const charts = {};
    let statsData = null;

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function reducedMotion() {
        return typeof Motion !== 'undefined' && Motion.reduced();
    }

    // ================= THEME =================

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

    function toggleOverlay(key, show) {
        document.getElementById('overlay' + key)?.classList.toggle('hidden', !show);
    }

    function destroy(key) {
        if (charts[key]) {
            charts[key].destroy();
            delete charts[key];
        }
    }

    // ================= CHART RENDERERS =================
    // Each one is called with only its own slice of statsData (or
    // undefined) — never touches hardcoded numbers. An empty/missing
    // section renders an empty chart frame + the overlay.

    function renderAppointmentsOverTime(section) {
        const colors = themeColors();
        const labels = section?.labels || [];
        const counts = section?.counts || [];

        destroy('appointments');
        charts.appointments = new Chart(document.getElementById('chartAppointments'), {
            type: 'line',
            data: {
                labels,
                datasets: [{
                    label: t('analytics.appointmentsOverTime'),
                    data: counts,
                    borderColor: colors.primary,
                    backgroundColor: colors.primary + '26',
                    fill: true,
                    tension: 0.3,
                    pointRadius: 3
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { display: false } },
                scales: {
                    x: { ...baseScaleOptions(colors), reverse: isAr() },
                    y: { ...baseScaleOptions(colors), beginAtZero: true }
                }
            }
        });

        toggleOverlay('Appointments', labels.length === 0);
    }

    function renderUsersByRole(section) {
        const colors = themeColors();
        const labels = section?.labels || [];
        const counts = section?.counts || [];

        destroy('usersByRole');
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

        toggleOverlay('UsersByRole', labels.length === 0);
    }

    function renderTopSpecialties(section) {
        const colors = themeColors();
        const labels = section?.labels || [];
        const counts = section?.counts || [];

        destroy('topSpecialties');
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
                    x: { ...baseScaleOptions(colors), beginAtZero: true, reverse: isAr() },
                    y: { ...baseScaleOptions(colors) }
                }
            }
        });

        toggleOverlay('TopSpecialties', labels.length === 0);
    }

    function renderConversationsPerWeek(section) {
        const colors = themeColors();
        const labels = section?.labels || [];
        const counts = section?.counts || [];

        destroy('conversations');
        charts.conversations = new Chart(document.getElementById('chartConversations'), {
            type: 'bar',
            data: {
                labels,
                datasets: [{ label: t('analytics.conversationsPerWeek'), data: counts, backgroundColor: colors.info }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { display: false } },
                scales: {
                    x: { ...baseScaleOptions(colors), reverse: isAr() },
                    y: { ...baseScaleOptions(colors), beginAtZero: true }
                }
            }
        });

        toggleOverlay('Conversations', labels.length === 0);
    }

    function renderTriageLevels(section) {
        const colors = themeColors();
        const labels = section?.labels || [];

        destroy('triage');
        charts.triage = new Chart(document.getElementById('chartTriage'), {
            type: 'bar',
            data: {
                labels,
                datasets: [
                    { label: t('analytics.triageEmergency'), data: section?.emergency || [], backgroundColor: colors.danger },
                    { label: t('analytics.triageUrgent'), data: section?.urgent || [], backgroundColor: colors.accent },
                    { label: t('analytics.triageRoutine'), data: section?.routine || [], backgroundColor: colors.success }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { position: 'bottom', labels: { color: colors.textMute, font: { size: 11 } } } },
                scales: {
                    x: { ...baseScaleOptions(colors), stacked: true, reverse: isAr() },
                    y: { ...baseScaleOptions(colors), stacked: true, beginAtZero: true }
                }
            }
        });

        toggleOverlay('Triage', labels.length === 0);
    }

    function renderClinicTypes(section) {
        const colors = themeColors();
        const labels = section?.labels || [];
        const counts = section?.counts || [];

        destroy('clinicTypes');
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

        toggleOverlay('ClinicTypes', labels.length === 0);
    }

    function renderAll() {
        renderAppointmentsOverTime(statsData?.appointmentsOverTime);
        renderUsersByRole(statsData?.usersByRole);
        renderTopSpecialties(statsData?.topSpecialties);
        renderConversationsPerWeek(statsData?.conversationsPerWeek);
        renderTriageLevels(statsData?.triageLevels);
        renderClinicTypes(statsData?.clinicTypes);
    }

    // ================= LOAD =================

    async function loadStats() {
        try {
            const res = await API.analytics.dashboardStats();
            statsData = res?.data || null;
        } catch (err) {
            console.info('Analytics: GET /api/dashboard/stats is not available yet (expected — see BACKEND_NEEDED.md)', err);
            statsData = null;
        }
        renderAll();
    }

    // ================= INIT =================

    async function init() {
        if (!API.requireAuth()) return;

        let isAdmin = false;
        try {
            const res = await API.users.me();
            isAdmin = res?.data?.role === 'admin';
        } catch (err) {
            console.error('Analytics: failed to verify role', err);
            isAdmin = false;
        }

        document.getElementById('analyticsLoading').classList.add('hidden');

        if (!isAdmin) {
            document.getElementById('analyticsRestricted').classList.remove('hidden');
            return;
        }

        document.getElementById('analyticsContent').classList.remove('hidden');
        Motion.staggerIn(document.getElementById('analyticsGrid'), '.chart-card');

        await loadStats();

        document.getElementById('themeToggle')?.addEventListener('click', () => renderAll());
        window.addEventListener('languageChanged', renderAll);
    }

    return { init };

})();

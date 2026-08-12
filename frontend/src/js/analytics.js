/**
 * MedOrbit v2 - Analytics
 * Wires analytics.html to the real admin endpoint:
 * GET /api/dashboard/stats.
 */
const Analytics = (() => {

    const charts = {};
    let statsData = null;
    // The untouched payload, kept so the summary tiles can be rebuilt in the
    // other language without a second network call.
    let rawStats = null;

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

    function isLegacyChartPayload(data) {
        return !!(
            data &&
            (
                data.appointmentsOverTime ||
                data.usersByRole ||
                data.topSpecialties ||
                data.conversationsPerWeek ||
                data.triageLevels ||
                data.clinicTypes
            )
        );
    }

    function section(labels, counts) {
        return {
            labels,
            counts: counts.map(toNumber)
        };
    }

    /**
     * Map the live GET /api/dashboard/stats payload onto this page's charts.
     *
     * The endpoint returns aggregate totals only:
     *   { users:{total,patients,doctors},
     *     appointments:{total,completed,cancelled,scheduled},
     *     medical_records:{total}, prescriptions:{total}, ratings:{average} }
     *
     * Exactly ONE of the six charts can be filled honestly from that. The
     * others need dimensions the endpoint does not have (a time axis, a
     * per-specialty breakdown, chatbot data, triage levels, facility types),
     * so they keep their own "awaiting backend data" overlay rather than being
     * fed unrelated numbers under a title that would misdescribe them.
     *
     * The real totals that don't fit any chart are shown truthfully in the
     * summary tiles instead — see buildSummary().
     */
    function normalizeStats(data) {
        if (!data) return null;
        // If the backend ever starts returning the richer per-chart shape
        // documented in api.js, pass it straight through.
        if (isLegacyChartPayload(data)) return data;

        const users = data.users || {};

        const patients = toNumber(users.patients);
        const doctors = toNumber(users.doctors);
        const totalUsers = toNumber(users.total);
        // Anything that isn't a patient or a doctor (admins, etc.). Clamped so
        // a partial payload can never produce a negative slice.
        const otherUsers = Math.max(totalUsers - patients - doctors, 0);

        return {
            // --- backed by real data ---
            usersByRole: section(
                [
                    label('مرضى', 'Patients'),
                    label('أطباء', 'Doctors'),
                    label('أخرى', 'Other')
                ],
                [patients, doctors, otherUsers]
            ),

            // --- no source in this endpoint: keep the empty state ---
            appointmentsOverTime: null,   // totals only, no time series
            topSpecialties: null,         // no per-specialty breakdown
            conversationsPerWeek: null,   // chatbot usage is not reported here
            triageLevels: null,           // triage levels are not reported here
            clinicTypes: null             // facility types are not reported here
        };
    }

    // ================= SUMMARY TILES =================

    /**
     * The scalar totals the endpoint really does return. These are shown as
     * plain labelled tiles, which is the only presentation that describes them
     * accurately — several of them (record counts, average rating) have no
     * meaningful chart on this page.
     */
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
                // null when no doctor has been rated yet — show a dash, not 0.
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

    function renderAppointmentsOverTime(sectionData) {
        const colors = themeColors();
        const labels = sectionData?.labels || [];
        const counts = sectionData?.counts || [];

        destroy('appointments');
        charts.appointments = new Chart(document.getElementById('chartAppointments'), {
            type: 'bar',
            data: {
                labels,
                datasets: [{
                    label: t('analytics.appointmentsOverTime'),
                    data: counts,
                    backgroundColor: [colors.primary, colors.success, colors.danger]
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

        toggleOverlay('Appointments', !hasCounts(counts));
    }

    function renderUsersByRole(sectionData) {
        const colors = themeColors();
        const labels = sectionData?.labels || [];
        const counts = sectionData?.counts || [];

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

        toggleOverlay('UsersByRole', !hasCounts(counts));
    }

    function renderTopSpecialties(sectionData) {
        const colors = themeColors();
        const labels = sectionData?.labels || [];
        const counts = sectionData?.counts || [];

        destroy('topSpecialties');
        charts.topSpecialties = new Chart(document.getElementById('chartTopSpecialties'), {
            type: 'bar',
            data: {
                labels,
                datasets: [{ label: t('analytics.topSpecialties'), data: counts, backgroundColor: [colors.primary, colors.info] }]
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

        toggleOverlay('TopSpecialties', !hasCounts(counts));
    }

    function renderConversationsPerWeek(sectionData) {
        const colors = themeColors();
        const labels = sectionData?.labels || [];
        const counts = sectionData?.counts || [];

        destroy('conversations');
        charts.conversations = new Chart(document.getElementById('chartConversations'), {
            type: 'doughnut',
            data: {
                labels,
                datasets: [{ data: counts, backgroundColor: [colors.success, colors.border] }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { position: 'bottom', labels: { color: colors.textMute, font: { size: 11 } } } }
            }
        });

        toggleOverlay('Conversations', !hasCounts(counts));
    }

    function renderTriageLevels(sectionData) {
        const colors = themeColors();
        const labels = sectionData?.labels || [];

        destroy('triage');
        charts.triage = new Chart(document.getElementById('chartTriage'), {
            type: 'bar',
            data: {
                labels,
                datasets: [
                    { label: t('analytics.triageEmergency'), data: sectionData?.emergency || [], backgroundColor: colors.danger },
                    { label: t('analytics.triageUrgent'), data: sectionData?.urgent || [], backgroundColor: colors.accent },
                    { label: t('analytics.triageRoutine'), data: sectionData?.routine || [], backgroundColor: colors.success }
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

    function renderClinicTypes(sectionData) {
        const colors = themeColors();
        const labels = sectionData?.labels || [];
        const counts = sectionData?.counts || [];

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

        toggleOverlay('ClinicTypes', !hasCounts(counts));
    }

    function renderAll() {
        // Rebuilt on every render so the tiles follow the language toggle.
        // Only the aggregate payload has scalars to show; the richer per-chart
        // shape has none, and a failed load has nothing at all.
        renderSummary(rawStats && !isLegacyChartPayload(rawStats) ? buildSummary(rawStats) : null);
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
            rawStats = res?.data || null;
            statsData = normalizeStats(rawStats);
        } catch (err) {
            console.error('Analytics: failed to load GET /api/dashboard/stats', err);
            rawStats = null;
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
            isAdmin = ['admin', 'super_admin'].includes(res?.data?.role);
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

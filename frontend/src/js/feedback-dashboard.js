/**
 * MedOrbit v2 - Home Feedback Dashboard
 * Wires the bottom section of home.html to GET /api/feedback/stats:
 * two Chart.js charts (rating distribution, category averages), a KPI
 * strip, and a continuous marquee of users who left feedback. Polls every
 * 5s so newly submitted feedback (from feedback.html) shows up live
 * without a page reload.
 */
const FeedbackDashboard = (() => {

    const POLL_MS = 5000;

    const charts = {};
    let pollTimer = null;
    let lastUserKey = null;

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function toNumber(value) {
        const n = Number(value);
        return Number.isFinite(n) ? n : 0;
    }

    function reducedMotion() {
        return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
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
            secondary: v('--secondary') || v('--info'),
            accent: v('--accent'),
            info: v('--info'),
            success: v('--success')
        };
    }

    function baseScaleOptions(colors) {
        return {
            grid: { color: colors.border },
            ticks: { color: colors.textMute, font: { size: 11 } }
        };
    }

    function destroy(key) {
        if (charts[key]) {
            charts[key].destroy();
            delete charts[key];
        }
    }

    // ================= KPI STRIP =================

    function renderKpis(data) {
        const wrap = document.getElementById('feedbackDashKpis');
        if (!wrap) return;

        const total = toNumber(data?.total);
        const avg = data?.averageRating == null ? null : toNumber(data.averageRating);
        const yes = toNumber(data?.recommend?.yes);
        const no = toNumber(data?.recommend?.no);
        const recommendTotal = yes + no;
        const recommendPct = recommendTotal > 0 ? Math.round((yes / recommendTotal) * 100) : null;

        const locale = isAr() ? 'ar-EG' : 'en-US';

        const tiles = [
            { icon: 'fa-comment-dots', label: t('feedbackDash.totalFeedback'), text: total.toLocaleString(locale) },
            { icon: 'fa-star', label: t('feedbackDash.averageRating'), text: avg == null ? '—' : avg.toFixed(1) },
            { icon: 'fa-thumbs-up', label: t('feedbackDash.wouldRecommend'), text: recommendPct == null ? '—' : recommendPct + '%' }
        ];

        wrap.innerHTML = tiles.map((tile) => (
            '<div class="feedback-dash-kpi">' +
                '<span class="feedback-dash-kpi-icon"><i class="fas ' + tile.icon + '"></i></span>' +
                '<span class="feedback-dash-kpi-body">' +
                    '<span class="feedback-dash-kpi-value">' + tile.text + '</span>' +
                    '<span class="feedback-dash-kpi-label">' + tile.label + '</span>' +
                '</span>' +
            '</div>'
        )).join('');
    }

    // ================= CHARTS =================

    function renderRatingChart(ratingDistribution) {
        const colors = themeColors();
        const rows = Array.isArray(ratingDistribution) ? ratingDistribution : [];
        const labels = rows.map((row) => row.rating + ' ' + t('feedbackDash.stars'));
        const counts = rows.map((row) => toNumber(row.count));

        if (charts.ratings) {
            charts.ratings.data.labels = labels;
            charts.ratings.data.datasets[0].data = counts;
            charts.ratings.data.datasets[0].backgroundColor = colors.primary;
            charts.ratings.options.scales.x.ticks.color = colors.textMute;
            charts.ratings.options.scales.y.ticks.color = colors.textMute;
            charts.ratings.update();
            return;
        }

        const canvas = document.getElementById('chartFeedbackRatings');
        if (!canvas || typeof Chart === 'undefined') return;

        charts.ratings = new Chart(canvas, {
            type: 'bar',
            data: {
                labels,
                datasets: [{ label: t('feedbackDash.ratingDistribution'), data: counts, backgroundColor: colors.primary, borderRadius: 6 }]
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
    }

    function renderCategoryChart(categoryAverages) {
        const colors = themeColors();
        const cat = categoryAverages || {};
        const labels = [
            t('feedbackDash.categoryChatbot'),
            t('feedbackDash.categoryClinics'),
            t('feedbackDash.categoryBooking'),
            t('feedbackDash.categoryDesign')
        ];
        const values = [cat.chatbot, cat.clinics, cat.booking, cat.design].map((v) => (v == null ? 0 : toNumber(v)));

        if (charts.categories) {
            charts.categories.data.labels = labels;
            charts.categories.data.datasets[0].data = values;
            charts.categories.data.datasets[0].backgroundColor = [colors.primary, colors.info, colors.accent, colors.success];
            charts.categories.options.scales.x.ticks.color = colors.textMute;
            charts.categories.options.scales.y.ticks.color = colors.textMute;
            charts.categories.update();
            return;
        }

        const canvas = document.getElementById('chartFeedbackCategories');
        if (!canvas || typeof Chart === 'undefined') return;

        charts.categories = new Chart(canvas, {
            type: 'bar',
            data: {
                labels,
                datasets: [{
                    label: t('feedbackDash.categoryAverages'),
                    data: values,
                    backgroundColor: [colors.primary, colors.info, colors.accent, colors.success],
                    borderRadius: 6
                }]
            },
            options: {
                indexAxis: 'y',
                responsive: true,
                maintainAspectRatio: false,
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: { legend: { display: false } },
                scales: {
                    x: { ...baseScaleOptions(colors), beginAtZero: true, max: 5, reverse: isAr() },
                    y: { ...baseScaleOptions(colors) }
                }
            }
        });
    }

    // ================= USERS MARQUEE =================

    function displayName(user) {
        const name = isAr() ? (user.nameAr || user.nameEn) : (user.nameEn || user.nameAr);
        return name || (isAr() ? 'مستخدم' : 'User');
    }

    function marqueeItemHtml(user) {
        const name = escapeHtml(displayName(user));
        const avatar = user.avatarUrl
            ? '<img class="feedback-marquee-avatar" src="' + escapeHtml(API.getOrigin() + user.avatarUrl) + '" alt="">'
            : '<span class="feedback-marquee-avatar-placeholder"></span>';

        return (
            '<div class="feedback-marquee-item">' +
                avatar +
                '<span class="feedback-marquee-name">' + name + '</span>' +
            '</div>'
        );
    }

    function renderMarquee(users) {
        const wrap = document.getElementById('feedbackMarquee');
        const track = document.getElementById('feedbackMarqueeTrack');
        const empty = document.getElementById('feedbackDashEmpty');
        if (!wrap || !track) return;

        const list = Array.isArray(users) ? users : [];

        if (!list.length) {
            wrap.classList.add('hidden');
            empty?.classList.remove('hidden');
            track.innerHTML = '';
            lastUserKey = '';
            return;
        }

        // Rebuilding the track resets the CSS animation, so skip it when the
        // visible set (and language, which changes the rendered name) hasn't
        // actually changed — keeps the scroll smooth across each 5s poll.
        const key = (isAr() ? 'ar:' : 'en:') + list.map((u) => u.id).join(',');
        if (key === lastUserKey) return;
        lastUserKey = key;

        wrap.classList.remove('hidden');
        empty?.classList.add('hidden');

        // Duplicated once so `translateX(-50%)` loops seamlessly.
        const itemsHtml = list.map(marqueeItemHtml).join('');
        track.innerHTML = itemsHtml + itemsHtml;
    }

    // ================= LOAD =================

    async function loadStats() {
        try {
            const res = await API.feedback.stats();
            const data = res?.data || null;

            renderKpis(data);
            renderRatingChart(data?.ratingDistribution);
            renderCategoryChart(data?.categoryAverages);
            renderMarquee(data?.users);
        } catch (err) {
            console.error('FeedbackDashboard: failed to load GET /api/feedback/stats', err);
        }
    }

    function rerenderStatic() {
        // Language/theme change: force a full chart + marquee rebuild.
        destroy('ratings');
        destroy('categories');
        lastUserKey = null;
        loadStats();
    }

    // ================= INIT =================

    function init() {
        if (!document.getElementById('feedbackDashKpis')) return;

        loadStats();

        pollTimer = window.setInterval(loadStats, POLL_MS);

        document.getElementById('themeToggle')?.addEventListener('click', rerenderStatic);
        window.addEventListener('languageChanged', rerenderStatic);
        window.addEventListener('beforeunload', () => {
            if (pollTimer) window.clearInterval(pollTimer);
        });
    }

    return { init };

})();

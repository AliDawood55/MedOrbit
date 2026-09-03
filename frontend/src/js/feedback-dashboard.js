const FeedbackDashboard = (() => {

    const POLL_MS = 60_000;

    const charts = {};
    let pollTimer = null;
    let loadRequest = null;
    let lastLoadedAt = 0;
    let lastData = null;
    let lastUserKey = null;
    let initialized = false;

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

function themeColors() {
        const cs = getComputedStyle(document.documentElement);
        const v = (name) => cs.getPropertyValue(name).trim();
        return {
            text: v('--text'),
            textMute: v('--text-mute'),
            border: v('--border'),
            bgCard: v('--bg-card'),
            primary: v('--primary'),
            secondary: v('--secondary') || v('--info'),
            accent: v('--accent'),
            info: v('--info'),
            success: v('--success'),

primaryRamp: [v('--primary-50'), v('--primary-100'), v('--primary-light'), v('--primary'), v('--primary-dark')]
        };
    }

function circularLegend(colors, formatItem) {
        return {
            position: 'bottom',
            labels: {
                color: colors.text,
                usePointStyle: true,
                pointStyle: 'circle',
                padding: 14,
                font: { size: 12 },
                generateLabels(chart) {
                    const { labels, datasets } = chart.data;
                    const data = datasets[0]?.data || [];
                    const bg = datasets[0]?.backgroundColor || [];
                    return labels.map((label, i) => ({
                        text: formatItem(label, data[i], data),
                        fillStyle: bg[i],
                        strokeStyle: bg[i],
                        fontColor: colors.text,
                        index: i
                    }));
                }
            }
        };
    }

    function destroy(key) {
        if (charts[key]) {
            charts[key].destroy();
            delete charts[key];
        }
    }

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

function renderRatingChart(ratingDistribution) {
        const colors = themeColors();
        const rows = Array.isArray(ratingDistribution) ? ratingDistribution : [];
        const labels = rows.map((row) => row.rating + ' ' + t('feedbackDash.stars'));
        const counts = rows.map((row) => toNumber(row.count));
        const bg = colors.primaryRamp;

        if (charts.ratings) {
            charts.ratings.data.labels = labels;
            charts.ratings.data.datasets[0].data = counts;
            charts.ratings.data.datasets[0].backgroundColor = bg;
            charts.ratings.data.datasets[0].borderColor = colors.bgCard;
            charts.ratings.options.plugins.legend.labels.color = colors.text;
            charts.ratings.update();
            return;
        }

        const canvas = document.getElementById('chartFeedbackRatings');
        if (!canvas || typeof Chart === 'undefined') return;

        charts.ratings = new Chart(canvas, {
            type: 'doughnut',
            data: {
                labels,
                datasets: [{
                    label: t('feedbackDash.ratingDistribution'),
                    data: counts,
                    backgroundColor: bg,
                    borderColor: colors.bgCard,
                    borderWidth: 2,
                    hoverOffset: 6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: '62%',
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: {
                    legend: circularLegend(colors, (label, value, all) => {
                        const total = all.reduce((sum, n) => sum + n, 0);
                        const pct = total > 0 ? Math.round((value / total) * 100) : 0;
                        return label + ' — ' + value + ' (' + pct + '%)';
                    }),
                    tooltip: {
                        callbacks: {
                            label(ctx) {
                                const total = ctx.dataset.data.reduce((sum, n) => sum + n, 0);
                                const pct = total > 0 ? Math.round((ctx.parsed / total) * 100) : 0;
                                return ctx.label + ': ' + ctx.parsed + ' (' + pct + '%)';
                            }
                        }
                    }
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
        const bg = [colors.primary, colors.info, colors.accent, colors.success];

        if (charts.categories) {
            charts.categories.data.labels = labels;
            charts.categories.data.datasets[0].data = values;
            charts.categories.data.datasets[0].backgroundColor = bg;
            charts.categories.data.datasets[0].borderColor = colors.bgCard;
            charts.categories.options.plugins.legend.labels.color = colors.text;
            charts.categories.update();
            return;
        }

        const canvas = document.getElementById('chartFeedbackCategories');
        if (!canvas || typeof Chart === 'undefined') return;

        charts.categories = new Chart(canvas, {
            type: 'doughnut',
            data: {
                labels,
                datasets: [{
                    label: t('feedbackDash.categoryAverages'),
                    data: values,
                    backgroundColor: bg,
                    borderColor: colors.bgCard,
                    borderWidth: 2,
                    hoverOffset: 6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: '62%',
                animation: reducedMotion() ? false : { duration: 250 },
                plugins: {

legend: circularLegend(colors, (label, value) => label + ' — ' + value.toFixed(1) + '/5'),
                    tooltip: {
                        callbacks: {
                            label(ctx) { return ctx.label + ': ' + ctx.parsed.toFixed(1) + '/5'; }
                        }
                    }
                }
            }
        });
    }

function displayName(user) {
        const name = isAr() ? (user.nameAr || user.nameEn) : (user.nameEn || user.nameAr);
        return name || (isAr() ? 'مستخدم' : 'User');
    }

    function marqueeItemHtml(user) {
        const name = escapeHtml(displayName(user));
        const avatar = user.avatarUrl
            ? '<img class="feedback-marquee-avatar" src="' + escapeHtml(API.assetUrl(user.avatarUrl)) + '" alt="">'
            : '<span class="feedback-marquee-avatar-placeholder"></span>';

        return (
            '<a class="feedback-marquee-item" href="feedback-review.html?reviewer=' + encodeURIComponent(user.id) + '">' +
                avatar +
                '<span class="feedback-marquee-name">' + name + '</span>' +
                '<i class="fas fa-arrow-up-right-from-square feedback-marquee-link-icon" aria-hidden="true"></i>' +
            '</a>'
        );
    }

    function renderMarquee(users) {
        const wrap = document.getElementById('feedbackMarquee');
        const track = document.getElementById('feedbackMarqueeTrack');
        const empty = document.getElementById('feedbackDashEmpty');
        const section = wrap?.closest('.feedback-dash-users');
        if (!wrap || !track) return;

if (!Array.isArray(users)) {
            section?.classList.add('hidden');
            track.innerHTML = '';
            lastUserKey = '';
            return;
        }
        section?.classList.remove('hidden');

        const list = users;

        if (!list.length) {
            wrap.classList.add('hidden');
            empty?.classList.remove('hidden');
            track.innerHTML = '';
            lastUserKey = '';
            return;
        }

const key = (isAr() ? 'ar:' : 'en:') + list.map((u) => u.id).join(',');
        if (key === lastUserKey) return;
        lastUserKey = key;

        wrap.classList.remove('hidden');
        empty?.classList.add('hidden');

const itemsHtml = list.map(marqueeItemHtml).join('');
        track.innerHTML = itemsHtml + itemsHtml;
    }

function renderData(data) {
        renderKpis(data);
        renderRatingChart(data?.ratingDistribution);
        renderCategoryChart(data?.categoryAverages);
        renderMarquee(data?.users);
    }

    function stopPolling() {
        if (pollTimer) window.clearTimeout(pollTimer);
        pollTimer = null;
    }

    function schedulePoll(delay = POLL_MS) {
        stopPolling();
        if (document.hidden) return;
        pollTimer = window.setTimeout(loadStats, delay);
    }

    async function loadStats() {
        if (loadRequest) return loadRequest;

        loadRequest = (async () => {
            let nextDelay = POLL_MS;
            try {
                const res = await API.feedback.stats();
                lastData = res?.data || null;
                renderData(lastData);
            } catch (err) {
                if (err.status === 429 && err.retryAfterSeconds) {
                    nextDelay = Math.max(nextDelay, err.retryAfterSeconds * 1000);
                }
                console.error('FeedbackDashboard: failed to load GET /api/feedback/stats', err);
            } finally {
                lastLoadedAt = Date.now();
                loadRequest = null;
                schedulePoll(nextDelay);
            }
        })();

        return loadRequest;
    }

    function rerenderStatic() {

        destroy('ratings');
        destroy('categories');
        lastUserKey = null;
        if (lastData) renderData(lastData);
    }

function init() {
        if (initialized) return;
        initialized = true;
        if (!document.getElementById('feedbackDashKpis')) return;

        loadStats();

        document.getElementById('themeToggle')?.addEventListener('click', rerenderStatic);
        window.addEventListener('languageChanged', rerenderStatic);
        document.addEventListener('visibilitychange', () => {
            if (document.hidden) {
                stopPolling();
                return;
            }
            const elapsed = Date.now() - lastLoadedAt;
            if (!lastLoadedAt || elapsed >= POLL_MS) loadStats();
            else schedulePoll(POLL_MS - elapsed);
        });
        window.addEventListener('beforeunload', stopPolling);
    }

    return { init };

})();

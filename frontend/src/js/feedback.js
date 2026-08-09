/**
 * MedOrbit v2 - Feedback
 * POST /api/feedback (backend/src/routes/feedback.routes.js) — any
 * authenticated user, user_id resolved server-side from the JWT.
 */
const Feedback = (() => {

    let recommendValue = null; // 'yes' | 'no' | null (optional)

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    // ================= STAR RATING WIDGET =================

    function paintStars(widget, upTo) {
        widget.querySelectorAll('.star-btn').forEach((btn) => {
            const val = Number(btn.dataset.star);
            btn.classList.toggle('filled', val <= upTo);
        });
    }

    function updateRatingLabels() {
        document.querySelectorAll('.star-btn').forEach((button) => {
            button.setAttribute(
                'aria-label',
                t('feedback.starLabel').replace('{rating}', button.dataset.star)
            );
        });
    }

    function initStarWidget(widget) {
        const buttons = widget.querySelectorAll('.star-btn');
        widget.setAttribute('role', 'radiogroup');

        buttons.forEach((btn) => {
            const val = Number(btn.dataset.star);
            btn.setAttribute('aria-label', t('feedback.starLabel').replace('{rating}', String(val)));
            btn.setAttribute('aria-pressed', 'false');

            btn.addEventListener('mouseenter', () => paintStars(widget, val));
            btn.addEventListener('click', () => {
                widget.dataset.value = String(val);
                widget.classList.remove('required-empty');
                paintStars(widget, val);
                buttons.forEach((option) => {
                    option.setAttribute('aria-pressed', String(option === btn));
                });
            });
        });

        widget.addEventListener('mouseleave', () => {
            paintStars(widget, Number(widget.dataset.value) || 0);
        });
    }

    // ================= RECOMMEND TOGGLE =================

    function initRecommendToggle() {
        const wrap = document.getElementById('recommendToggle');
        wrap.querySelectorAll('.recommend-btn').forEach((btn) => {
            btn.setAttribute('aria-pressed', 'false');
            btn.addEventListener('click', () => {
                const val = btn.dataset.value;
                if (recommendValue === val) {
                    // Click again to deselect — this field is optional.
                    recommendValue = null;
                } else {
                    recommendValue = val;
                }
                wrap.querySelectorAll('.recommend-btn').forEach((b) => {
                    b.classList.toggle('active', b.dataset.value === recommendValue);
                    b.setAttribute('aria-pressed', String(b.dataset.value === recommendValue));
                });
            });
        });
    }

    // ================= COMMENT CHAR COUNT =================

    function initCommentCounter() {
        const input = document.getElementById('commentInput');
        const counter = document.getElementById('charCount');
        input.addEventListener('input', () => {
            counter.textContent = String(input.value.length);
        });
    }

    // ================= SUBMIT =================

    function collectFormData() {
        return {
            overallRating: Number(document.getElementById('overallStars').dataset.value) || 0,
            categoryRatings: {
                chatbot: Number(document.querySelector('[data-category="chatbot"]').dataset.value) || 0,
                clinics: Number(document.querySelector('[data-category="clinics"]').dataset.value) || 0,
                booking: Number(document.querySelector('[data-category="booking"]').dataset.value) || 0,
                design: Number(document.querySelector('[data-category="design"]').dataset.value) || 0
            },
            comment: document.getElementById('commentInput').value.trim(),
            wouldRecommend: recommendValue
        };
    }

    function validate(data) {
        if (!data.overallRating) {
            return t('feedback.errorRatingRequired');
        }
        return null;
    }

    async function submit() {
        const alertBox = document.getElementById('feedbackAlert');
        alertBox.className = 'alert';
        alertBox.textContent = '';

        const data = collectFormData();
        const error = validate(data);

        if (error) {
            alertBox.classList.add('error');
            alertBox.textContent = error;
            document.getElementById('overallStars').classList.toggle('required-empty', !data.overallRating);
            return;
        }

        const btn = document.getElementById('submitFeedbackBtn');
        btn.classList.add('loading');

        let ok = true;
        try {
            await API.feedback.submit(data);
        } catch (err) {
            console.error('Feedback: failed to submit', err);
            ok = false;
        }

        btn.classList.remove('loading');
        showResult(ok);
    }

    function showResult(ok) {
        const icon = document.getElementById('feedbackResultIcon');
        icon.className = 'feedback-result-icon ' + (ok ? 'success' : 'error');
        icon.innerHTML = '<i class="fas ' + (ok ? 'fa-circle-check' : 'fa-triangle-exclamation') + '"></i>';
        document.getElementById('feedbackResultTitle').textContent = t(ok ? 'feedback.savedTitle' : 'feedback.errorTitle');
        document.getElementById('feedbackResultHint').textContent = t(ok ? 'feedback.savedHint' : 'feedback.errorHint');

        document.getElementById('feedbackFormWrap').classList.add('hidden');
        document.getElementById('feedbackResult').classList.remove('hidden');
    }

    function resetForm() {
        document.querySelectorAll('.star-rating').forEach((widget) => {
            widget.dataset.value = '0';
            widget.classList.remove('required-empty');
            paintStars(widget, 0);
            widget.querySelectorAll('.star-btn').forEach((button) => {
                button.setAttribute('aria-pressed', 'false');
            });
        });

        recommendValue = null;
        document.querySelectorAll('.recommend-btn').forEach((b) => {
            b.classList.remove('active');
            b.setAttribute('aria-pressed', 'false');
        });

        const comment = document.getElementById('commentInput');
        comment.value = '';
        document.getElementById('charCount').textContent = '0';

        const alertBox = document.getElementById('feedbackAlert');
        alertBox.className = 'alert';
        alertBox.textContent = '';

        document.getElementById('feedbackResult').classList.add('hidden');
        document.getElementById('feedbackFormWrap').classList.remove('hidden');
    }

    // ================= INIT =================

    function init() {
        if (!API.requireAuth()) return;

        document.querySelectorAll('.star-rating').forEach(initStarWidget);
        initRecommendToggle();
        initCommentCounter();
        window.addEventListener('languageChanged', updateRatingLabels);

        document.getElementById('submitFeedbackBtn')?.addEventListener('click', submit);
        document.getElementById('startOverBtn')?.addEventListener('click', resetForm);
    }

    return { init };

})();

/**
 * MedOrbit v2 - Feedback
 * No backend endpoint exists for platform feedback at all (grepped every
 * route file — see BACKEND_NEEDED.md). This is a fully working form with
 * real client-side validation; on submit it never calls an API and never
 * claims success — it shows an explicit "not connected yet" message.
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

    function initStarWidget(widget) {
        const buttons = widget.querySelectorAll('.star-btn');

        buttons.forEach((btn) => {
            const val = Number(btn.dataset.star);

            btn.addEventListener('mouseenter', () => paintStars(widget, val));
            btn.addEventListener('click', () => {
                widget.dataset.value = String(val);
                widget.classList.remove('required-empty');
                paintStars(widget, val);
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

        // No endpoint exists to send this to (see BACKEND_NEEDED.md) — the
        // brief delay is just normal button-press affordance, not a real
        // network call. The result panel below is explicit that nothing
        // was actually saved.
        await new Promise((resolve) => setTimeout(resolve, 450));

        btn.classList.remove('loading');
        console.info('Feedback: form is valid but there is no backend endpoint to submit to yet. Collected data:', data);

        document.getElementById('feedbackFormWrap').classList.add('hidden');
        document.getElementById('feedbackResult').classList.remove('hidden');
    }

    function resetForm() {
        document.querySelectorAll('.star-rating').forEach((widget) => {
            widget.dataset.value = '0';
            widget.classList.remove('required-empty');
            paintStars(widget, 0);
        });

        recommendValue = null;
        document.querySelectorAll('.recommend-btn').forEach((b) => b.classList.remove('active'));

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

        document.getElementById('submitFeedbackBtn')?.addEventListener('click', submit);
        document.getElementById('startOverBtn')?.addEventListener('click', resetForm);
    }

    return { init };

})();

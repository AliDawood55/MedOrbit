/* Global Feedback Review page. The API deliberately exposes only platform
 * feedback for a signed-in viewer; no medical or contact information is read. */
const FeedbackReview = (() => {
    'use strict';

    let payload = null;
    const copy = {
        ar: {
            back: 'العودة للرئيسية', loading: 'جارٍ تحميل التقييمات…', missing: 'لم يتم تحديد صاحب التقييم.',
            notFound: 'تعذّر العثور على هذه التقييمات.', retry: 'إعادة المحاولة', title: 'تقييمات المنصة',
            submitted: 'أُرسل في', overall: 'التقييم العام', outOf: 'من 5', details: 'التقييم التفصيلي',
            chatbot: 'المساعد الذكي', clinics: 'البحث عن المنشآت', booking: 'حجز المواعيد', design: 'تصميم المنصة',
            recommendation: 'هل ينصح بـ MedOrbit؟', yes: 'نعم، يوصي بالمنصة', no: 'لا يوصي بالمنصة',
            noAnswer: 'لم يحدد', comment: 'التعليق', noComment: 'لم يترك تعليقاً إضافياً.',
            reviews: 'تقييمات مرسلة'
        },
        en: {
            back: 'Back to home', loading: 'Loading feedback…', missing: 'No feedback reviewer was selected.',
            notFound: 'This feedback could not be found.', retry: 'Try again', title: 'Platform feedback',
            submitted: 'Submitted', overall: 'Overall rating', outOf: 'out of 5', details: 'Detailed ratings',
            chatbot: 'AI assistant', clinics: 'Finding facilities', booking: 'Appointment booking', design: 'Platform design',
            recommendation: 'Would they recommend MedOrbit?', yes: 'Yes, recommends MedOrbit', no: 'Does not recommend MedOrbit',
            noAnswer: 'No answer provided', comment: 'Comment', noComment: 'No additional comment was provided.',
            reviews: 'Submitted reviews'
        }
    };

    const lang = () => I18n?.getLang?.() === 'ar' ? 'ar' : 'en';
    const t = () => copy[lang()];
    const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character]));
    const reviewerId = () => new URLSearchParams(window.location.search).get('reviewer') || '';
    const reviewerName = (reviewer) => lang() === 'ar'
        ? (reviewer?.nameAr || reviewer?.nameEn || 'MedOrbit user')
        : (reviewer?.nameEn || reviewer?.nameAr || 'MedOrbit user');

    function stars(value) {
        const safeValue = Math.max(0, Math.min(5, Number(value) || 0));
        return Array.from({ length: 5 }, (_, index) => `<i class="fas fa-star ${index < safeValue ? 'is-filled' : ''}" aria-hidden="true"></i>`).join('');
    }

    function formattedDate(value) {
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '';
        return new Intl.DateTimeFormat(lang() === 'ar' ? 'ar' : 'en', { dateStyle: 'medium' }).format(date);
    }

    function categoryRow(label, value) {
        if (!value) return '';
        return `<div class="feedback-review-category"><span>${escapeHtml(label)}</span><span class="feedback-review-mini-stars" aria-label="${escapeHtml(`${value} ${t().outOf}`)}">${stars(value)}<b>${value}/5</b></span></div>`;
    }

    function reviewCard(review) {
        const text = t();
        const categories = review.categories || {};
        const recommendation = review.wouldRecommend === true
            ? `<span class="feedback-review-recommend is-yes"><i class="fas fa-thumbs-up"></i>${text.yes}</span>`
            : review.wouldRecommend === false
                ? `<span class="feedback-review-recommend is-no"><i class="fas fa-thumbs-down"></i>${text.no}</span>`
                : `<span class="feedback-review-recommend"><i class="fas fa-minus"></i>${text.noAnswer}</span>`;
        return `<article class="feedback-review-card">
            <div class="feedback-review-card-top"><div><p class="feedback-review-eyebrow">${text.overall}</p><div class="feedback-review-stars" aria-label="${escapeHtml(`${review.overallRating} ${text.outOf}`)}">${stars(review.overallRating)}<strong>${review.overallRating}/5</strong></div></div><time>${text.submitted} ${escapeHtml(formattedDate(review.createdAt))}</time></div>
            <div class="feedback-review-categories"><h3>${text.details}</h3>${categoryRow(text.chatbot, categories.chatbot)}${categoryRow(text.clinics, categories.clinics)}${categoryRow(text.booking, categories.booking)}${categoryRow(text.design, categories.design)}</div>
            <div class="feedback-review-recommendation"><span>${text.recommendation}</span>${recommendation}</div>
            <div class="feedback-review-comment"><h3>${text.comment}</h3><p>${review.comment ? escapeHtml(review.comment) : text.noComment}</p></div>
        </article>`;
    }

    function render() {
        const target = document.getElementById('reviewerFeedback');
        if (!target || !payload) return;
        const text = t();
        const reviewer = payload.reviewer || {};
        const avatar = reviewer.avatarUrl
            ? `<img class="feedback-review-avatar" src="${escapeHtml(API.assetUrl(reviewer.avatarUrl))}" alt="">`
            : '<span class="feedback-review-avatar feedback-review-avatar-fallback"><i class="fas fa-user"></i></span>';
        target.className = 'feedback-review-content';
        target.innerHTML = `<section class="feedback-review-hero"><div class="feedback-review-person">${avatar}<div><p>${text.title}</p><h1>${escapeHtml(reviewerName(reviewer))}</h1><span>${payload.reviews?.length || 0} ${text.reviews}</span></div></div></section><section class="feedback-review-list">${(payload.reviews || []).map(reviewCard).join('')}</section>`;
        document.getElementById('feedbackReviewBack').lastElementChild.textContent = text.back;
    }

    function renderError(message) {
        const target = document.getElementById('reviewerFeedback');
        if (!target) return;
        target.className = 'feedback-review-state feedback-review-error';
        target.innerHTML = `<i class="fas fa-circle-exclamation"></i><p>${escapeHtml(message)}</p><button class="btn btn-primary btn-sm" id="feedbackReviewRetry">${t().retry}</button>`;
        document.getElementById('feedbackReviewRetry')?.addEventListener('click', load);
    }

    async function load() {
        const id = reviewerId();
        if (!id) return renderError(t().missing);
        const target = document.getElementById('reviewerFeedback');
        target.className = 'feedback-review-state';
        target.innerHTML = `<i class="fas fa-circle-notch fa-spin"></i><p>${t().loading}</p>`;
        try {
            const response = await API.feedback.reviewer(id);
            payload = response?.data;
            if (!payload?.reviewer || !Array.isArray(payload.reviews)) throw new Error('INVALID_RESPONSE');
            render();
        } catch (error) {
            console.error('Feedback review failed', error);
            renderError(t().notFound);
        }
    }

    function init() {
        Layout.init();
        document.getElementById('feedbackReviewBack').lastElementChild.textContent = t().back;
        window.addEventListener('languageChanged', () => payload ? render() : load());
        load();
    }

    document.addEventListener('DOMContentLoaded', init);
    return { load };
})();

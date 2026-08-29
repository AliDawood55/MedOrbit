const BillingSandbox = (() => {

    let token = null;
    let attempt = null;

    const t = (key, en, ar) => BillingUI.t(key, en, ar);
    const esc = (value) => BillingUI.escapeHtml(value);
    const isArabic = () => BillingUI.isArabic();

    function el(id) { return document.getElementById(id); }

    function intervalLabel(interval) {
        if (interval === 'month') return t('billing.perMonth', '/month', '/شهر');
        if (interval === 'year') return t('billing.perYear', '/year', '/سنة');
        return '';
    }

    function renderError(message) {
        el('sandboxBody').innerHTML = `
            <p class="sandbox-error" role="alert">${esc(message)}</p>
            <a class="btn btn-secondary btn-block" href="billing.html">${
                esc(t('billing.backToBilling', 'Back to billing', 'العودة إلى الفوترة'))}</a>`;
    }

    function render() {
        const name = isArabic() ? attempt.name_ar : attempt.name_en;
        const price = BillingUI.formatPrice(attempt.price_cents, attempt.currency);

        const saving = attempt.billing_interval === 'year'
            ? `<p class="sandbox-saving">${esc(t('billing.annualSaving',
                'Two months free compared with paying monthly.',
                'شهران مجانًا مقارنة بالدفع الشهري.'))}</p>`
            : '';

        el('sandboxBody').innerHTML = `
            <div class="sandbox-summary">
                <p class="sandbox-summary__label">${esc(t('billing.selectedPlan', 'Selected plan', 'الخطة المختارة'))}</p>
                <p class="sandbox-summary__plan">${esc(name)}</p>
                <p class="sandbox-summary__price">
                    <span>${esc(price)}</span><span class="sandbox-summary__interval">${esc(intervalLabel(attempt.billing_interval))}</span>
                </p>
                ${saving}
            </div>

            <div class="sandbox-actions">
                <button type="button" class="btn btn-primary btn-block" data-outcome="success">
                    ${esc(t('billing.simulateSuccess', 'Simulate successful payment', 'محاكاة دفع ناجح'))}
                </button>
                <button type="button" class="btn btn-secondary btn-block" data-outcome="failure">
                    ${esc(t('billing.simulateFailure', 'Simulate payment failure', 'محاكاة فشل الدفع'))}
                </button>
                <button type="button" class="btn btn-ghost btn-block" data-outcome="canceled">
                    ${esc(t('billing.simulateCancel', 'Cancel and go back', 'إلغاء والعودة'))}
                </button>
            </div>

            <p class="sandbox-nocard">
                <i class="fas fa-lock" aria-hidden="true"></i>
                ${esc(t('billing.noCardCollected',
                    'No card details are requested or stored at any point.',
                    'لا يتم طلب أو تخزين أي بيانات بطاقة في أي مرحلة.'))}
            </p>`;
    }

async function complete(outcome, button) {
        const buttons = Array.from(document.querySelectorAll('[data-outcome]'));
        buttons.forEach((node) => { node.disabled = true; });
        if (button) button.dataset.busy = 'true';

        try {
            const res = await API.billing.sandbox.complete(token, outcome);
            const returnPath = res?.data?.return_path;

            if (outcome === 'canceled') {
                window.location.href = returnPath || 'billing.html?state=canceled';
                return;
            }
            if (outcome === 'failure') {

window.location.href = 'billing.html?state=failed';
                return;
            }

window.location.href = returnPath || 'billing.html?state=success';
        } catch (err) {
            buttons.forEach((node) => { node.disabled = false; });
            if (button) delete button.dataset.busy;
            Toast.error(err?.message || t('billing.sandboxFailed',
                'Could not complete the sandbox checkout.', 'تعذر إكمال عملية الدفع التجريبية.'));
        }
    }

function renderUnavailable() {
        el('sandboxBody').innerHTML = `
            <p class="sandbox-error" role="alert">${esc(t('billing.sandboxUnavailable',
                'Sandbox checkout is not enabled in this environment.',
                'الدفع التجريبي غير مُفعّل في هذه البيئة.'))}</p>
            <a class="btn btn-secondary btn-block" href="billing.html">${
                esc(t('billing.backToBilling', 'Back to billing', 'العودة إلى الفوترة'))}</a>`;
    }

    async function init() {
        if (!API.isAuthenticated?.()) return;

const cfg = await API.billing.config().catch(() => null);
        if (!cfg?.data?.sandbox) {
            renderUnavailable();
            return;
        }

        token = new URLSearchParams(window.location.search).get('session');
        if (!token) {
            renderError(t('billing.sandboxNoSession', 'This checkout link is missing its session.',
                'رابط الدفع هذا ينقصه معرّف الجلسة.'));
            return;
        }

        document.addEventListener('click', (event) => {
            const trigger = event.target.closest('[data-outcome]');
            if (trigger) complete(trigger.dataset.outcome, trigger);
        });

        try {
            const res = await API.billing.sandbox.checkout(token);
            attempt = res?.data || null;
            if (!attempt) throw new Error('not found');

            if (!attempt.is_open) {
                renderError(t('billing.sandboxClosed',
                    'This checkout has already been completed or has expired.',
                    'تم إكمال عملية الدفع هذه بالفعل أو انتهت صلاحيتها.'));
                return;
            }
            render();
        } catch (err) {

renderError(t('billing.sandboxNotFound',
                'This checkout session was not found.', 'لم يتم العثور على جلسة الدفع هذه.'));
        }
    }

    return { init };
})();

/**
 * MedOrbit — the sandbox hosted checkout.
 *
 * Stands in for the page a payment provider would host on its own domain.
 * It shows what is being bought and offers the outcomes a real checkout can
 * end in, and that is the whole of its authority: clicking "successful
 * payment" does not make anyone Pro. It asks the backend to have the mock
 * provider emit the event a real provider would have sent, and that event
 * goes through signature verification, idempotent recording and the
 * subscription state machine like any other.
 *
 * There are no card fields on this page, and there never will be. Card entry
 * belongs on a provider's PCI DSS validated pages; building a fake card form
 * here would be rehearsing an architecture MedOrbit is specifically designed
 * not to have.
 *
 * The plan and the price are read from the backend against the stored
 * checkout attempt, never from the query string, so editing the URL changes
 * nothing except which attempt is not found.
 */
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

    /**
     * Resolve the attempt, then go where the backend says.
     *
     * The destination comes from the response — the return path the backend
     * stored when the checkout was created — rather than from a query
     * parameter, so this page cannot be turned into an open redirect by
     * editing its URL.
     */
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
                // A declined payment is not a subscription. The user goes back
                // to billing, still on the free plan, with nothing charged.
                window.location.href = 'billing.html?state=failed';
                return;
            }
            // Success: return to whatever the user was doing when they hit the
            // limit, if the backend recorded one.
            window.location.href = returnPath || 'billing.html?state=success';
        } catch (err) {
            buttons.forEach((node) => { node.disabled = false; });
            if (button) delete button.dataset.busy;
            Toast.error(err?.message || t('billing.sandboxFailed',
                'Could not complete the sandbox checkout.', 'تعذر إكمال عملية الدفع التجريبية.'));
        }
    }

    /**
     * The page with nothing on it.
     *
     * Reached when the backend reports no sandbox — which is what every
     * deployed environment reports, because the sandbox routes are not
     * mounted there at all. The URL is guessable; what it leads to is not a
     * checkout, and nothing below this line renders a control.
     */
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

        // Asked before anything else, and answered by the backend rather than
        // by this page: with mock billing off there is no checkout to show
        // and no outcome to simulate, so the page renders its dead end and
        // never binds a single button.
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
            // 404 covers both "no such attempt" and "somebody else's attempt".
            // The page cannot tell the difference, and neither should it.
            renderError(t('billing.sandboxNotFound',
                'This checkout session was not found.', 'لم يتم العثور على جلسة الدفع هذه.'));
        }
    }

    return { init };
})();

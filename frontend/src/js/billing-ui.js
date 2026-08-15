/**
 * MedOrbit — the shared upgrade experience.
 *
 * One pricing dialog, opened from wherever a limit is met: the chatbot
 * composer, the Voice Doctor cooldown, or the billing page. Having a single
 * one matters for more than tidiness — every price shown anywhere in the
 * product comes from this module, and this module only ever renders numbers
 * that /api/billing/plans returned. There is no hardcoded 20 or 200 in the
 * frontend, so the UI cannot drift out of step with what checkout charges.
 *
 * The savings figure on the annual plan is derived from those same two
 * server numbers rather than written down, for the same reason: a price
 * change is one database UPDATE and every screen follows it.
 *
 * This module has no authority. It starts a checkout and it displays what
 * the backend says; it cannot grant, extend or refresh entitlement, and
 * nothing it puts in the DOM is read back as truth.
 */
const BillingUI = (() => {

    let dialog = null;
    let previouslyFocused = null;
    let cachedPlans = null;
    let cachedConfig = null;

    function isArabic() {
        return typeof I18n !== 'undefined' && I18n.getLang?.() === 'ar';
    }

    function t(key, en, ar) {
        const translated = typeof I18n !== 'undefined' ? I18n.t?.(key) : null;
        if (translated && translated !== key) return translated;
        return isArabic() ? ar : en;
    }

    /**
     * Render a price the backend supplied.
     *
     * Minor units in, formatted string out. Whole amounts lose the ".00" —
     * "$20/month" reads like a price, "$20.00/month" reads like an invoice.
     */
    function formatPrice(cents, currency = 'USD') {
        const amount = Number(cents || 0) / 100;
        const fractionDigits = Number.isInteger(amount) ? 0 : 2;
        try {
            return new Intl.NumberFormat(isArabic() ? 'ar' : 'en-US', {
                style: 'currency',
                currency,
                minimumFractionDigits: fractionDigits,
                maximumFractionDigits: 2,
            }).format(amount);
        } catch (_) {
            return `${currency} ${amount.toFixed(fractionDigits)}`;
        }
    }

    function intervalLabel(plan) {
        if (plan.billing_interval === 'month') return t('billing.perMonth', '/month', '/شهر');
        if (plan.billing_interval === 'year') return t('billing.perYear', '/year', '/سنة');
        return '';
    }

    /**
     * What an annual plan saves against paying monthly for a year.
     *
     * Computed from the two prices the backend returned, never from a
     * remembered "$40". Returns null when the catalogue does not contain
     * both plans, so a missing plan produces no claim rather than a wrong one.
     */
    function annualSaving(plans) {
        const monthly = plans.find((p) => p.billing_interval === 'month' && p.grants_pro);
        const annual = plans.find((p) => p.billing_interval === 'year' && p.grants_pro);
        if (!monthly || !annual) return null;

        const saving = (monthly.price_cents * 12) - annual.price_cents;
        if (saving <= 0) return null;

        return {
            amount: formatPrice(saving, annual.currency),
            months: Math.round(saving / monthly.price_cents),
        };
    }

    async function loadCatalogue({ force = false } = {}) {
        if (!force && cachedPlans && cachedConfig) {
            return { plans: cachedPlans, config: cachedConfig };
        }
        const [plansRes, configRes] = await Promise.all([
            API.billing.plans(),
            API.billing.config().catch(() => null),
        ]);
        cachedPlans = plansRes?.data?.plans || [];
        cachedConfig = configRes?.data || { checkout_available: false, sandbox: false };
        return { plans: cachedPlans, config: cachedConfig };
    }

    // -----------------------------------------------------------------
    // Rendering
    // -----------------------------------------------------------------

    function planFeatures(plan) {
        if (!plan.grants_pro) {
            return [
                t('billing.freeVoice', '1 Voice Doctor consultation per free allowance',
                    'استشارة صوتية واحدة ضمن الحد المجاني'),
                t('billing.freeChat', '20 Chatbot messages per free quota window',
                    '20 رسالة للمساعد الذكي في كل فترة مجانية'),
            ];
        }
        return [
            t('billing.proVoice', 'Unlimited Voice Doctor consultations',
                'استشارات صوتية غير محدودة'),
            t('billing.proChat', 'Unlimited Chatbot messages', 'رسائل غير محدودة للمساعد الذكي'),
            t('billing.proSupport', 'Priority access to new AI features',
                'أولوية الوصول إلى ميزات الذكاء الاصطناعي الجديدة'),
        ];
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function planCard(plan, { saving, currentPlanCode, checkoutAvailable }) {
        const name = isArabic() ? plan.name_ar : plan.name_en;
        const isCurrent = plan.plan_code === currentPlanCode;
        const isAnnual = plan.billing_interval === 'year';
        const features = planFeatures(plan)
            .map((f) => `<li><i class="fas fa-check" aria-hidden="true"></i><span>${escapeHtml(f)}</span></li>`)
            .join('');

        const badge = isAnnual && saving
            ? `<span class="plan-card__badge">${escapeHtml(t('billing.bestValue', 'Best value', 'أفضل قيمة'))}</span>`
            : '';

        const savingNote = isAnnual && saving
            ? `<p class="plan-card__saving">${escapeHtml(
                t('billing.saveAmount', `Save ${saving.amount} a year`, `وفّر ${saving.amount} سنويًا`))}</p>`
            : '';

        let action;
        if (isCurrent) {
            action = `<button type="button" class="btn btn-secondary btn-block" disabled>${
                escapeHtml(t('billing.currentPlan', 'Current plan', 'خطتك الحالية'))}</button>`;
        } else if (!plan.grants_pro) {
            action = '';
        } else if (!checkoutAvailable) {
            action = `<button type="button" class="btn btn-secondary btn-block" disabled>${
                escapeHtml(t('billing.unavailable', 'Unavailable', 'غير متاح'))}</button>`;
        } else {
            action = `<button type="button" class="btn btn-primary btn-block" data-checkout-plan="${
                escapeHtml(plan.plan_code)}">${
                escapeHtml(t('billing.choosePlan', 'Choose this plan', 'اختر هذه الخطة'))}</button>`;
        }

        return `
            <article class="plan-card${isAnnual ? ' plan-card--featured' : ''}${isCurrent ? ' plan-card--current' : ''}">
                ${badge}
                <h3 class="plan-card__name">${escapeHtml(name)}</h3>
                <p class="plan-card__price">
                    <span class="plan-card__amount">${escapeHtml(formatPrice(plan.price_cents, plan.currency))}</span>
                    <span class="plan-card__interval">${escapeHtml(intervalLabel(plan))}</span>
                </p>
                ${savingNote}
                <ul class="plan-card__features">${features}</ul>
                ${action}
            </article>`;
    }

    function sandboxNotice(config) {
        if (!config.sandbox) return '';
        return `
            <div class="billing-sandbox-notice" role="note">
                <i class="fas fa-flask" aria-hidden="true"></i>
                <div>
                    <strong>${escapeHtml(t('billing.sandboxTitle', 'Development sandbox', 'بيئة تطوير تجريبية'))}</strong>
                    <p>${escapeHtml(t('billing.sandboxBody',
                        'No real payment will be processed and no card details are collected.',
                        'لن تتم معالجة أي دفعة حقيقية ولا يتم جمع أي بيانات بطاقة.'))}</p>
                </div>
            </div>`;
    }

    // -----------------------------------------------------------------
    // Dialog
    // -----------------------------------------------------------------

    function focusableNodes() {
        if (!dialog) return [];
        return Array.from(dialog.querySelectorAll(
            'button:not([disabled]), [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
        )).filter((node) => node.offsetParent !== null);
    }

    /** Keep Tab inside the dialog; Escape closes it. */
    function onKeydown(event) {
        if (event.key === 'Escape') {
            event.preventDefault();
            close();
            return;
        }
        if (event.key !== 'Tab') return;

        const nodes = focusableNodes();
        if (nodes.length === 0) return;
        const first = nodes[0];
        const last = nodes[nodes.length - 1];

        if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first.focus();
        }
    }

    function close() {
        if (!dialog) return;
        document.removeEventListener('keydown', onKeydown, true);
        dialog.remove();
        dialog = null;
        document.body.style.overflow = '';
        // Return focus to whatever opened the dialog, so a keyboard user is
        // not dropped back at the top of the document.
        if (previouslyFocused && document.contains(previouslyFocused)) previouslyFocused.focus();
        previouslyFocused = null;
    }

    /**
     * Open the pricing dialog.
     *
     * `returnPath` records where the user was when they hit the limit, so a
     * successful checkout can put them back there. It is sent to the backend
     * and stored against the checkout attempt rather than kept in the URL,
     * because a return target that survives a round trip through the browser
     * is an open redirect waiting to happen.
     */
    async function openPricing({ returnPath = null, reason = null } = {}) {
        if (dialog) close();
        if (!API.isAuthenticated?.()) {
            window.location.href = 'login.html';
            return;
        }

        previouslyFocused = document.activeElement;

        dialog = document.createElement('div');
        dialog.className = 'billing-modal';
        dialog.innerHTML = `
            <div class="billing-modal__backdrop" data-billing-close></div>
            <div class="billing-modal__panel" role="dialog" aria-modal="true"
                 aria-labelledby="billingModalTitle" tabindex="-1">
                <button type="button" class="billing-modal__close" data-billing-close
                        aria-label="${escapeHtml(t('common.close', 'Close', 'إغلاق'))}">
                    <i class="fas fa-times" aria-hidden="true"></i>
                </button>
                <h2 id="billingModalTitle" class="billing-modal__title">${
                    escapeHtml(t('billing.upgradeTitle', 'MedOrbit Pro', 'مدأوربت برو'))}</h2>
                <p class="billing-modal__subtitle">${escapeHtml(reason
                    || t('billing.upgradeSubtitle',
                        'Unlimited AI consultations and chat, on every device.',
                        'استشارات ومحادثات ذكية غير محدودة، على كل أجهزتك.'))}</p>
                <div class="billing-modal__body" aria-live="polite">
                    <p class="billing-modal__loading">${escapeHtml(t('common.loading', 'Loading…', 'جارٍ التحميل…'))}</p>
                </div>
            </div>`;

        document.body.appendChild(dialog);
        document.body.style.overflow = 'hidden';
        document.addEventListener('keydown', onKeydown, true);
        dialog.querySelector('.billing-modal__panel').focus();

        dialog.addEventListener('click', (event) => {
            if (event.target.closest('[data-billing-close]')) {
                close();
                return;
            }
            const trigger = event.target.closest('[data-checkout-plan]');
            if (trigger) startCheckout(trigger.dataset.checkoutPlan, returnPath, trigger);
        });

        const body = dialog.querySelector('.billing-modal__body');
        try {
            const [{ plans, config }, entitlements] = await Promise.all([
                loadCatalogue(),
                API.billing.entitlements().catch(() => null),
            ]);
            if (!dialog) return;

            const currentPlanCode = entitlements?.data?.plan || 'free';
            const saving = annualSaving(plans);
            const cards = plans
                .map((plan) => planCard(plan, { saving, currentPlanCode, checkoutAvailable: config.checkout_available }))
                .join('');

            const unavailable = config.checkout_available ? '' : `
                <p class="billing-modal__unavailable" role="status">${escapeHtml(t('billing.checkoutUnavailable',
                    'Upgrades are not available yet. Your free allowance is unaffected.',
                    'الترقية غير متاحة بعد. لن يتأثر حدك المجاني.'))}</p>`;

            body.innerHTML = `${sandboxNotice(config)}${unavailable}<div class="plan-grid">${cards}</div>`;
        } catch (err) {
            if (!dialog) return;
            body.innerHTML = `<p class="billing-modal__unavailable" role="alert">${escapeHtml(
                t('billing.loadFailed', 'Could not load plans. Please try again.',
                    'تعذر تحميل الخطط. حاول مرة أخرى.'))}</p>`;
        }
    }

    /**
     * Hand off to the provider's checkout.
     *
     * The only thing sent is a plan code. Nothing about the resulting
     * subscription is decided here, or on the page the user lands on when
     * they come back — entitlement changes when a verified provider event
     * says it did, and not a moment sooner.
     */
    async function startCheckout(planCode, returnPath, trigger) {
        if (!planCode) return;
        if (trigger) {
            trigger.disabled = true;
            trigger.dataset.busy = 'true';
        }
        try {
            const res = await API.billing.checkout(planCode, returnPath || currentReturnPath());
            const url = res?.data?.checkout_url;
            if (!url) throw new Error('No checkout URL');
            window.location.href = url;
        } catch (err) {
            if (trigger) {
                trigger.disabled = false;
                delete trigger.dataset.busy;
            }
            const message = err?.code === 'SUBSCRIPTION_ALREADY_LIVE'
                ? t('billing.alreadySubscribed', 'This account already has a subscription.',
                    'هذا الحساب لديه اشتراك بالفعل.')
                : (err?.message || t('billing.checkoutFailed', 'Could not start checkout.',
                    'تعذر بدء عملية الدفع.'));
            if (typeof Toast !== 'undefined') Toast.error?.(message);
            else alert(message);
        }
    }

    /** The page the user is on, as a relative path the backend will validate. */
    function currentReturnPath() {
        const file = window.location.pathname.split('/').pop() || '';
        return file ? `${file}${window.location.search || ''}` : null;
    }

    return {
        openPricing,
        close,
        formatPrice,
        annualSaving,
        loadCatalogue,
        currentReturnPath,
        sandboxNotice,
        escapeHtml,
        t,
        isArabic,
    };
})();

if (typeof window !== 'undefined') window.BillingUI = BillingUI;

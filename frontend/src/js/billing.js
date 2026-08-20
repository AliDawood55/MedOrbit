/**
 * MedOrbit — the billing page.
 *
 * Renders subscription state that the server decided, and offers the three
 * actions a subscriber actually has: stop auto-renew, start it again, and
 * switch between monthly and annual at the next renewal.
 *
 * Every fact on this page arrives from /api/billing/subscription or
 * /api/billing/entitlements. Nothing is cached in localStorage, nothing is
 * kept in a cookie, and no state here is trusted on the way back — the
 * buttons send an intent and then re-read what the backend did with it. A
 * user who edits this page's variables changes what they see and nothing
 * else, because the composer, the consultation and the checkout all re-check
 * server-side.
 *
 * Dates are rendered from absolute UTC instants the backend supplied, so two
 * devices in different timezones show the same renewal date.
 */
const Billing = (() => {

    let subscription = null;
    let entitlements = null;
    let config = { checkout_available: false, sandbox: false };

    const t = (key, en, ar) => BillingUI.t(key, en, ar);
    const esc = (value) => BillingUI.escapeHtml(value);
    const isArabic = () => BillingUI.isArabic();

    function el(id) { return document.getElementById(id); }

    /** Format a server timestamp in the reader's locale. Never re-derives it. */
    function formatDate(value) {
        if (!value) return '—';
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return '—';
        try {
            return new Intl.DateTimeFormat(isArabic() ? 'ar' : 'en-GB', {
                year: 'numeric', month: 'long', day: 'numeric',
            }).format(date);
        } catch (_) {
            return date.toISOString().slice(0, 10);
        }
    }

    /**
     * Whole days between now and a server deadline.
     *
     * The browser clock is only used for the *distance*; whether access has
     * actually ended is decided by the backend on every request. A skewed
     * clock makes this number slightly wrong and changes nothing else.
     */
    function daysUntil(value) {
        if (!value) return null;
        const ms = new Date(value).getTime() - Date.now();
        if (Number.isNaN(ms)) return null;
        return Math.max(Math.ceil(ms / 86400000), 0);
    }

    // -----------------------------------------------------------------
    // State classification
    // -----------------------------------------------------------------

    /**
     * The nine states this page can be in.
     *
     * Derived from the server's status plus its timestamps — never stored,
     * so it cannot go stale, and never sent anywhere.
     */
    function classify() {
        if (!subscription || !subscription.status) return 'free';
        if (subscription.status === 'past_due') return 'past_due';
        if (subscription.status === 'canceled') return 'canceled';
        if (subscription.status === 'expired') return 'expired';
        if (subscription.status === 'incomplete') return 'incomplete';
        if (subscription.status === 'active' && subscription.cancel_at_period_end) return 'canceling';
        if (subscription.status === 'active') return 'active';
        return 'free';
    }

    const STATUS_TEXT = {
        free: () => ({
            tone: 'neutral',
            label: t('billing.statusFree', 'Free plan', 'الخطة المجانية'),
            detail: t('billing.statusFreeDetail',
                'You are on the free allowance. Upgrade any time.',
                'أنت على الحد المجاني. يمكنك الترقية في أي وقت.'),
        }),
        active: () => ({
            tone: 'good',
            label: t('billing.statusActive', 'Active', 'نشط'),
            detail: t('billing.statusActiveDetail',
                `Renews on ${formatDate(subscription.current_period_end)}.`,
                `يتجدد في ${formatDate(subscription.current_period_end)}.`),
        }),
        canceling: () => ({
            tone: 'warn',
            label: t('billing.statusCanceling', 'Ending soon', 'ينتهي قريبًا'),
            detail: t('billing.statusCancelingDetail',
                `Your subscription will end on ${formatDate(subscription.current_period_end)}. You keep Pro access until then.`,
                `سينتهي اشتراكك في ${formatDate(subscription.current_period_end)}. ستحتفظ بمزايا Pro حتى ذلك الحين.`),
        }),
        past_due: () => {
            const days = daysUntil(subscription.grace_period_ends_at);
            return {
                tone: 'danger',
                label: t('billing.statusPastDue', 'Payment problem', 'مشكلة في الدفع'),
                detail: t('billing.statusPastDueDetail',
                    `There is a problem with your subscription renewal. Your Pro access is temporarily still active. Please update your payment method before ${formatDate(subscription.grace_period_ends_at)}${days !== null ? ` (${days} days left)` : ''}.`,
                    `هناك مشكلة في تجديد اشتراكك. لا تزال مزايا Pro نشطة مؤقتًا. يُرجى تحديث طريقة الدفع قبل ${formatDate(subscription.grace_period_ends_at)}${days !== null ? ` (${days} يومًا متبقية)` : ''}.`),
            };
        },
        canceled: () => ({
            tone: 'neutral',
            label: t('billing.statusCanceled', 'Canceled', 'ملغى'),
            detail: t('billing.statusCanceledDetail',
                `Your subscription ended on ${formatDate(subscription.ended_at)}. Your history and records are unchanged.`,
                `انتهى اشتراكك في ${formatDate(subscription.ended_at)}. سجلك وبياناتك لم تتغير.`),
        }),
        expired: () => ({
            tone: 'neutral',
            label: t('billing.statusExpired', 'Expired', 'منتهٍ'),
            detail: t('billing.statusExpiredDetail',
                'Your subscription has ended. Your history and records are unchanged.',
                'انتهى اشتراكك. سجلك وبياناتك لم تتغير.'),
        }),
        incomplete: () => ({
            tone: 'warn',
            label: t('billing.statusIncomplete', 'Payment not completed', 'لم يكتمل الدفع'),
            detail: t('billing.statusIncompleteDetail',
                'The payment did not complete, so no subscription was started.',
                'لم تكتمل عملية الدفع، لذلك لم يبدأ أي اشتراك.'),
        }),
    };

    // -----------------------------------------------------------------
    // Rendering
    // -----------------------------------------------------------------

    function renderStatus() {
        const state = classify();
        const info = (STATUS_TEXT[state] || STATUS_TEXT.free)();
        const planName = subscription?.plan_code && subscription.plan_code !== 'free'
            ? (isArabic() ? subscription.plan_name_ar : subscription.plan_name_en)
            : t('billing.planFree', 'Free', 'مجاني');

        const interval = subscription?.billing_interval === 'month'
            ? t('billing.intervalMonthly', 'Billed monthly', 'فوترة شهرية')
            : subscription?.billing_interval === 'year'
                ? t('billing.intervalAnnual', 'Billed annually', 'فوترة سنوية')
                : '';

        const price = subscription?.price_cents
            ? `${BillingUI.formatPrice(subscription.price_cents, subscription.currency)}`
            : '';

        const pending = subscription?.pending_plan
            ? `<p class="billing-card__pending">${esc(t('billing.pendingChange',
                `Changing to ${isArabic() ? subscription.pending_plan.name_ar : subscription.pending_plan.name_en} on ${formatDate(subscription.pending_plan.effective_at)}.`,
                `سيتم التغيير إلى ${subscription.pending_plan.name_ar} في ${formatDate(subscription.pending_plan.effective_at)}.`))}</p>`
            : '';

        el('billingStatus').innerHTML = `
            <div class="billing-card billing-card--${info.tone}">
                <div class="billing-card__head">
                    <div>
                        <p class="billing-card__eyebrow">${esc(t('billing.currentPlanLabel', 'Current plan', 'خطتك الحالية'))}</p>
                        <h2 class="billing-card__plan">${esc(planName)}</h2>
                        ${price ? `<p class="billing-card__price">${esc(price)} ${esc(interval)}</p>` : ''}
                    </div>
                    <span class="billing-badge billing-badge--${info.tone}">${esc(info.label)}</span>
                </div>
                <p class="billing-card__detail">${esc(info.detail)}</p>
                ${pending}
                <div class="billing-card__actions" id="billingActions"></div>
            </div>`;

        renderActions(state);
    }

    function renderActions(state) {
        const host = el('billingActions');
        if (!host) return;

        const buttons = [];

        if (state === 'free' || state === 'canceled' || state === 'expired' || state === 'incomplete') {
            buttons.push(`<button type="button" class="btn btn-primary" data-billing-action="upgrade">${
                esc(t('billing.upgrade', 'Upgrade to Pro', 'الترقية إلى Pro'))}</button>`);
        }

        if (state === 'active' || state === 'past_due') {
            const other = subscription.plan_code === 'pro_monthly' ? 'pro_annual' : 'pro_monthly';
            const otherLabel = other === 'pro_annual'
                ? t('billing.switchToAnnual', 'Switch to annual billing', 'التحويل إلى الفوترة السنوية')
                : t('billing.switchToMonthly', 'Switch to monthly billing', 'التحويل إلى الفوترة الشهرية');

            if (!subscription.pending_plan) {
                buttons.push(`<button type="button" class="btn btn-secondary" data-billing-action="change-plan"
                    data-plan="${esc(other)}">${esc(otherLabel)}</button>`);
            }
            buttons.push(`<button type="button" class="btn btn-ghost btn-danger-text" data-billing-action="cancel">${
                esc(t('billing.cancel', 'Cancel subscription', 'إلغاء الاشتراك'))}</button>`);
        }

        if (state === 'canceling') {
            buttons.push(`<button type="button" class="btn btn-primary" data-billing-action="resume">${
                esc(t('billing.resume', 'Resume subscription', 'استئناف الاشتراك'))}</button>`);
        }

        if (state === 'past_due') {
            // No card form, here or anywhere. "Update payment method" leads to
            // the provider's own management surface; in the sandbox that is
            // this page, which is the honest answer rather than a fake form.
            buttons.unshift(`<button type="button" class="btn btn-primary" data-billing-action="update-payment">${
                esc(t('billing.updatePayment', 'Update payment method', 'تحديث طريقة الدفع'))}</button>`);
        }

        host.innerHTML = buttons.join('');
    }

    /**
     * Usage, straight from the entitlement snapshot.
     *
     * A Pro subscriber sees "unlimited" because the server said unlimited,
     * not because the page decided a Pro user should not see a counter.
     */
    function renderUsage() {
        const host = el('billingUsage');
        if (!host || !entitlements) return;

        const chat = entitlements.features?.chatbot;
        const voice = entitlements.features?.voice_doctor;

        const chatValue = chat?.unlimited
            ? t('billing.unlimited', 'Unlimited', 'غير محدود')
            : `${chat?.remaining ?? 0} / ${chat?.limit ?? 0}`;

        const chatNote = chat?.unlimited
            ? ''
            : chat?.resets_at
                ? t('billing.resetsOn', `Resets ${formatDate(chat.resets_at)}`, `يتجدد ${formatDate(chat.resets_at)}`)
                : t('billing.resetsOnFirstUse', 'Resets 24 hours after your first message',
                    'يتجدد بعد 24 ساعة من أول رسالة');

        const voiceValue = voice?.unlimited
            ? t('billing.unlimited', 'Unlimited', 'غير محدود')
            : voice?.allowed
                ? t('billing.available', 'Available', 'متاحة')
                : t('billing.onCooldown', 'On cooldown', 'في فترة انتظار');

        const voiceNote = !voice?.unlimited && voice?.next_free_at
            ? t('billing.nextFree', `Next free consultation ${formatDate(voice.next_free_at)}`,
                `الاستشارة المجانية القادمة ${formatDate(voice.next_free_at)}`)
            : '';

        host.innerHTML = `
            <div class="usage-tile">
                <p class="usage-tile__label">${esc(t('billing.usageChat', 'Chatbot messages', 'رسائل المساعد الذكي'))}</p>
                <p class="usage-tile__value">${esc(chatValue)}</p>
                <p class="usage-tile__note">${esc(chatNote)}</p>
            </div>
            <div class="usage-tile">
                <p class="usage-tile__label">${esc(t('billing.usageVoice', 'Voice Doctor', 'الطبيب الصوتي'))}</p>
                <p class="usage-tile__value">${esc(voiceValue)}</p>
                <p class="usage-tile__note">${esc(voiceNote)}</p>
            </div>`;
    }

    /** Human-readable labels for the canonical event vocabulary. */
    const HISTORY_LABELS = {
        'checkout.completed': () => t('billing.evtStarted', 'Subscription started', 'بدأ الاشتراك'),
        'subscription.activated': () => t('billing.evtStarted', 'Subscription started', 'بدأ الاشتراك'),
        'subscription.renewed': () => t('billing.evtRenewed', 'Renewal successful', 'تم التجديد بنجاح'),
        'payment.failed': () => t('billing.evtFailed', 'Renewal failed', 'فشل التجديد'),
        'payment.recovered': () => t('billing.evtRecovered', 'Payment recovered', 'تمت استعادة الدفع'),
        'subscription.cancel_at_period_end': () => t('billing.evtScheduled', 'Cancellation scheduled', 'تمت جدولة الإلغاء'),
        'subscription.updated': () => t('billing.evtPlanChange', 'Plan change scheduled', 'تمت جدولة تغيير الخطة'),
        'subscription.canceled': () => t('billing.evtEnded', 'Subscription ended', 'انتهى الاشتراك'),
    };

    function renderHistory(events) {
        const host = el('billingHistory');
        if (!host) return;

        if (!events || events.length === 0) {
            host.innerHTML = `<p class="billing-empty">${esc(t('billing.noHistory',
                'No billing activity yet.', 'لا يوجد نشاط فوترة بعد.'))}</p>`;
            return;
        }

        host.innerHTML = `<ul class="billing-history">${events.map((event) => {
            const label = HISTORY_LABELS[event.event_type];
            return `<li class="billing-history__row">
                <span>${esc(label ? label() : event.event_type)}</span>
                <time datetime="${esc(event.occurred_at)}">${esc(formatDate(event.occurred_at))}</time>
            </li>`;
        }).join('')}</ul>`;
    }

    /**
     * "This is a sandbox" stated on the page itself, not only in the dialog.
     *
     * Sourced from the backend's own answer rather than a build flag, so it
     * cannot say "simulated" while the process is doing something else. A
     * page that can take money and a page that cannot must never look the
     * same.
     */
    function renderSandboxNotice() {
        const host = el('billingSandboxNotice');
        if (!host) return;
        const markup = BillingUI.sandboxNotice(config);
        host.hidden = !markup;
        host.innerHTML = markup;
    }

    /**
     * Developer controls, shown only when the backend reports a sandbox.
     *
     * Note what is not offered: anything that creates a subscription. These
     * simulate what a provider would do to an EXISTING one — a renewal, a
     * declined card, a recovery. Becoming Pro still requires going through
     * checkout, in the sandbox exactly as in production.
     */
    function renderSandboxTools() {
        const host = el('billingSandbox');
        if (!host) return;

        if (!config.sandbox || !subscription?.status) {
            host.hidden = true;
            host.innerHTML = '';
            return;
        }

        host.hidden = false;
        host.innerHTML = `
            <h2 class="section-title">${esc(t('billing.sandboxTools', 'Sandbox lifecycle simulation', 'محاكاة دورة الاشتراك'))}</h2>
            <p class="billing-empty">${esc(t('billing.sandboxToolsHelp',
                'Development only. These trigger the provider events a real provider would send on its own schedule.',
                'للتطوير فقط. تُشغّل هذه أحداث المزود التي يرسلها المزود الحقيقي وفق جدوله.'))}</p>
            <div class="billing-card__actions">
                <button type="button" class="btn btn-secondary btn-sm" data-simulate="renewal">${
                    esc(t('billing.simRenewal', 'Simulate renewal', 'محاكاة التجديد'))}</button>
                <button type="button" class="btn btn-secondary btn-sm" data-simulate="renewal_failure">${
                    esc(t('billing.simFailure', 'Simulate renewal failure', 'محاكاة فشل التجديد'))}</button>
                <button type="button" class="btn btn-secondary btn-sm" data-simulate="payment_recovered">${
                    esc(t('billing.simRecovered', 'Simulate payment recovered', 'محاكاة استعادة الدفع'))}</button>
                <button type="button" class="btn btn-secondary btn-sm" data-simulate="ended">${
                    esc(t('billing.simEnded', 'Simulate subscription ended', 'محاكاة انتهاء الاشتراك'))}</button>
            </div>`;
    }

    /** Banner for the state the user came back from checkout in. */
    function renderReturnBanner() {
        const host = el('billingBanner');
        if (!host) return;

        const state = new URLSearchParams(window.location.search).get('state');
        if (state !== 'success' && state !== 'canceled') {
            host.hidden = true;
            return;
        }

        host.hidden = false;
        host.className = `billing-banner billing-banner--${state === 'success' ? 'good' : 'neutral'}`;
        host.setAttribute('role', 'status');
        host.textContent = state === 'success'
            // Deliberately worded as an observation, not a confirmation. This
            // page cannot know a payment succeeded — only the backend does,
            // and the status card above it reflects what the backend actually
            // recorded.
            ? t('billing.returnSuccess', 'Checkout finished. Your plan below reflects what was processed.',
                'انتهت عملية الدفع. تعرض خطتك أدناه ما تمت معالجته فعليًا.')
            : t('billing.returnCanceled', 'Checkout was canceled. Nothing was charged.',
                'تم إلغاء عملية الدفع. لم يتم خصم أي مبلغ.');
    }

    // -----------------------------------------------------------------
    // Actions
    // -----------------------------------------------------------------

    async function reload() {
        const [subRes, entRes, cfgRes, histRes] = await Promise.all([
            API.billing.subscription().catch(() => null),
            API.billing.entitlements().catch(() => null),
            API.billing.config().catch(() => null),
            API.billing.history().catch(() => null),
        ]);

        subscription = subRes?.data || null;
        entitlements = entRes?.data || null;
        config = cfgRes?.data || config;

        renderSandboxNotice();
        renderStatus();
        renderUsage();
        renderHistory(histRes?.data?.events);
        renderSandboxTools();
    }

    async function withBusy(button, work) {
        if (button) button.disabled = true;
        try {
            await work();
            await reload();
        } catch (err) {
            Toast.error(err?.message || t('billing.actionFailed', 'That did not work. Please try again.',
                'لم تنجح العملية. حاول مرة أخرى.'));
        } finally {
            if (button) button.disabled = false;
        }
    }

    function confirmCancel() {
        const endsOn = formatDate(subscription?.current_period_end);
        return window.confirm(t('billing.confirmCancel',
            `Cancel your subscription? You keep Pro access until ${endsOn}, and nothing in your history is deleted.`,
            `هل تريد إلغاء اشتراكك؟ ستحتفظ بمزايا Pro حتى ${endsOn}، ولن يُحذف أي شيء من سجلك.`));
    }

    function onClick(event) {
        const action = event.target.closest('[data-billing-action]');
        if (action) {
            const button = action;
            switch (action.dataset.billingAction) {
                case 'upgrade':
                    BillingUI.openPricing({ returnPath: 'billing.html' });
                    break;
                case 'cancel':
                    if (confirmCancel()) withBusy(button, () => API.billing.cancel());
                    break;
                case 'resume':
                    withBusy(button, () => API.billing.resume());
                    break;
                case 'change-plan':
                    withBusy(button, () => API.billing.changePlan(action.dataset.plan));
                    break;
                case 'update-payment':
                    // No card fields exist in MedOrbit. In the sandbox the
                    // provider's management surface is this page; with a real
                    // provider this becomes a redirect to their hosted portal.
                    Toast.info(t('billing.updatePaymentSandbox',
                        'A payment provider is not connected yet, so there is no payment method to update.',
                        'لم يتم ربط مزود دفع بعد، لذلك لا توجد طريقة دفع لتحديثها.'));
                    break;
                default:
                    break;
            }
            return;
        }

        const simulate = event.target.closest('[data-simulate]');
        if (simulate) {
            withBusy(simulate, () => API.billing.sandbox.simulate(simulate.dataset.simulate));
        }
    }

    async function init() {
        if (!API.isAuthenticated?.()) return;
        document.addEventListener('click', onClick);
        renderReturnBanner();
        await reload();
    }

    return { init, reload };
})();

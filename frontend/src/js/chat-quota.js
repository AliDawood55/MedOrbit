/**
 * MedOrbit — free-allowance UI for the chatbot composer.
 *
 * Renders quota state that the SERVER computed. This module deliberately owns
 * no arithmetic about eligibility: it never decides whether a message is
 * allowed, never counts messages itself, and never persists a count anywhere.
 * Clearing cookies or editing localStorage cannot change what it shows,
 * because there is nothing here to edit — every number and deadline arrives
 * from /api/billing/entitlements or from the quota block on a send response.
 *
 * The one thing computed locally is the countdown, and only ever as the
 * difference between the browser clock and an absolute UTC instant the server
 * supplied. A skewed clock makes the countdown slightly wrong; it cannot make
 * a blocked composer usable, because the backend re-checks on every send.
 */
const ChatQuota = (() => {

    // Below this many remaining messages, the counter starts nudging toward
    // upgrading. Above it the UI stays quiet — a counter shouting at someone
    // on message three would be noise, not information.
    const NUDGE_THRESHOLD = 5;

    let state = null;
    let countdownTimer = null;

    function el(id) {
        return document.getElementById(id);
    }

    function isArabic() {
        return typeof I18n !== 'undefined' && I18n.getLang?.() === 'ar';
    }

    /** Ensure the counter/paywall nodes exist next to the composer. */
    function ensureMounted() {
        if (el('chatQuotaBar')) return el('chatQuotaBar');

        const composer = el('chatInput')?.closest('form, .chat-composer, .composer')
            || el('chatInput')?.parentElement;
        if (!composer || !composer.parentElement) return null;

        const bar = document.createElement('div');
        bar.id = 'chatQuotaBar';
        bar.className = 'chat-quota';
        bar.hidden = true;
        composer.parentElement.insertBefore(bar, composer);
        return bar;
    }

    function formatCountdown(msRemaining) {
        const total = Math.max(Math.floor(msRemaining / 1000), 0);
        const hours = Math.floor(total / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        const seconds = total % 60;
        if (hours > 0) return `${hours}h ${String(minutes).padStart(2, '0')}m`;
        if (minutes > 0) return `${minutes}m ${String(seconds).padStart(2, '0')}s`;
        return `${seconds}s`;
    }

    function stopCountdown() {
        if (countdownTimer) {
            clearInterval(countdownTimer);
            countdownTimer = null;
        }
    }

    /**
     * Count down toward a server-provided instant.
     *
     * resetsAt is an absolute UTC timestamp from the backend, so two devices in
     * different timezones show the same remaining time.
     */
    function startCountdown(resetsAt, onTick) {
        stopCountdown();
        if (!resetsAt) return;
        const target = new Date(resetsAt).getTime();
        if (Number.isNaN(target)) return;

        const tick = () => {
            const remaining = target - Date.now();
            if (remaining <= 0) {
                stopCountdown();
                // The window has rolled over. Ask the server what is true now
                // rather than assuming the allowance is back.
                refresh();
                return;
            }
            onTick(formatCountdown(remaining));
        };
        tick();
        countdownTimer = setInterval(tick, 1000);
    }

    function setComposerEnabled(enabled) {
        const input = el('chatInput');
        const sendBtn = el('sendBtn') || el('chatSendBtn');
        if (input) {
            input.disabled = !enabled;
            input.placeholder = enabled
                ? (input.dataset.originalPlaceholder || input.placeholder)
                : (isArabic() ? 'انتهت رسائلك المجانية لهذه الفترة' : 'Your free messages are used for this period');
            if (enabled && input.dataset.originalPlaceholder) {
                input.placeholder = input.dataset.originalPlaceholder;
            } else if (!enabled && !input.dataset.originalPlaceholder) {
                input.dataset.originalPlaceholder = input.placeholder;
            }
        }
        if (sendBtn) sendBtn.disabled = !enabled;
    }

    function renderRemaining(quota) {
        const bar = ensureMounted();
        if (!bar) return;

        // A Pro subscriber sees no quota furniture at all.
        if (quota.unlimited || quota.limit === null) {
            bar.hidden = true;
            setComposerEnabled(true);
            return;
        }

        stopCountdown();
        setComposerEnabled(true);
        bar.hidden = false;
        bar.classList.toggle('chat-quota--low', quota.remaining <= NUDGE_THRESHOLD);
        bar.classList.remove('chat-quota--blocked');

        const label = isArabic()
            ? `${quota.remaining} من ${quota.limit} رسالة مجانية متبقية`
            : `${quota.remaining} of ${quota.limit} free messages remaining`;

        // Upgrade context appears only as the allowance runs low.
        const nudge = quota.remaining <= NUDGE_THRESHOLD
            ? `<button type="button" class="chat-quota__upgrade" data-action="upgrade">${
                isArabic() ? 'الترقية إلى Pro' : 'Upgrade to Pro'}</button>`
            : '';

        bar.innerHTML = `<span class="chat-quota__label">${label}</span>${nudge}`;
    }

    function renderBlocked(details) {
        const bar = ensureMounted();
        if (!bar) return;

        bar.hidden = false;
        bar.classList.add('chat-quota--blocked');
        bar.classList.remove('chat-quota--low');
        setComposerEnabled(false);

        const heading = isArabic()
            ? 'انتهت رسائلك المجانية لهذه الفترة.'
            : 'Your free messages are used for this period.';
        const nextLabel = isArabic() ? 'الرسائل المجانية القادمة:' : 'Next free messages:';
        const upgrade = isArabic() ? 'الترقية إلى Pro' : 'Upgrade to Pro';

        bar.innerHTML = `
            <div class="chat-quota__heading">${heading}</div>
            <div class="chat-quota__countdown">
                <span>${nextLabel}</span> <strong id="chatQuotaCountdown">—</strong>
            </div>
            <button type="button" class="chat-quota__upgrade" data-action="upgrade">${upgrade}</button>
        `;

        startCountdown(details?.resets_at, (text) => {
            const node = el('chatQuotaCountdown');
            if (node) node.textContent = text;
        });
    }

    /** Apply the quota block returned alongside a chat reply. */
    function apply(quota) {
        if (!quota) return;
        state = quota;
        if (!quota.unlimited && quota.remaining === 0) {
            renderBlocked(quota);
        } else {
            renderRemaining(quota);
        }
    }

    /** Enter the blocked state after the server refused a message. */
    function lock(details) {
        state = { ...(state || {}), remaining: 0, ...details };
        renderBlocked(details);
    }

    /**
     * Ask the backend what this account is entitled to.
     *
     * Called on load and whenever a window is believed to have rolled over.
     * The answer is authoritative; nothing here second-guesses it.
     */
    async function refresh() {
        if (!API.isAuthenticated?.()) return null;
        try {
            const res = await API.billing.entitlements();
            const chatbot = res?.data?.features?.chatbot;
            if (!chatbot) return null;

            if (chatbot.unlimited) {
                apply({ unlimited: true, limit: null, remaining: null });
            } else {
                apply({
                    unlimited: false,
                    used: chatbot.used,
                    limit: chatbot.limit,
                    remaining: chatbot.remaining,
                    resets_at: chatbot.resets_at,
                });
            }
            return res.data;
        } catch (_) {
            // Entitlement is unavailable — leave the composer as it is rather
            // than locking someone out because a status call failed. The send
            // path is still enforced server-side, so this is safe.
            return null;
        }
    }

    function init() {
        document.addEventListener('click', (event) => {
            const trigger = event.target.closest('[data-action="upgrade"]');
            if (!trigger) return;
            // Open pricing over the conversation rather than navigating away
            // from it. A successful checkout returns to this page, where the
            // refresh below unlocks the composer — the conversation is still
            // there, because nothing about upgrading touches chat history.
            if (typeof BillingUI !== 'undefined') {
                BillingUI.openPricing({ returnPath: 'index.html' });
            } else {
                window.location.href = 'billing.html';
            }
        });

        // Re-ask the server when the tab becomes visible again. This is what
        // makes the composer usable straight after returning from checkout,
        // and it also picks up a subscription that lapsed while the tab sat
        // in the background. The answer is always the server's; nothing here
        // infers that a payment succeeded.
        document.addEventListener('visibilitychange', () => {
            if (document.visibilityState === 'visible') refresh();
        });
        window.addEventListener('pageshow', (event) => {
            if (event.persisted) refresh();
        });

        refresh();
    }

    return { init, apply, lock, refresh, getState: () => state };
})();

if (typeof document !== 'undefined') {
    document.addEventListener('DOMContentLoaded', () => ChatQuota.init());
}

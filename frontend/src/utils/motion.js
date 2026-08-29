const Motion = (() => {

    const animatedEls = new WeakSet();

    function reduced() {
        return typeof window.matchMedia === 'function' &&
            window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }

function staggerIn(container, itemSelector, options = {}) {
        if (!container || animatedEls.has(container)) return;
        animatedEls.add(container);

        if (reduced()) return;

        const items = itemSelector
            ? container.querySelectorAll(itemSelector)
            : container.children;

        const stepMs = options.stepMs ?? 30;
        const maxDelayMs = options.maxDelayMs ?? 240;

        Array.prototype.forEach.call(items, (el, i) => {
            el.classList.add('fade-in-item');
            el.style.animationDelay = Math.min(i * stepMs, maxDelayMs) + 'ms';
        });
    }

function countUp(el, target, options = {}) {
        if (!el) return;

        const duration = Math.min(options.duration ?? 250, 300);
        const format = options.format || ((n) => String(Math.round(n)));

        if (animatedEls.has(el) || reduced()) {
            animatedEls.add(el);
            el.textContent = format(target);
            return;
        }
        animatedEls.add(el);

        const start = performance.now();

        function tick(now) {
            const elapsed = now - start;
            const progress = Math.min(elapsed / duration, 1);
            const eased = 1 - Math.pow(1 - progress, 2);
            el.textContent = format(target * eased);
            if (progress < 1) requestAnimationFrame(tick);
            else el.textContent = format(target);
        }

        requestAnimationFrame(tick);
    }

    return { staggerIn, countUp, reduced };

})();

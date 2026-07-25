/**
 * MedOrbit v2 - Motion Utilities
 * Tiny, dependency-free helpers for the subtle-motion system: staggered
 * list entrance and number count-up. Both respect prefers-reduced-motion
 * and are safe to call repeatedly — each only animates a given element
 * once (tracked via a WeakSet), so re-rendering the same list on a
 * language or theme change never replays the entrance animation.
 */
const Motion = (() => {

    const animatedEls = new WeakSet();

    function reduced() {
        return typeof window.matchMedia === 'function' &&
            window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }

    /**
     * Applies a fade/slide-in with a small incremental delay to each direct
     * child matching itemSelector inside container. Only runs once per
     * container instance — safe to call again after a full re-render
     * (e.g. on language change) without replaying the animation.
     *
     * @param {HTMLElement} container
     * @param {string} [itemSelector] - defaults to all direct children
     * @param {object} [options]
     * @param {number} [options.stepMs=30] - delay increment per item
     * @param {number} [options.maxDelayMs=240] - cap on total stagger delay
     */
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

    /**
     * Animates a number from 0 (or from) to `target` over `duration` ms,
     * writing the formatted value into el.textContent each frame. Only
     * animates a given element once — subsequent calls (e.g. after a
     * language-change re-render) just set the final value immediately so
     * the count-up never replays.
     *
     * @param {HTMLElement} el
     * @param {number} target
     * @param {object} [options]
     * @param {number} [options.duration=250] - ms, kept short by design
     * @param {(n:number)=>string} [options.format] - defaults to Math.round
     */
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
            const eased = 1 - Math.pow(1 - progress, 2); // ease-out-quad
            el.textContent = format(target * eased);
            if (progress < 1) requestAnimationFrame(tick);
            else el.textContent = format(target);
        }

        requestAnimationFrame(tick);
    }

    return { staggerIn, countUp, reduced };

})();

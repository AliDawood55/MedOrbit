/**
 * MedOrbit v2 - DOM Utilities
 * Small helpers to reduce boilerplate.
 */

const Dom = (() => {
    /**
     * Shorthand querySelector
     */
    const $ = (sel, root = document) => root.querySelector(sel);
    const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

    /**
     * Create an HTML element with attributes and children
     * @param {string} tag - HTML tag name
     * @param {Object} attrs - attributes (class, id, data-*, etc.)
     * @param {Array|string|HTMLElement} children - children to append
     */
    function el(tag, attrs = {}, children = []) {
        const node = document.createElement(tag);

        for (const [key, val] of Object.entries(attrs)) {
            if (key === 'className') node.className = val;
            else if (key === 'text') node.textContent = val;
            else if (key === 'html') node.innerHTML = val;
            else if (key.startsWith('on') && typeof val === 'function') {
                node.addEventListener(key.slice(2).toLowerCase(), val);
            } else if (key === 'dataset' && typeof val === 'object') {
                for (const [dk, dv] of Object.entries(val)) {
                    node.dataset[dk] = dv;
                }
            } else if (val === true) {
                node.setAttribute(key, '');
            } else if (val === false || val == null) {
                // skip
            } else {
                node.setAttribute(key, val);
            }
        }

        if (children) {
            const arr = Array.isArray(children) ? children : [children];
            for (const child of arr) {
                if (child == null) continue;
                if (typeof child === 'string' || typeof child === 'number') {
                    node.appendChild(document.createTextNode(String(child)));
                } else {
                    node.appendChild(child);
                }
            }
        }

        return node;
    }

    /**
     * Debounce: call fn after `wait` ms of silence
     */
    function debounce(fn, wait = 300) {
        let timer = null;
        return function (...args) {
            clearTimeout(timer);
            timer = setTimeout(() => fn.apply(this, args), wait);
        };
    }

    /**
     * Throttle: call fn at most once per `wait` ms
     */
    function throttle(fn, wait = 300) {
        let last = 0;
        let timer = null;
        return function (...args) {
            const now = Date.now();
            if (now - last >= wait) {
                last = now;
                fn.apply(this, args);
            } else {
                clearTimeout(timer);
                timer = setTimeout(() => {
                    last = Date.now();
                    fn.apply(this, args);
                }, wait - (now - last));
            }
        };
    }

    /**
     * Escape HTML special chars
     */
    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    /**
     * Smooth scroll an element to bottom
     */
    function scrollToBottom(el) {
        if (!el) return;
        requestAnimationFrame(() => {
            el.scrollTop = el.scrollHeight;
        });
    }

    /**
     * Reference-counted body scroll lock — for overlays (drawer, mobile
     * sidebar, bottom sheet) that should block background scroll while
     * open. Counted so two overlays opening/closing in any order can never
     * unlock the body while another is still up.
     */
    let scrollLockCount = 0;
    function lockScroll() {
        scrollLockCount++;
        document.body.classList.add('scroll-locked');
    }
    function unlockScroll() {
        scrollLockCount = Math.max(0, scrollLockCount - 1);
        if (scrollLockCount === 0) {
            document.body.classList.remove('scroll-locked');
        }
    }

    return { $, $$, el, debounce, throttle, escapeHtml, scrollToBottom, lockScroll, unlockScroll };
})();
/**
 * MedOrbit v2 - Toast Module
 * Shared across every page. Requires a #toastContainer element in the DOM.
 */
const Toast = (() => {
    const URGENT = new Set(['error', 'warning']);

    function show(message, type = 'info', duration = 3000) {
        const container = document.getElementById('toastContainer');
        if (!container) return;

        // One announcement owner: the container carries the live-region
        // semantics, toasts themselves carry none, so a toast's text is
        // announced exactly once when it lands in the region.
        const role = URGENT.has(type) ? 'alert' : 'status';
        if (container.getAttribute('role') !== role) {
            container.setAttribute('role', role);
            container.setAttribute('aria-live', role === 'alert' ? 'assertive' : 'polite');
        }

        const icons = {
            success: 'fa-check-circle',
            error: 'fa-times-circle',
            warning: 'fa-exclamation-triangle',
            info: 'fa-info-circle'
        };

        const toast = document.createElement('div');
        toast.className = `toast ${type}`;

        const icon = document.createElement('i');
        icon.className = `fas ${icons[type] || icons.info}`;
        icon.setAttribute('aria-hidden', 'true');

        const text = document.createElement('span');
        text.textContent = message;

        toast.appendChild(icon);
        toast.appendChild(text);
        container.appendChild(toast);

        setTimeout(() => {
            toast.style.opacity = '0';
            toast.style.transform = 'translateY(-10px)';
            setTimeout(() => toast.remove(), 300);
        }, duration);
    }

    return {
        success: (m, d) => show(m, 'success', d),
        error: (m, d) => show(m, 'error', d),
        warning: (m, d) => show(m, 'warning', d),
        info: (m, d) => show(m, 'info', d)
    };
})();

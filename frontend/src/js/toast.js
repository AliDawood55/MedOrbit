/**
 * MedOrbit v2 - Toast Module
 * Shared across every page. Requires a #toastContainer element in the DOM.
 */
const Toast = (() => {
    function show(message, type = 'info', duration = 3000) {
        const container = document.getElementById('toastContainer');
        if (!container) return;

        const icons = {
            success: 'fa-check-circle',
            error: 'fa-times-circle',
            warning: 'fa-exclamation-triangle',
            info: 'fa-info-circle'
        };

        const toast = document.createElement('div');
        toast.className = `toast ${type}`;
        toast.innerHTML = `<i class="fas ${icons[type] || icons.info}"></i><span>${message}</span>`;
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

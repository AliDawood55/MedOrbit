const Theme = (() => {
    let current = Store.getTheme() || 'light';

    function apply() {
        document.body.setAttribute('data-theme', current);
        const btn = document.getElementById('themeToggle');
        if (btn) {
            const icon = btn.querySelector('i');
            if (icon) {
                icon.className = current === 'dark' ? 'fas fa-sun' : 'fas fa-moon';
            }
        }
        Store.setTheme(current);
    }

    function toggle() {
        current = current === 'light' ? 'dark' : 'light';
        apply();
    }

    return { apply, toggle, get: () => current };
})();

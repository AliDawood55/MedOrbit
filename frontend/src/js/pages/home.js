document.addEventListener('DOMContentLoaded', () => {
    Layout.init();
    FeedbackDashboard.init();

function applySessionState() {
        const loggedIn = API.isAuthenticated();

        const heroBtn = document.getElementById('heroPrimaryBtn');
        if (heroBtn) heroBtn.href = loggedIn ? 'dashboard.html' : 'index.html';

        const heroIcon = document.getElementById('heroPrimaryIcon');
        if (heroIcon) {
            heroIcon.classList.toggle('fa-gauge-high', loggedIn);
            heroIcon.classList.toggle('fa-comments', !loggedIn);
        }

        const heroLabel = document.getElementById('heroPrimaryLabel');
        if (heroLabel) {
            heroLabel.setAttribute('data-i18n', loggedIn ? 'home.goToDashboard' : 'home.startChat');
        }

        document.getElementById('ctaRegisterBtn')?.classList.toggle('hidden', loggedIn);
        document.getElementById('ctaDashboardBtn')?.classList.toggle('hidden', !loggedIn);

        if (typeof I18n !== 'undefined') I18n.apply();
    }

    function localizeFacilityDiscovery() {
        const label = document.getElementById('heroFacilityDiscoveryLabel');
        if (!label) return;
        label.textContent = I18n?.getLang?.() === 'ar'
            ? 'اكتشف المنشآت الصحية'
            : 'Find healthcare facilities';
    }

    applySessionState();
    localizeFacilityDiscovery();
    window.addEventListener('auth:changed', applySessionState);
    window.addEventListener('languageChanged', localizeFacilityDiscovery);

document.getElementById('heroSearchForm')?.addEventListener('submit', (e) => {
        e.preventDefault();
        const q = document.getElementById('heroSearchInput')?.value.trim();
        const type = document.getElementById('heroSearchType')?.value;
        const target = type === 'clinics' ? 'find-clinics.html' : 'find-doctors.html';
        AuthGate.navigate(
            target + (q ? '?search=' + encodeURIComponent(q) : ''),
            e.submitter || document.getElementById('heroSearchInput')
        );
    });
});

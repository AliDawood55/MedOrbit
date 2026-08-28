document.addEventListener('DOMContentLoaded', () => {
    Layout.init();
    MapApp.init();
    LocationPicker.mount('locationPicker');
    FindClinics.init();

    setTimeout(() => {
        document.getElementById('appLoader')?.classList.add('hidden');
        const app = document.getElementById('app');
        if (app) app.style.visibility = 'visible';
    }, 400);

    document.getElementById('fitAllBtn')?.addEventListener('click', () => MapApp.fitToMarkers());

    document.getElementById('mobileViewToggle')?.addEventListener('click', function () {
        const main = document.querySelector('.app-main');
        if (!main) return;
        const showingMap = main.classList.toggle('mobile-show-map');

document.documentElement.classList.toggle('mobile-map-active', showingMap);
        document.body.classList.toggle('mobile-map-active', showingMap);
        this.innerHTML = showingMap ? '<i class="fas fa-list"></i>' : '<i class="fas fa-map-location-dot"></i>';
        const viewLabel = I18n.t(showingMap ? 'common.showList' : 'common.showMap');
        this.title = viewLabel;
        this.setAttribute('aria-label', viewLabel);
        if (showingMap) MapApp.invalidateSize();
    });
});

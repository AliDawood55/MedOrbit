/**
 * MedOrbit v2 - Location Picker UI
 * Renders a status pill + dropdown (GPS / pick-on-map / choose district)
 * into a container, backed entirely by the shared Location module. Mounted
 * on index.html (chat/map page) and find-clinics.html — same UI, same state.
 */
const LocationPicker = (() => {

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

    function t(ar, en) {
        return isAr() ? ar : en;
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function pillContent(state) {
        if (state.status === 'locating') {
            return { icon: 'fa-circle-notch fa-spin', text: t('جارِ تحديد موقعك...', 'Locating you...'), cls: 'locating' };
        }
        if (state.status === 'resolved') {
            const acc = state.accuracy != null ? Math.round(state.accuracy) : null;
            const accText = acc != null ? t(`دقة ~${acc}م`, `~${acc}m accuracy`) : t('تم التحديد', 'Located');
            return { icon: 'fa-location-crosshairs', text: accText, cls: 'resolved' };
        }
        if (state.status === 'manual') {
            const name = state.label ? (isAr() ? state.label.ar : state.label.en) : t('موقع مخصص', 'Custom point');
            return { icon: 'fa-map-pin', text: name, cls: 'manual' };
        }
        if (state.status === 'error') {
            return { icon: 'fa-triangle-exclamation', text: t('تعذر تحديد الموقع', 'Location unavailable'), cls: 'error' };
        }
        return { icon: 'fa-location-dot', text: t('حدد موقعك', 'Set your location'), cls: 'idle' };
    }

    const mounted = new Set();

    function mount(containerId) {
        if (mounted.has(containerId)) {
            relabel(containerId);
            return;
        }
        mounted.add(containerId);

        const container = document.getElementById(containerId);
        if (!container) return;

        const districts = Location.getDistricts();

        container.className = (container.className + ' location-picker').trim();
        container.innerHTML =
            '<button type="button" class="location-pill" id="' + containerId + 'PillBtn">' +
                '<span class="location-pill-icon"><i class="fas"></i></span><span class="location-pill-text"></span>' +
            '</button>' +
            '<div class="location-menu" id="' + containerId + 'Menu">' +
                '<div class="location-error-note" id="' + containerId + 'ErrorNote" style="display:none;"></div>' +
                '<button type="button" class="location-menu-item" data-action="gps">' +
                    '<i class="fas fa-location-crosshairs"></i><span>' + t('استخدام موقعي (GPS)', 'Use my GPS location') + '</span>' +
                '</button>' +
                '<button type="button" class="location-menu-item" data-action="pick-map">' +
                    '<i class="fas fa-map-pin"></i><span>' + t('اختيار من الخريطة', 'Pick a point on the map') + '</span>' +
                '</button>' +
                '<div class="location-menu-label">' + t('أو اختر منطقة تقريبية', 'Or choose an approximate area') + '</div>' +
                '<div class="location-district-list">' +
                    districts.map((d) =>
                        '<button type="button" class="location-district-btn" data-district="' + d.id + '">' +
                            escapeHtml(isAr() ? d.ar : d.en) +
                        '</button>'
                    ).join('') +
                '</div>' +
            '</div>';

        const pillBtn = document.getElementById(containerId + 'PillBtn');
        const menu = document.getElementById(containerId + 'Menu');
        const errorNote = document.getElementById(containerId + 'ErrorNote');

        // Bottom-sheet backdrop on mobile (see map.css) — harmless on desktop
        // where the menu is a small anchored dropdown instead.
        const backdrop = document.createElement('div');
        backdrop.className = 'location-menu-backdrop';
        document.body.appendChild(backdrop);

        function isBottomSheet() {
            return typeof window.matchMedia === 'function' && window.matchMedia('(max-width: 768px)').matches;
        }

        function closeMenu() {
            const wasOpen = menu.classList.contains('open');
            menu.classList.remove('open');
            backdrop.classList.remove('open');
            // Only the mobile bottom-sheet variant locks the background —
            // the desktop dropdown is small and shouldn't block page scroll.
            if (wasOpen && isBottomSheet() && typeof Dom !== 'undefined') Dom.unlockScroll();
        }

        function openMenu() {
            document.querySelectorAll('.location-menu.open').forEach((m) => m.classList.remove('open'));
            document.querySelectorAll('.location-menu-backdrop.open').forEach((b) => b.classList.remove('open'));
            menu.classList.add('open');
            backdrop.classList.add('open');
            if (isBottomSheet() && typeof Dom !== 'undefined') Dom.lockScroll();
        }

        function render(state) {
            const { icon, text, cls } = pillContent(state);
            pillBtn.className = 'location-pill ' + cls;
            // Rebuilt fresh each time (not mutated in place) — FontAwesome's
            // JS kit replaces <i> tags with inline <svg> shortly after they're
            // added, so a stale reference to the original <i> goes null.
            pillBtn.querySelector('.location-pill-icon').innerHTML = '<i class="fas ' + icon + '"></i>';
            pillBtn.querySelector('.location-pill-text').textContent = text;

            if (state.status === 'error' && state.errorCode) {
                errorNote.textContent = Location.errorMessage(state.errorCode);
                errorNote.style.display = 'block';
            } else {
                errorNote.style.display = 'none';
            }
        }

        pillBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            if (menu.classList.contains('open')) closeMenu();
            else openMenu();
        });

        menu.querySelector('[data-action="gps"]').addEventListener('click', () => {
            Location.locate(true);
            closeMenu();
        });

        menu.querySelector('[data-action="pick-map"]').addEventListener('click', () => {
            closeMenu();
            if (typeof MapApp !== 'undefined' && MapApp.enablePickMode) {
                MapApp.enablePickMode();
                if (typeof Toast !== 'undefined') {
                    Toast.info(t('انقر على أي نقطة على الخريطة لتحديد موقعك', 'Click anywhere on the map to set your location'));
                }
            }
        });

        menu.querySelectorAll('.location-district-btn').forEach((btn) => {
            btn.addEventListener('click', () => {
                Location.setDistrict(btn.dataset.district);
                closeMenu();
            });
        });

        document.addEventListener('click', closeMenu);
        backdrop.addEventListener('click', closeMenu);

        Location.onChange(render);
        render(Location.getState());
    }

    /**
     * Language toggled after this picker was already mounted — re-render its
     * static labels (menu items, district names) and current pill text
     * without tearing down the DOM or re-subscribing to Location.
     */
    function relabel(containerId) {
        const menu = document.getElementById(containerId + 'Menu');
        if (!menu) return;

        menu.querySelector('[data-action="gps"] span').textContent = t('استخدام موقعي (GPS)', 'Use my GPS location');
        menu.querySelector('[data-action="pick-map"] span').textContent = t('اختيار من الخريطة', 'Pick a point on the map');
        menu.querySelector('.location-menu-label').textContent = t('أو اختر منطقة تقريبية', 'Or choose an approximate area');

        const districts = Location.getDistricts();
        menu.querySelectorAll('.location-district-btn').forEach((btn) => {
            const d = districts.find((x) => x.id === btn.dataset.district);
            if (d) btn.textContent = isAr() ? d.ar : d.en;
        });

        const pillBtn = document.getElementById(containerId + 'PillBtn');
        if (pillBtn) {
            const { text } = pillContent(Location.getState());
            pillBtn.querySelector('.location-pill-text').textContent = text;
        }

        const errorNote = document.getElementById(containerId + 'ErrorNote');
        const state = Location.getState();
        if (errorNote && state.status === 'error' && state.errorCode) {
            errorNote.textContent = Location.errorMessage(state.errorCode);
        }
    }

    window.addEventListener('languageChanged', () => {
        mounted.forEach((id) => relabel(id));
    });

    return { mount };

})();

const FindClinics = (() => {

    const PAGE_SIZE = 20;
    const NEARBY_RADIUS_KM = 10;
    const FACILITY_TYPES = Object.freeze({
        clinic: { labelKey: 'filter.clinic', icon: 'fa-hospital', category: 'clinic' },
        dental: { labelKey: 'filter.dental', icon: 'fa-tooth', category: 'dental' },
        hospital: { labelKey: 'filter.hospital', icon: 'fa-hospital-user', category: 'hospital' },
        pharmacy: { labelKey: 'filter.pharmacy', icon: 'fa-pills', category: 'pharmacy' },
        laboratory: { icon: 'fa-flask', category: 'healthcare', labels: ['المختبرات', 'Laboratories'] },
        radiology: { icon: 'fa-x-ray', category: 'healthcare', labels: ['مراكز الأشعة', 'Radiology centres'] },
        emergency: { icon: 'fa-truck-medical', category: 'healthcare', labels: ['مراكز الطوارئ', 'Emergency centres'] }
    });
    const GENERIC_FACILITY = Object.freeze({
        labelKey: 'filter.healthcare', icon: 'fa-notes-medical', category: 'healthcare'
    });

    let mode = 'list';
    let currentType = '';
    let currentCity = '';
    let currentService = '';
    let currentOpenNow = false;
    let currentPage = 1;
    let searchDebounceTimer = null;
    let activeController = null;
    const LIST_CACHE_TTL = 60000;

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    }

    function t(key) {
        return typeof I18n !== 'undefined' ? I18n.t(key) : key;
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function optionalText(value) {
        if (value == null) return '';
        const text = String(value).trim();
        return /^(?:n\/?a|undefined|null)$/i.test(text) ? '' : text;
    }

    function typePresentation(type) {
        const key = optionalText(type).toLowerCase();
        return FACILITY_TYPES[key] || GENERIC_FACILITY;
    }

    function clinicName(c) {
        return optionalText(isAr() ? c.name_ar : c.name_en) || optionalText(c.name_ar) || optionalText(c.name_en);
    }

    function clinicAddress(c) {
        return optionalText(isAr() ? c.address_ar : c.address_en) || optionalText(c.address_ar) || optionalText(c.address_en);
    }

    function toPlace(c) {
        const type = typePresentation(c.type);
        return {
            id: c.id,
            name: clinicName(c),
            lat: parseFloat(c.latitude),
            lng: parseFloat(c.longitude),
            type: type.category,
            phone: optionalText(c.phone),
            address: clinicAddress(c),
            distance: c.distance_km != null ? Number(c.distance_km) * 1000 : null,
            rating: c.average_rating
        };
    }

async function loadList(page = 1) {
        mode = 'list';
        currentPage = page;

        const content = document.getElementById('clinicsListContent');
        if (!content) return;

        if (activeController) activeController.abort();
        activeController = API.makeCancellable();

        content.innerHTML = renderSkeleton();

        const query = {
            page,
            limit: PAGE_SIZE,
            search: document.getElementById('searchInput')?.value.trim(),
            type: currentType || undefined,
            city: currentCity || undefined,
            service: currentService || undefined
        };

        try {
            const res = await API.clinics.list(query, { signal: activeController.signal, cacheTTL: LIST_CACHE_TTL });
            const { clinics: responseClinics, pagination } = res.data;
            const clinics = filteredByOpenNow(responseClinics || []);

            if (!clinics || clinics.length === 0) {
                content.innerHTML = renderEmpty();
                MapApp.clearResults();
                return;
            }

            const places = clinics.map(toPlace);
            content.innerHTML = clinics.map(c => renderCard(c, false)).join('') + renderPagination(pagination);
            MapApp.renderPlaces(places);

        } catch (err) {
            if (err.name === 'AbortError') return;
            console.error('FindClinics: failed to load list', err);
            content.innerHTML = renderError();
        }
    }

function loadNearby() {
        const content = document.getElementById('clinicsListContent');
        if (!content) return;

        if (typeof Location === 'undefined') {
            if (typeof Toast !== 'undefined') Toast.error(isAr() ? 'تعذر تحديد الموقع' : 'Location is unavailable');
            return;
        }

        mode = 'nearby';
        content.innerHTML = '<div class="empty-state"><div class="spinner spinner-lg" style="margin:0 auto 16px;"></div><p>' + escapeHtml(t('clinics.locating')) + '</p></div>';

const unsubscribe = Location.onChange(handleLocationUpdate);
        Location.locate(true);

        function handleLocationUpdate(state) {
            if (state.status === 'locating') return;
            unsubscribe();

            if (state.coords) {
                fetchNearby(state.coords.lat, state.coords.lng);
            } else {
                const message = state.errorCode
                    ? Location.errorMessage(state.errorCode)
                    : (isAr() ? 'تعذر تحديد موقعك' : 'Could not determine your location');
                if (typeof Toast !== 'undefined') Toast.error(message);
                loadList(1);
            }
        }
    }

    async function fetchNearby(lat, lng) {
        const content = document.getElementById('clinicsListContent');
        if (!content) return;

        if (activeController) activeController.abort();
        activeController = API.makeCancellable();

        try {
            const res = await API.clinics.nearby({
                lat, lng,
                radius: NEARBY_RADIUS_KM,
                type: currentType || undefined
            }, { signal: activeController.signal, cacheTTL: LIST_CACHE_TTL });

            const clinics = filteredByOpenNow(res.data.clinics || []);

            if (clinics.length === 0) {
                content.innerHTML = renderEmpty();
                MapApp.clearResults();
                return;
            }

            const places = clinics.map(toPlace);
            content.innerHTML = clinics.map(c => renderCard(c, true)).join('');
            MapApp.renderPlaces(places);

        } catch (err) {
            if (err.name === 'AbortError') return;
            console.error('FindClinics: nearby search failed', err);
            content.innerHTML = renderError();
        }
    }

function renderSkeleton() {
        const row = '<div class="entity-card" style="margin-bottom:10px;"><div class="entity-card-body">' +
            '<div class="skeleton" style="width:44px;height:44px;border-radius:50%;flex-shrink:0;"></div>' +
            '<div style="flex:1;"><div class="skeleton" style="height:14px;width:60%;margin-bottom:8px;"></div>' +
            '<div class="skeleton" style="height:11px;width:40%;"></div></div>' +
            '</div></div>';
        return row.repeat(5);
    }

    function renderEmpty() {
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas fa-map-location-dot"></i></div>' +
            '<h3>' + escapeHtml(t('clinics.empty')) + '</h3>' +
        '</div>';
    }

    function renderError() {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('clinics.error')) + '</p>' +
            '<button type="button" class="btn btn-secondary btn-sm" id="retryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
        '</div>';
    }

    function renderCard(c, showDistance) {
        const cName = escapeHtml(clinicName(c));
        const address = escapeHtml(clinicAddress(c));
        const type = typePresentation(c.type);
        const facilityTypeLabel = escapeHtml(typeLabel(type));
        const distText = showDistance && c.distance_km != null ? Number(c.distance_km).toFixed(2) + (isAr() ? ' كم' : ' km') : '';
        const phone = escapeHtml(optionalText(c.phone));
        const verifiedBadge = c.verification_status === 'verified'
            ? '<span class="badge badge-success"><i class="fas fa-circle-check"></i> ' + escapeHtml(t('clinic.verified')) + '</span>'
            : '';
        const opening = openingState(c);
        const copy = localCopy();
        const hoursStatus = '<div class="clinic-directory-status ' + (opening === 'open' ? 'is-open' : opening === 'closed' ? 'is-closed' : '') + '"><i class="fas fa-clock"></i>' + escapeHtml(opening === 'open' ? copy.open : opening === 'closed' ? copy.closed : copy.hoursUnavailable) + '</div>';
        const directionsUrl = c.latitude != null && c.longitude != null
            ? 'https://www.google.com/maps/dir/?api=1&destination=' + encodeURIComponent(c.latitude + ',' + c.longitude)
            : null;

        return (
            '<div class="entity-card" style="margin-bottom:10px;" data-clinic-id="' + escapeHtml(c.id) + '">' +
                '<div class="entity-card-body">' +
                    '<div class="entity-avatar" style="background:var(--cat-' + type.category + ', var(--primary-gradient));"><i class="fas ' + type.icon + '"></i></div>' +
                    '<div class="entity-card-info">' +
                        '<div class="entity-card-title">' + cName + '</div>' +
                        (address ? '<div class="entity-card-subtitle" style="color:var(--text-mute);font-weight:500;">' + address + '</div>' : '') +
                        (verifiedBadge ? '<div class="entity-card-badges">' + verifiedBadge + '</div>' : '') +
                        hoursStatus +
                        '<div class="entity-card-meta">' +
                            '<span><i class="fas ' + type.icon + '"></i>' + facilityTypeLabel + '</span>' +
                            (distText ? '<span><i class="fas fa-route"></i>' + distText + '</span>' : '') +
                            (phone ? '<span><i class="fas fa-phone"></i>' + phone + '</span>' : '') +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="entity-card-footer clinic-directory-card-actions">' +
                    '<a class="btn btn-primary btn-sm" href="clinic.html?id=' + encodeURIComponent(c.id) + '">' +
                        '<i class="fas fa-circle-info"></i> ' + escapeHtml(t('clinics.viewDetails')) +
                    '</a>' +
                    (directionsUrl ? '<a class="btn btn-secondary btn-sm" href="' + directionsUrl + '" target="_blank" rel="noopener"><i class="fas fa-route"></i> ' + escapeHtml(copy.directions) + '</a>' : '') +
                '</div>' +
            '</div>'
        );
    }

    function renderPagination(pageInfo) {
        if (!pageInfo || pageInfo.totalPages <= 1) return '';

        const { page, totalPages } = pageInfo;
        let html = '<div class="pagination">';
        html += `<button type="button" class="pagination-btn" data-page="${page - 1}" ${page <= 1 ? 'disabled' : ''}><i class="fas fa-chevron-${isAr() ? 'right' : 'left'}"></i></button>`;

        const start = Math.max(1, page - 2);
        const end = Math.min(totalPages, page + 2);
        for (let p = start; p <= end; p++) {
            html += `<button type="button" class="pagination-btn${p === page ? ' active' : ''}" data-page="${p}">${p}</button>`;
        }

        html += `<button type="button" class="pagination-btn" data-page="${page + 1}" ${page >= totalPages ? 'disabled' : ''}><i class="fas fa-chevron-${isAr() ? 'left' : 'right'}"></i></button>`;
        html += '</div>';
        return html;
    }

    // ================= INIT =================

    const SERVICE_LABELS = {
        cardiology: ['القلب', 'Cardiology'], orthopedics: ['العظام', 'Orthopedics'], dentistry: ['الأسنان', 'Dentistry'], dermatology: ['الجلدية', 'Dermatology'], pediatrics: ['الأطفال', 'Pediatrics'], gynecology: ['النسائية', 'Gynecology'], general_medicine: ['الطب العام', 'General medicine'], laboratory: ['المختبر', 'Laboratory'], radiology: ['الأشعة', 'Radiology'], emergency: ['الطوارئ', 'Emergency']
    };

    async function loadDirectoryFilters() {
        try {
            const response = await API.clinics.directoryFilters({ cacheTTL: LIST_CACHE_TTL });
            const data = response.data || {};
            const city = document.getElementById('cityFilter');
            const service = document.getElementById('serviceFilter');
            if (city) city.innerHTML = '<option value="">' + escapeHtml(localCopy().allCities) + '</option>' + (data.cities || []).map((value) => `<option value="${escapeHtml(value)}" ${value === currentCity ? 'selected' : ''}>${escapeHtml(value)}</option>`).join('');
            if (service) service.innerHTML = '<option value="">' + escapeHtml(localCopy().allServices) + '</option>' + (data.services || []).map((value) => { const label = SERVICE_LABELS[value]; return `<option value="${escapeHtml(value)}" ${value === currentService ? 'selected' : ''}>${escapeHtml(label ? (isAr() ? label[0] : label[1]) : value)}</option>`; }).join('');
        } catch (err) { console.warn('FindClinics: filters unavailable', err); }
    }

    function typeLabel(presentation) {
        return presentation.labels ? presentation.labels[isAr() ? 0 : 1] : t(presentation.labelKey);
    }

    function localCopy() {
        return isAr()
            ? { openNow: 'مفتوح الآن', open: 'مفتوح الآن', closed: 'مغلق الآن', hoursUnavailable: 'ساعات العمل غير متوفرة', directions: 'الاتجاهات', laboratories: 'المختبرات', radiology: 'مراكز الأشعة', allCities: 'كل المدن', allServices: 'كل الخدمات' }
            : { openNow: 'Open now', open: 'Open now', closed: 'Closed now', hoursUnavailable: 'Hours unavailable', directions: 'Get directions', laboratories: 'Laboratories', radiology: 'Radiology centres', allCities: 'All cities', allServices: 'All services' };
    }

    function applyDirectoryLabels() {
        const copy = localCopy();
        const labels = [
            ['openNowLabel', copy.openNow],
            ['laboratoryTypeLabel', copy.laboratories],
            ['radiologyTypeLabel', copy.radiology]
        ];
        labels.forEach(([id, value]) => { const element = document.getElementById(id); if (element) element.textContent = value; });
    }

    function timeInClinicTimezone() {
        const parts = new Intl.DateTimeFormat('en-US', { timeZone: 'Asia/Hebron', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date());
        const value = (name) => parts.find((part) => part.type === name)?.value;
        const weekdays = { Sun: 'sun', Mon: 'mon', Tue: 'tue', Wed: 'wed', Thu: 'thu', Fri: 'fri', Sat: 'sat' };
        return { day: weekdays[value('weekday')], minutes: Number(value('hour')) * 60 + Number(value('minute')) };
    }

    function minutesFromTime(value) {
        const match = String(value || '').match(/^(\d{1,2}):(\d{2})/);
        if (!match) return null;
        const hours = Number(match[1]); const minutes = Number(match[2]);
        return hours <= 23 && minutes <= 59 ? hours * 60 + minutes : null;
    }

    // Only a structured schedule can qualify as open. We use the clinic
    // directory's Palestine timezone and correctly support overnight hours.
    function openingState(clinic) {
        const schedule = clinic?.operating_hours;
        if (!schedule || typeof schedule !== 'object' || Array.isArray(schedule)) return 'unknown';
        const now = timeInClinicTimezone(); const slot = schedule[now.day];
        if (!slot || slot.is_off) return 'closed';
        const open = minutesFromTime(slot.open); const close = minutesFromTime(slot.close);
        if (open == null || close == null || open === close) return 'unknown';
        return (close > open ? now.minutes >= open && now.minutes < close : now.minutes >= open || now.minutes < close) ? 'open' : 'closed';
    }

    function filteredByOpenNow(clinics) {
        return currentOpenNow ? clinics.filter((clinic) => openingState(clinic) === 'open') : clinics;
    }

    function init() {
        const params = new URLSearchParams(window.location.search);
        const initialSearch = params.get('search');
        if (initialSearch) {
            const input = document.getElementById('searchInput');
            if (input) input.value = initialSearch;
        }

        applyDirectoryLabels();
        loadDirectoryFilters();
        loadList(1);

        document.getElementById('searchInput')?.addEventListener('input', () => {
            clearTimeout(searchDebounceTimer);
            searchDebounceTimer = setTimeout(() => loadList(1), 400);
        });

        document.querySelectorAll('.filter-chip[data-type]').forEach(chip => {
            chip.addEventListener('click', () => {
                document.querySelectorAll('.filter-chip[data-type]').forEach(c => {
                    c.classList.remove('active');
                    c.setAttribute('aria-pressed', 'false');
                });
                chip.classList.add('active');
                chip.setAttribute('aria-pressed', 'true');
                currentType = chip.dataset.type || '';
                if (mode === 'nearby') {
                    loadNearby();
                } else {
                    loadList(1);
                }
            });
        });

        document.getElementById('openNowBtn')?.addEventListener('click', (event) => {
            currentOpenNow = !currentOpenNow;
            event.currentTarget.classList.toggle('active', currentOpenNow);
            event.currentTarget.setAttribute('aria-pressed', String(currentOpenNow));
            mode === 'nearby' ? loadNearby() : loadList(1);
        });

        document.getElementById('nearMeBtn')?.addEventListener('click', loadNearby);
        document.getElementById('cityFilter')?.addEventListener('change', (event) => { currentCity = event.target.value; loadList(1); });
        document.getElementById('serviceFilter')?.addEventListener('change', (event) => { currentService = event.target.value; loadList(1); });

        document.getElementById('clinicsListContent')?.addEventListener('click', (e) => {
            if (e.target.closest('#retryBtn')) {
                mode === 'nearby' ? loadNearby() : loadList(currentPage);
                return;
            }
            const pageBtn = e.target.closest('.pagination-btn:not(:disabled)');
            if (pageBtn) {
                loadList(parseInt(pageBtn.dataset.page, 10));
            }
        });

        window.addEventListener('languageChanged', () => {
            applyDirectoryLabels();
            loadDirectoryFilters();
            mode === 'nearby' ? loadNearby() : loadList(currentPage);
        });
    }

    return { init };

})();

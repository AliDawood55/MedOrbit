/**
 * MedOrbit v2 - Find Clinics
 * GET /api/clinics (paginated list) + GET /api/clinics/nearby (geolocation),
 * both with an optional ?type= filter. List + map side by side, reusing
 * MapApp (the same Leaflet/clustering module the chat page uses).
 */
const FindClinics = (() => {

    const PAGE_SIZE = 20;
    const NEARBY_RADIUS_KM = 10;

    let mode = 'list'; // 'list' | 'nearby'
    let currentType = '';
    let currentPage = 1;
    let searchDebounceTimer = null;
    let activeController = null;
    const LIST_CACHE_TTL = 60000; // 1 min — clinic list/filters rarely change that fast

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

    function clinicName(c) {
        return (isAr() ? c.name_ar : c.name_en) || c.name_ar || c.name_en || '';
    }

    function clinicAddress(c) {
        return (isAr() ? c.address_ar : c.address_en) || c.address_ar || c.address_en || '';
    }

    function toPlace(c) {
        return {
            id: c.id,
            name: clinicName(c),
            lat: parseFloat(c.latitude),
            lng: parseFloat(c.longitude),
            type: c.type || 'clinic',
            phone: c.phone,
            address: clinicAddress(c),
            distance: c.distance_km != null ? Number(c.distance_km) * 1000 : null,
            rating: c.average_rating
        };
    }

    // ================= DATA: LIST MODE =================

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
            type: currentType || undefined
        };

        try {
            const res = await API.clinics.list(query, { auth: false, signal: activeController.signal, cacheTTL: LIST_CACHE_TTL });
            const { clinics, pagination } = res.data;

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

    // ================= DATA: NEARBY MODE =================

    function loadNearby() {
        const content = document.getElementById('clinicsListContent');
        if (!content) return;

        if (typeof Location === 'undefined') {
            if (typeof Toast !== 'undefined') Toast.error(isAr() ? 'تعذر تحديد الموقع' : 'Location is unavailable');
            return;
        }

        mode = 'nearby';
        content.innerHTML = '<div class="empty-state"><div class="spinner spinner-lg" style="margin:0 auto 16px;"></div><p>' + escapeHtml(t('clinics.locating')) + '</p></div>';

        // "Near me" always means a fresh GPS fix — delegated entirely to the
        // shared Location module (map.js reacts to the same state change and
        // updates the user marker on its own, no separate call needed here).
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
            }, { auth: false, signal: activeController.signal, cacheTTL: LIST_CACHE_TTL });

            const clinics = res.data.clinics || [];

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

    // ================= RENDER =================

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
        const typeLabel = c.type ? escapeHtml(t('filter.' + c.type) !== 'filter.' + c.type ? t('filter.' + c.type) : c.type) : '';
        const distText = showDistance && c.distance_km != null ? Number(c.distance_km).toFixed(2) + (isAr() ? ' كم' : ' km') : '';
        const typeIcon = { clinic: 'fa-hospital', pharmacy: 'fa-pills', hospital: 'fa-hospital-user' }[c.type] || 'fa-hospital';

        return (
            '<div class="entity-card" style="margin-bottom:10px;" data-clinic-id="' + escapeHtml(c.id) + '">' +
                '<div class="entity-card-body">' +
                    '<div class="entity-avatar" style="background:var(--cat-' + (c.type || 'clinic') + ', var(--primary-gradient));"><i class="fas ' + typeIcon + '"></i></div>' +
                    '<div class="entity-card-info">' +
                        '<div class="entity-card-title">' + cName + '</div>' +
                        (address ? '<div class="entity-card-subtitle" style="color:var(--text-mute);font-weight:500;">' + address + '</div>' : '') +
                        '<div class="entity-card-meta">' +
                            (typeLabel ? '<span><i class="fas ' + typeIcon + '"></i>' + typeLabel + '</span>' : '') +
                            (distText ? '<span><i class="fas fa-route"></i>' + distText + '</span>' : '') +
                            (c.phone ? '<span><i class="fas fa-phone"></i>' + escapeHtml(c.phone) + '</span>' : '') +
                        '</div>' +
                    '</div>' +
                '</div>' +
                '<div class="entity-card-footer">' +
                    '<a class="btn btn-primary btn-sm" href="clinic.html?id=' + encodeURIComponent(c.id) + '">' +
                        '<i class="fas fa-circle-info"></i> ' + escapeHtml(t('clinics.viewDetails')) +
                    '</a>' +
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

    function init() {
        const params = new URLSearchParams(window.location.search);
        const initialSearch = params.get('search');
        if (initialSearch) {
            const input = document.getElementById('searchInput');
            if (input) input.value = initialSearch;
        }

        loadList(1);

        document.getElementById('searchInput')?.addEventListener('input', () => {
            clearTimeout(searchDebounceTimer);
            searchDebounceTimer = setTimeout(() => loadList(1), 400);
        });

        document.querySelectorAll('.filter-chip').forEach(chip => {
            chip.addEventListener('click', () => {
                document.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));
                chip.classList.add('active');
                currentType = chip.dataset.type || '';
                if (mode === 'nearby') {
                    loadNearby();
                } else {
                    loadList(1);
                }
            });
        });

        document.getElementById('nearMeBtn')?.addEventListener('click', loadNearby);

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
            mode === 'nearby' ? loadNearby() : loadList(currentPage);
        });
    }

    return { init };

})();

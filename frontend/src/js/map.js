const MapApp = (() => {

const DEFAULT_CENTER = [32.2211, 35.2544];
    const DEFAULT_ZOOM = 13;

    let map = null;
    let clusterGroup = null;

let userLocation = null;
    let userMarker = null;
    let clinicMarkers = [];
    let routeLayer = null;
    let activeHighlight = null;

const CATEGORY_ICONS = {
        clinic: 'fa-hospital',
        dental: 'fa-tooth',
        pharmacy: 'fa-pills',
        hospital: 'fa-hospital-user',
        doctor: 'fa-user-md',
        healthcare: 'fa-notes-medical'
    };

    const CATEGORY_LABELS = {
        clinic: { ar: 'عيادة', en: 'Clinic' },
        dental: { ar: 'عيادة أسنان', en: 'Dental clinic' },
        pharmacy: { ar: 'صيدلية', en: 'Pharmacy' },
        hospital: { ar: 'مستشفى', en: 'Hospital' },
        doctor: { ar: 'طبيب', en: 'Doctor' },
        healthcare: { ar: 'مرفق صحي', en: 'Healthcare facility' }
    };

    function isArLang() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

function init() {

        map = L.map('map', {
            center: DEFAULT_CENTER,
            zoom: DEFAULT_ZOOM
        });

        L.tileLayer(
            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            { maxZoom: 19 }
        ).addTo(map);

if (typeof L.markerClusterGroup === 'function') {
            clusterGroup = L.markerClusterGroup({
                showCoverageOnHover: false,
                spiderfyOnMaxZoom: true,
                maxClusterRadius: 50
            });
            map.addLayer(clusterGroup);
        }

if (typeof Location !== 'undefined') {
            Location.onChange(onLocationChange);
            setTimeout(() => Location.locate(false), 500);
        }

        map.on('click', onMapClick);
    }

function onLocationChange(state) {
        if (!state.coords) return;

        userLocation = state.coords;

        map.setView([userLocation.lat, userLocation.lng], 15);

        if (userMarker) {
            map.removeLayer(userMarker);
        }

        const isAr = isArLang();
        userMarker = L.marker([userLocation.lat, userLocation.lng], {
            zIndexOffset: 1000
        })
            .addTo(map)
            .bindPopup(isAr ? '📍 موقعك الحالي' : '📍 Your location')
            .openPopup();
    }

    let pickModeActive = false;

function enablePickMode() {
        pickModeActive = true;
        if (map) map.getContainer().style.cursor = 'crosshair';
    }

    function onMapClick(e) {
        if (!pickModeActive) return;
        pickModeActive = false;
        if (map) map.getContainer().style.cursor = '';

        if (typeof Location !== 'undefined') {
            Location.setManual({ lat: e.latlng.lat, lng: e.latlng.lng }, 'manual-map');
        }
    }

    function getUserLocation() {
        return userLocation;
    }

function buildMarkerIcon(type) {
        const cls = CATEGORY_ICONS[type] ? type : 'healthcare';
        return L.divIcon({
            className: 'custom-marker',
            iconSize: [38, 38],
            iconAnchor: [19, 38],
            popupAnchor: [0, -34],
            html: '<div class="marker-pin ' + cls + '"><i class="fas ' + (CATEGORY_ICONS[cls]) + '"></i></div>'
        });
    }

    function buildPopupContent(place) {
        const ar = isArLang();
        const type = CATEGORY_ICONS[place.type] ? place.type : 'healthcare';
        const label = CATEGORY_LABELS[type][ar ? 'ar' : 'en'];

        const rows = [];
        if (place.phone) {
            rows.push(
                '<div class="popup-meta-row"><i class="fas fa-phone"></i><a href="tel:' + escapeHtml(place.phone) + '">' + escapeHtml(place.phone) + '</a></div>'
            );
        }
        if (place.address) {
            rows.push(
                '<div class="popup-meta-row"><i class="fas fa-map-marker-alt"></i><span>' + escapeHtml(place.address) + '</span></div>'
            );
        }
        if (place.distance != null) {
            const distText = (Number(place.distance) / 1000).toFixed(2) + (ar ? ' كم' : ' km');
            rows.push(
                '<div class="popup-meta-row"><i class="fas fa-route"></i><span>' + distText + '</span></div>'
            );
        }
        if (place.rating != null) {
            rows.push(
                '<div class="popup-meta-row"><i class="fas fa-star"></i><span>' + Number(place.rating).toFixed(1) + '</span></div>'
            );
        }

        return (
            '<div class="popup-content">' +
                '<div class="popup-header">' +
                    '<div class="popup-title">' + escapeHtml(place.name || '') + '</div>' +
                    '<span class="popup-type ' + type + '">' + escapeHtml(label) + '</span>' +
                '</div>' +
                (rows.length ? '<div class="popup-meta">' + rows.join('') + '</div>' : '') +
                (place.phone
                    ? '<div class="popup-actions"><a class="btn btn-primary btn-sm" href="tel:' + escapeHtml(place.phone) + '"><i class="fas fa-phone"></i> ' + (ar ? 'اتصال' : 'Call') + '</a></div>'
                    : '') +
            '</div>'
        );
    }

function clearClinicMarkers() {

        if (clusterGroup) {
            clusterGroup.clearLayers();
        } else {
            clinicMarkers.forEach((marker) => map.removeLayer(marker));
        }

        clinicMarkers = [];
        activeHighlight = null;
    }

    function clearRoute() {
        if (routeLayer) {
            map.removeLayer(routeLayer);
            routeLayer = null;
        }
    }

    function clearResults() {
        clearClinicMarkers();
        clearRoute();
    }

    function renderPlaces(places) {

        clearClinicMarkers();

        if (!Array.isArray(places)) return;

        const validPlaces = places.filter(p =>
            p != null &&
            p.lat != null &&
            p.lng != null &&
            !isNaN(Number(p.lat)) &&
            !isNaN(Number(p.lng))
        );

        if (validPlaces.length === 0) return;

        validPlaces.forEach(place => {

            const lat = Number(place.lat);
            const lng = Number(place.lng);

            const marker = L.marker([lat, lng], { icon: buildMarkerIcon(place.type) })
                .bindPopup(buildPopupContent(place));

            marker.on('click', () => {
                highlightPlace(place);

                if (userLocation) {
                    drawRoute(userLocation, place);
                }
            });

            if (clusterGroup) {
                clusterGroup.addLayer(marker);
            } else {
                marker.addTo(map);
            }

            clinicMarkers.push(marker);
        });

fitToMarkers();
    }

    function fitToMarkers() {

        if (clinicMarkers.length === 0) return;

        const group = L.featureGroup(clinicMarkers);

if (userMarker) {
            group.addLayer(userMarker);
        }

        map.fitBounds(group.getBounds(), {
            padding: [80, 80],
            maxZoom: 16
        });
    }

function highlightPlace(place) {

        if (!place || place.lat == null || place.lng == null) return;

if (activeHighlight) {
            map.removeLayer(activeHighlight);
            activeHighlight = null;
        }

        const lat = Number(place.lat);
        const lng = Number(place.lng);

activeHighlight = L.marker([lat, lng], {
            zIndexOffset: 500,
            icon: L.divIcon({
                className: 'highlight-marker',
                iconSize: [30, 30],
                iconAnchor: [15, 15],
                html: '<div style="width:24px;height:24px;background:#2563EB;border:3px solid #fff;border-radius:50%;box-shadow:0 0 12px rgba(37,99,235,0.6);"></div>'
            })
        })
            .addTo(map)
            .bindPopup(
                '<div><strong>' + escapeHtml(place.name || '') + '</strong></div>'
            );

        map.flyTo([lat, lng], 17, { duration: 1.0 });
    }

    async function drawRoute(user, destination) {

        if (!user || !destination) return;

        const userLat = Number(user.lat);
        const userLng = Number(user.lng);
        const destLat = Number(destination.lat);
        const destLng = Number(destination.lng);

        if (isNaN(userLat) || isNaN(userLng) || isNaN(destLat) || isNaN(destLng)) {
            console.warn('MapApp: Invalid coordinates for route');
            return;
        }

        try {

            const url = 'https://router.project-osrm.org/route/v1/driving/' +
                userLng + ',' + userLat + ';' +
                destLng + ',' + destLat +
                '?overview=full&geometries=geojson';

            const response = await fetch(url);

            if (!response.ok) {
                console.warn('MapApp: OSRM request failed', response.status);
                return;
            }

            const data = await response.json();

            if (!data.routes || data.routes.length === 0) {
                console.warn('MapApp: No route found');
                return;
            }

const coords = data.routes[0].geometry.coordinates.map(c => [c[1], c[0]]);

clearRoute();

routeLayer = L.polyline(coords, {
                color: '#2563EB',
                weight: 5,
                opacity: 0.85,
                dashArray: null,
                lineJoin: 'round'
            }).addTo(map);

const distanceKm = (data.routes[0].distance / 1000).toFixed(2);
            const durationMin = (data.routes[0].duration / 60).toFixed(0);

const isAr = isArLang();
            const popupText = isAr
                ? '📏 ' + distanceKm + ' كم — ⏱ ' + durationMin + ' دقيقة'
                : '📏 ' + distanceKm + ' km — ⏱ ' + durationMin + ' min';

            L.popup()
                .setLatLng([destLat, destLng])
                .setContent(popupText)
                .openOn(map);

        } catch (err) {
            console.error('MapApp: Routing error:', err.message);
        }
    }

    function recenter() {

        if (userLocation) {
            map.flyTo([userLocation.lat, userLocation.lng], 15, { duration: 0.8 });
        } else if (typeof Location !== 'undefined') {
            Location.locate(true);
        }
    }

function setCategoryFilter(category) {

console.log('MapApp: Category filter set to', category);
    }

function invalidateSize() {
        if (map) {
            setTimeout(() => map.invalidateSize(), 50);
        }
    }

function escapeHtml(text) {
        if (!text) return '';
        return String(text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

return {
        init,
        recenter,
        getUserLocation,
        enablePickMode,
        renderPlaces,
        highlightPlace,
        drawRoute,
        fitToMarkers,
        clearRoute,
        clearResults,
        setCategoryFilter,
        invalidateSize
    };

})();

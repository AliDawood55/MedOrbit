const MapApp = (() => {

    // ===== DEFAULT =====
    const DEFAULT_CENTER = [32.2211, 35.2544];
    const DEFAULT_ZOOM = 13;

    let map = null;

    // ===== STATE =====
    let userLocation = null;
    let userMarker = null;
    let clinicMarkers = [];
    let routeLayer = null;
    let activeHighlight = null;

    // ================= INIT =================
    function init() {

        map = L.map('map', {
            center: DEFAULT_CENTER,
            zoom: DEFAULT_ZOOM
        });

        L.tileLayer(
            'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            { maxZoom: 19 }
        ).addTo(map);

        // Try to get user location after a short delay
        setTimeout(() => locateUser(false), 500);
    }

    // ================= USER LOCATION =================
    function locateUser(force = false) {

        if (!navigator.geolocation) {
            console.warn('MapApp: Geolocation not supported');
            return;
        }

        navigator.geolocation.getCurrentPosition(

            (position) => {

                userLocation = {
                    lat: position.coords.latitude,
                    lng: position.coords.longitude
                };

                map.setView([userLocation.lat, userLocation.lng], 15);

                // Remove old marker
                if (userMarker) {
                    map.removeLayer(userMarker);
                }

                userMarker = L.marker([userLocation.lat, userLocation.lng], {
                    zIndexOffset: 1000
                })
                    .addTo(map)
                    .bindPopup('📍 موقعك الحالي')
                    .openPopup();
            },

            (err) => {
                console.warn('MapApp: Location error', err.message);
            },

            { enableHighAccuracy: true, timeout: 10000 }
        );
    }

    function getUserLocation() {
        return userLocation;
    }

    // ================= MARKERS =================
    function clearClinicMarkers() {

        clinicMarkers.forEach(marker => {
            map.removeLayer(marker);
        });

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

            const marker = L.marker([lat, lng])
                .addTo(map)
                .bindPopup(
                    '<div>' +
                        '<strong>' + escapeHtml(place.name || '') + '</strong><br/>' +
                        (place.phone ? '📞 ' + escapeHtml(place.phone) + '<br/>' : '') +
                        (place.address ? '📍 ' + escapeHtml(place.address) + '<br/>' : '') +
                        (place.distance ? '📏 ' + (Number(place.distance) / 1000).toFixed(2) + ' كم' : '') +
                    '</div>'
                );

            marker.on('click', () => {
                highlightPlace(place);

                if (userLocation) {
                    drawRoute(userLocation, place);
                }
            });

            clinicMarkers.push(marker);
        });

        // Fit bounds to show all markers
        fitToMarkers();
    }

    function fitToMarkers() {

        if (clinicMarkers.length === 0) return;

        const group = L.featureGroup(clinicMarkers);

        // Include user marker in bounds if available
        if (userMarker) {
            group.addLayer(userMarker);
        }

        map.fitBounds(group.getBounds(), {
            padding: [80, 80],
            maxZoom: 16
        });
    }

    // ================= MAP ACTIONS =================
    function highlightPlace(place) {

        if (!place || place.lat == null || place.lng == null) return;

        // Remove previous highlight marker
        if (activeHighlight) {
            map.removeLayer(activeHighlight);
            activeHighlight = null;
        }

        const lat = Number(place.lat);
        const lng = Number(place.lng);

        // Create a highlighted marker (distinct from regular markers)
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

            // Convert GeoJSON coordinates [lng, lat] to Leaflet [lat, lng]
            const coords = data.routes[0].geometry.coordinates.map(c => [c[1], c[0]]);

            // Remove old route
            clearRoute();

            // Draw new route
            routeLayer = L.polyline(coords, {
                color: '#2563EB',
                weight: 5,
                opacity: 0.85,
                dashArray: null,
                lineJoin: 'round'
            }).addTo(map);

            // Route info
            const distanceKm = (data.routes[0].distance / 1000).toFixed(2);
            const durationMin = (data.routes[0].duration / 60).toFixed(0);

            // Show route info popup at destination
            const isAr = (document.documentElement.lang || 'ar') === 'ar';
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
        } else {
            locateUser(true);
        }
    }

    // Category filter stub — for future implementation
    function setCategoryFilter(category) {
        // Placeholder: will be implemented when filter bar
        // is connected to direct DB queries
        console.log('MapApp: Category filter set to', category);
    }

    // ================= HELPERS =================
    function escapeHtml(text) {
        if (!text) return '';
        return String(text)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    // ================= PUBLIC =================
    return {
        init,
        locateUser,
        recenter,
        getUserLocation,
        renderPlaces,
        highlightPlace,
        drawRoute,
        fitToMarkers,
        clearRoute,
        clearResults,
        setCategoryFilter
    };

})();
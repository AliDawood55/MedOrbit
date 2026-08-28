const MiniMap = (() => {

    function render(containerId, { lat, lng, title, zoom = 15 } = {}) {
        const el = document.getElementById(containerId);
        const latNum = Number(lat);
        const lngNum = Number(lng);

        if (!el || lat == null || lng == null || isNaN(latNum) || isNaN(lngNum)) {
            return null;
        }

        const map = L.map(containerId, {
            center: [latNum, lngNum],
            zoom,
            scrollWheelZoom: false
        });

        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            maxZoom: 19
        }).addTo(map);

        const marker = L.marker([latNum, lngNum]).addTo(map);
        if (title) marker.bindPopup(title);

        return map;
    }

    return { render };

})();

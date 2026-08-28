const Location = (() => {

const NABLUS_DISTRICTS = [
        { id: 'center', ar: 'وسط المدينة', en: 'City Center', lat: 32.2211, lng: 35.2544 },
        { id: 'rafidia', ar: 'رفيديا', en: 'Rafidia', lat: 32.2258, lng: 35.2280 },
        { id: 'askar', ar: 'مخيم عسكر', en: 'Askar Camp', lat: 32.2350, lng: 35.2930 },
        { id: 'balata', ar: 'مخيم بلاطة', en: 'Balata Camp', lat: 32.2080, lng: 35.2862 },
        { id: 'huwara', ar: 'حوارة', en: 'Huwara', lat: 32.1520, lng: 35.2590 },
        { id: 'beitfurik', ar: 'بيت فوريك', en: 'Beit Furik', lat: 32.1760, lng: 35.3350 },
        { id: 'sabastia', ar: 'سبسطية', en: 'Sabastia', lat: 32.2770, lng: 35.1940 }
    ];

    const ERROR_MESSAGES = {
        PERMISSION_DENIED: {
            ar: 'تم رفض إذن الوصول لموقعك. يمكنك تحديد موقعك يدوياً بدلاً من ذلك.',
            en: 'Location permission was denied. You can set your location manually instead.'
        },
        POSITION_UNAVAILABLE: {
            ar: 'تعذر تحديد موقعك حالياً. حاول مرة أخرى أو اختر موقعك يدوياً.',
            en: 'Your location is unavailable right now. Try again or set it manually.'
        },
        TIMEOUT: {
            ar: 'استغرق تحديد موقعك وقتاً طويلاً. حاول مرة أخرى أو اختر يدوياً.',
            en: 'Locating you took too long. Try again or set your location manually.'
        },
        NOT_SUPPORTED: {
            ar: 'متصفحك لا يدعم تحديد الموقع. يمكنك تحديد موقعك يدوياً.',
            en: 'Your browser does not support geolocation. You can set your location manually.'
        }
    };

    let state = {
        status: 'idle',
        coords: null,
        accuracy: null,
        source: null,
        errorCode: null,
        label: null
    };

    const listeners = new Set();

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

    function notify() {
        const snapshot = { ...state };
        listeners.forEach((cb) => {
            try { cb(snapshot); } catch (e) { console.error('Location listener error', e); }
        });
    }

    function onChange(cb) {
        listeners.add(cb);
        return () => listeners.delete(cb);
    }

    function getState() {
        return { ...state };
    }

    function errorCodeName(code) {
        return {
            1: 'PERMISSION_DENIED',
            2: 'POSITION_UNAVAILABLE',
            3: 'TIMEOUT'
        }[code] || 'POSITION_UNAVAILABLE';
    }

    function errorMessage(errorCode) {
        const msg = ERROR_MESSAGES[errorCode] || ERROR_MESSAGES.POSITION_UNAVAILABLE;
        return isAr() ? msg.ar : msg.en;
    }

    function locate(force = false) {
        if (state.status === 'locating' && !force) return;

        if (!navigator.geolocation) {
            state = { status: 'error', coords: state.coords, accuracy: null, source: null, errorCode: 'NOT_SUPPORTED', label: null };
            notify();
            return;
        }

        state = { ...state, status: 'locating', errorCode: null };
        notify();

        navigator.geolocation.getCurrentPosition(
            (position) => {
                state = {
                    status: 'resolved',
                    coords: { lat: position.coords.latitude, lng: position.coords.longitude },
                    accuracy: position.coords.accuracy,
                    source: 'gps',
                    errorCode: null,
                    label: null
                };
                notify();
            },
            (err) => {
                state = { ...state, status: 'error', errorCode: errorCodeName(err.code) };
                notify();
            },
            { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
        );
    }

function setManual(coords, source, label) {
        state = {
            status: 'manual',
            coords: { lat: Number(coords.lat), lng: Number(coords.lng) },
            accuracy: null,
            source: source || 'manual-map',
            errorCode: null,
            label: label || null
        };
        notify();
    }

    function setDistrict(districtId) {
        const d = NABLUS_DISTRICTS.find((x) => x.id === districtId);
        if (!d) return;
        setManual({ lat: d.lat, lng: d.lng }, 'manual-district', d);
    }

    function getDistricts() {
        return NABLUS_DISTRICTS.slice();
    }

function waitForFix(timeoutMs = 2500) {
        return new Promise((resolve) => {
            if (state.coords) {
                resolve(state.coords);
                return;
            }
            if (state.status !== 'locating') {
                resolve(null);
                return;
            }

            let settled = false;
            const finish = (value) => {
                if (settled) return;
                settled = true;
                clearTimeout(timer);
                unsubscribe();
                resolve(value);
            };

            const unsubscribe = onChange((s) => {
                if (s.status === 'resolved' || s.status === 'manual') finish(s.coords);
                else if (s.status === 'error') finish(null);
            });

            const timer = setTimeout(() => finish(null), timeoutMs);
        });
    }

    return {
        locate,
        setManual,
        setDistrict,
        getDistricts,
        getState,
        onChange,
        waitForFix,
        errorMessage
    };

})();

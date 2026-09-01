/**
 * MedOrbit v2 - Clinic Profile
 * GET /api/clinics/:id — info, hours, services, doctors, mini-map, route button.
 */
const ClinicProfile = (() => {

    const DAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    const FACILITY_TYPES = Object.freeze({
        clinic: { labelKey: 'filter.clinic', icon: 'fa-hospital' },
        dental: { labelKey: 'filter.dental', icon: 'fa-tooth' },
        hospital: { labelKey: 'filter.hospital', icon: 'fa-hospital-user' },
        pharmacy: { labelKey: 'filter.pharmacy', icon: 'fa-pills' }
    });
    const GENERIC_FACILITY = Object.freeze({ labelKey: 'filter.healthcare', icon: 'fa-notes-medical' });

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

    function getIdFromUrl() {
        return new URLSearchParams(window.location.search).get('id');
    }

    function name(o, arKey, enKey) {
        const ar = isAr();
        return optionalText(ar ? o[arKey] : o[enKey]) || optionalText(o[arKey]) || optionalText(o[enKey]);
    }

    function doctorName(d) {
        const full = (name(d, 'first_name_ar', 'first_name_en') + ' ' + name(d, 'last_name_ar', 'last_name_en')).trim();
        return full || '';
    }

    function formatTime(t) {
        return t ? String(t).slice(0, 5) : '';
    }

    function renderSocialLinks(links) {
        if (!links || typeof links !== 'object') return '';
        const config = { website:['fa-globe','Website'], instagram:['fa-instagram','Instagram'], facebook:['fa-facebook','Facebook'], tiktok:['fa-tiktok','TikTok'], linkedin:['fa-linkedin','LinkedIn'], whatsapp:['fa-whatsapp','WhatsApp'], youtube:['fa-youtube','YouTube'], x:['fa-x-twitter','X'] };
        return Object.entries(config).map(([key, [icon, label]]) => {
            const href = optionalText(links[key]);
            return /^https:\/\//i.test(href) ? '<a class="btn btn-ghost btn-sm" href="' + escapeHtml(href) + '" target="_blank" rel="noopener noreferrer"><i class="fab ' + icon + '"></i> ' + escapeHtml(label) + '</a>' : '';
        }).join('');
    }

    // ================= LOAD =================

    async function load() {
        const id = getIdFromUrl();
        const content = document.getElementById('clinicContent');
        if (!content) return;

        if (!id) {
            content.innerHTML = renderNotFound();
            return;
        }

        content.innerHTML = renderSkeleton();

        try {
            const res = await API.clinics.get(id);
            const { clinic, doctors } = res.data;

            content.innerHTML = renderProfile(clinic, doctors || []);
            renderMiniMap(clinic);

        } catch (err) {
            console.error('ClinicProfile: failed to load', err);
            if (err?.status === 404) {
                content.innerHTML = renderNotFound();
            } else {
                content.innerHTML = renderError();
                document.getElementById('retryBtn')?.addEventListener('click', load);
            }
        }
    }

    // ================= RENDER: STATES =================

    function renderSkeleton() {
        return (
            '<div class="profile-header">' +
                '<div class="skeleton" style="width:96px;height:96px;border-radius:18px;flex-shrink:0;"></div>' +
                '<div style="flex:1;">' +
                    '<div class="skeleton" style="height:22px;width:40%;margin-bottom:10px;"></div>' +
                    '<div class="skeleton" style="height:14px;width:25%;"></div>' +
                '</div>' +
            '</div>'
        );
    }

    function renderNotFound() {
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas fa-hospital"></i></div>' +
            '<h3>' + escapeHtml(t('clinic.notFound')) + '</h3>' +
        '</div>';
    }

    function renderError() {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('clinics.error')) + '</p>' +
            '<button type="button" class="btn btn-secondary btn-sm" id="retryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
        '</div>';
    }

    // ================= RENDER: PROFILE =================

    function renderProfile(clinic, doctors) {
        const ar = isAr();
        const clinicName = escapeHtml(name(clinic, 'name_ar', 'name_en'));
        const address = escapeHtml(name(clinic, 'address_ar', 'address_en'));
        const type = typePresentation(clinic.type);
        const typeIcon = type.icon;
        const typeLabel = escapeHtml(t(type.labelKey));
        const logoUrl = escapeHtml(optionalText(clinic.logo_url));
        const phone = escapeHtml(optionalText(clinic.phone));
        const email = escapeHtml(optionalText(clinic.email));
        const website = escapeHtml(optionalText(clinic.website));
        const services = Array.isArray(clinic.services) ? clinic.services.map(optionalText).filter(Boolean) : [];
        const insurance = Array.isArray(clinic.insurance_accepted) ? clinic.insurance_accepted.map(optionalText).filter(Boolean) : [];
        const verifiedBadge = clinic.verification_status === 'verified'
            ? '<span class="badge badge-success"><i class="fas fa-circle-check"></i> ' + escapeHtml(t('clinic.verified')) + '</span>'
            : '';

        const hasCoords = clinic.latitude != null && clinic.longitude != null;
        const directionsUrl = hasCoords
            ? 'https://www.google.com/maps/dir/?api=1&destination=' + encodeURIComponent(clinic.latitude) + ',' + encodeURIComponent(clinic.longitude)
            : null;

        return (
            '<div class="profile-header">' +
                '<div class="profile-avatar">' +
                    (logoUrl
                        ? '<img src="' + logoUrl + '" alt="" data-fallback-icon="' + escapeHtml(typeIcon) + '" onerror="ClinicProfile.__logoFallback(this)">'
                        : '<i class="fas ' + typeIcon + '"></i>') +
                '</div>' +
                '<div class="profile-info">' +
                    '<h1>' + clinicName + '</h1>' +
                    (typeLabel ? '<div class="profile-subtitle">' + typeLabel + '</div>' : '') +
                    '<div class="profile-meta">' +
                        (address ? '<span><i class="fas fa-location-dot"></i>' + address + '</span>' : '') +
                        (phone ? '<span><i class="fas fa-phone"></i>' + phone + '</span>' : '') +
                        (email ? '<span><i class="fas fa-envelope"></i>' + email + '</span>' : '') +
                        (website ? '<span><i class="fas fa-globe"></i><a href="' + website + '" target="_blank" rel="noopener">' + website + '</a></span>' : '') +
                    '</div>' +
                    (verifiedBadge ? '<div class="profile-badges">' + verifiedBadge + '</div>' : '') +
                    (renderSocialLinks(clinic.social_links) ? '<div class="profile-actions">' + renderSocialLinks(clinic.social_links) + '</div>' : '') +
                '</div>' +
                '<div class="profile-actions">' +
                    (directionsUrl ? '<a class="btn btn-primary btn-sm" href="' + directionsUrl + '" target="_blank" rel="noopener"><i class="fas fa-route"></i> ' + escapeHtml(t('clinic.getDirections')) + '</a>' : '') +
                    (phone ? '<a class="btn btn-secondary btn-sm" href="tel:' + phone + '"><i class="fas fa-phone"></i> ' + (ar ? 'اتصال' : 'Call') + '</a>' : '') +
                '</div>' +
            '</div>' +

            '<div class="profile-layout">' +
                '<div class="profile-main">' +
                    '<div class="profile-section">' +
                        '<h2><i class="fas fa-clock"></i> ' + escapeHtml(t('clinic.hours')) + '</h2>' +
                        renderHours(clinic.operating_hours) +
                    '</div>' +

                    (services.length ? (
                        '<div class="profile-section">' +
                            '<h2><i class="fas fa-notes-medical"></i> ' + escapeHtml(t('clinic.services')) + '</h2>' +
                            '<div class="chip-list">' + services.map(s => '<span class="chip">' + escapeHtml(s) + '</span>').join('') + '</div>' +
                        '</div>'
                    ) : '') +

                    (insurance.length ? (
                        '<div class="profile-section">' +
                            '<h2><i class="fas fa-shield-heart"></i> ' + escapeHtml(t('clinic.insurance')) + '</h2>' +
                            '<div class="chip-list">' + insurance.map(s => '<span class="chip">' + escapeHtml(s) + '</span>').join('') + '</div>' +
                        '</div>'
                    ) : '') +
                '</div>' +

                '<aside class="profile-sidebar">' +
                    '<div class="profile-section">' +
                        '<h2><i class="fas fa-user-md"></i> ' + escapeHtml(t('clinic.doctors')) + '</h2>' +
                        (doctors.length
                            ? doctors.map(renderDoctorSubItem).join('')
                            : '<p>' + escapeHtml(t('clinic.noDoctors')) + '</p>') +
                    '</div>' +
                    (hasCoords ? '<div class="profile-section"><div id="clinicMiniMap" class="mini-map"></div></div>' : '') +
                '</aside>' +
            '</div>'
        );
    }

    function renderHours(hours) {
        if (!hours || typeof hours !== 'object') {
            return '<p>' + escapeHtml(isAr() ? 'ساعات العمل غير متوفرة' : 'Hours not available') + '</p>';
        }

        const todayKey = DAY_KEYS[new Date().getDay()];

        return '<div class="schedule-grid">' +
            DAY_KEYS.map(key => {
                const day = hours[key];
                const isToday = key === todayKey;
                const isOff = !day || day.is_off;

                return (
                    '<div class="schedule-day' + (isToday ? ' today' : '') + '">' +
                        '<div class="schedule-day-name">' + escapeHtml(t('day.' + key)) + '</div>' +
                        (isOff
                            ? '<div class="schedule-day-off">' + escapeHtml(t('doctor.closed')) + '</div>'
                            : '<div class="schedule-day-slots"><span class="slot">' + formatTime(day.open) + '–' + formatTime(day.close) + '</span></div>') +
                    '</div>'
                );
            }).join('') +
        '</div>';
    }

    function renderDoctorSubItem(d) {
        const dName = escapeHtml(doctorName(d));
        const specialty = escapeHtml(name(d, 'specialty_ar', 'specialty_en'));
        const initials = (doctorName(d) || '?').trim().charAt(0).toUpperCase();

        return (
            '<a class="sub-item" href="doctor.html?id=' + encodeURIComponent(d.id) + '">' +
                '<div class="entity-avatar">' +
                    (d.profile_image_url
                        ? '<img src="' + escapeHtml(API.assetUrl(d.profile_image_url)) + '" alt="" data-fallback-initials="' + escapeHtml(initials) + '" onerror="ClinicProfile.__avatarFallback(this)">'
                        : escapeHtml(initials)) +
                '</div>' +
                '<div class="sub-item-body">' +
                    '<div class="sub-item-title">' + dName + '</div>' +
                    (specialty ? '<div class="sub-item-subtitle">' + specialty + '</div>' : '') +
                '</div>' +
            '</a>'
        );
    }

    function renderMiniMap(clinic) {
        if (clinic.latitude == null || clinic.longitude == null || typeof MiniMap === 'undefined') return;
        MiniMap.render('clinicMiniMap', {
            lat: clinic.latitude,
            lng: clinic.longitude,
            title: name(clinic, 'name_ar', 'name_en')
        });
    }

    // ================= IMAGE FALLBACK =================

    // Swaps a broken clinic logo <img> for the same type-icon <i> already used
    // when logo_url is absent. Invoked from a static
    // onerror="ClinicProfile.__logoFallback(this)" attribute (no user-derived
    // string is ever embedded in executable JS); the icon class travels only
    // as an HTML-escaped data attribute.
    function logoFallback(img) {
        const icon = document.createElement('i');
        icon.className = 'fas ' + (img.dataset.fallbackIcon || 'fa-notes-medical');
        img.replaceWith(icon);
    }

    // Swaps a broken doctor sub-item <img> for the same initials fallback
    // already used when profile_image_url is absent. Same static-onerror
    // pattern as logoFallback above.
    function avatarFallback(img) {
        img.replaceWith(document.createTextNode(img.dataset.fallbackInitials || '?'));
    }

    // ================= INIT =================

    function init() {
        load();
    }

    return { init, __logoFallback: logoFallback, __avatarFallback: avatarFallback };

})();

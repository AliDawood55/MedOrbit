/**
 * MedOrbit v2 - Doctor Profile
 * GET /api/doctors/:id (profile + clinics + reviews) and
 * GET /api/doctors/:id/availability (weekly schedule).
 */
const DoctorProfile = (() => {

    const DAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

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

    function getIdFromUrl() {
        return new URLSearchParams(window.location.search).get('id');
    }

    function name(d, arKey, enKey) {
        const ar = isAr();
        return ((ar ? d[arKey] : d[enKey]) || d[arKey] || d[enKey] || '').trim();
    }

    function doctorName(d) {
        const full = (name(d, 'first_name_ar', 'first_name_en') + ' ' + name(d, 'last_name_ar', 'last_name_en')).trim();
        return full || d.email || '';
    }

    function formatTime(t) {
        return t ? String(t).slice(0, 5) : '';
    }

    // ================= LOAD =================

    async function load() {
        const id = getIdFromUrl();
        const content = document.getElementById('doctorContent');
        if (!content) return;

        if (!id) {
            content.innerHTML = renderNotFound();
            return;
        }

        content.innerHTML = renderSkeleton();

        try {
            const [profileRes, availabilityRes] = await Promise.all([
                API.doctors.get(id, { auth: false }),
                API.doctors.availability(id, null, { auth: false }).catch(() => null)
            ]);

            const { doctor, clinics, reviews } = profileRes.data;
            const slots = availabilityRes?.data?.slots || profileRes.data.availability || [];

            content.innerHTML = renderProfile(doctor, clinics || [], slots, reviews || []);
            renderMiniMap(clinics || []);

        } catch (err) {
            console.error('DoctorProfile: failed to load', err);
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
            '<div class="empty-state-icon"><i class="fas fa-user-doctor"></i></div>' +
            '<h3>' + escapeHtml(t('doctor.notFound')) + '</h3>' +
        '</div>';
    }

    function renderError() {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('doctors.error')) + '</p>' +
            '<button type="button" class="btn btn-secondary btn-sm" id="retryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
        '</div>';
    }

    // ================= RENDER: PROFILE =================

    function renderProfile(doctor, clinics, slots, reviews) {
        const ar = isAr();
        const fullName = escapeHtml(doctorName(doctor));
        const specialty = escapeHtml(name(doctor, 'specialty_ar', 'specialty_en'));
        const initials = (doctorName(doctor) || '?').trim().charAt(0).toUpperCase();
        const rating = doctor.average_rating != null ? Number(doctor.average_rating).toFixed(1) : null;

        const acceptingBadge = doctor.is_accepting_patients === false
            ? '<span class="badge badge-danger">' + escapeHtml(t('doctors.notAccepting')) + '</span>'
            : (doctor.is_accepting_patients ? '<span class="badge badge-success">' + escapeHtml(t('doctors.accepting')) + '</span>' : '');

        const bio = name(doctor, 'professional_bio_ar', 'professional_bio_en');

        return (
            '<div class="profile-header">' +
                '<div class="profile-avatar">' +
                    (doctor.profile_image_url ? '<img src="' + escapeHtml(doctor.profile_image_url) + '" alt="">' : escapeHtml(initials)) +
                '</div>' +
                '<div class="profile-info">' +
                    '<h1>' + fullName + '</h1>' +
                    (specialty ? '<div class="profile-subtitle">' + specialty + '</div>' : '') +
                    '<div class="profile-meta">' +
                        (rating ? '<span class="rating"><span class="rating-stars">★</span><span class="rating-value">' + rating + (doctor.total_ratings ? ' (' + doctor.total_ratings + ')' : '') + '</span></span>' : '') +
                        (doctor.years_of_experience != null ? '<span><i class="fas fa-briefcase"></i>' + escapeHtml(String(doctor.years_of_experience)) + ' ' + escapeHtml(t('doctors.yearsExp')) + '</span>' : '') +
                        (doctor.consultation_fee != null ? '<span><i class="fas fa-shekel-sign"></i>' + escapeHtml(t('doctor.consultationFee')) + ': ' + escapeHtml(String(doctor.consultation_fee)) + '</span>' : '') +
                        (doctor.city ? '<span><i class="fas fa-location-dot"></i>' + escapeHtml(doctor.city) + '</span>' : '') +
                    '</div>' +
                    (acceptingBadge ? '<div class="profile-badges">' + acceptingBadge + '</div>' : '') +
                '</div>' +
                '<div class="profile-actions">' +
                    '<a class="btn btn-primary btn-sm" href="index.html"><i class="fas fa-comments"></i> ' + escapeHtml(t('home.startChat')) + '</a>' +
                '</div>' +
            '</div>' +

            '<div class="profile-layout">' +
                '<div class="profile-main">' +
                    (bio ? (
                        '<div class="profile-section">' +
                            '<h2><i class="fas fa-user"></i> ' + escapeHtml(t('doctor.about')) + '</h2>' +
                            '<p>' + escapeHtml(bio) + '</p>' +
                        '</div>'
                    ) : '') +

                    '<div class="profile-section">' +
                        '<h2><i class="fas fa-calendar-week"></i> ' + escapeHtml(t('doctor.availability')) + '</h2>' +
                        renderSchedule(slots) +
                    '</div>' +

                    '<div class="profile-section">' +
                        '<h2><i class="fas fa-star"></i> ' + escapeHtml(t('doctor.reviews')) + '</h2>' +
                        (reviews.length
                            ? reviews.map(renderReview).join('')
                            : '<p>' + escapeHtml(t('doctor.noReviews')) + '</p>') +
                    '</div>' +
                '</div>' +

                '<aside class="profile-sidebar">' +
                    '<div class="profile-section">' +
                        '<h2><i class="fas fa-hospital"></i> ' + escapeHtml(t('doctor.clinics')) + '</h2>' +
                        (clinics.length
                            ? clinics.map(renderClinicSubItem).join('')
                            : '<p>' + escapeHtml(t('clinic.noDoctors')) + '</p>') +
                    '</div>' +
                    (hasMappableClinic(clinics) ? '<div class="profile-section"><div id="doctorMiniMap" class="mini-map"></div></div>' : '') +
                '</aside>' +
            '</div>'
        );
    }

    function renderSchedule(slots) {
        const byDay = [[], [], [], [], [], [], []];
        (slots || []).forEach(s => {
            const day = Number(s.day_of_week);
            if (day >= 0 && day <= 6) byDay[day].push(s);
        });

        const todayIndex = new Date().getDay();

        return '<div class="schedule-grid">' +
            byDay.map((daySlots, i) => {
                daySlots.sort((a, b) => (a.start_time || '').localeCompare(b.start_time || ''));
                return (
                    '<div class="schedule-day' + (i === todayIndex ? ' today' : '') + '">' +
                        '<div class="schedule-day-name">' + escapeHtml(t('day.' + DAY_KEYS[i])) + '</div>' +
                        (daySlots.length
                            ? '<div class="schedule-day-slots">' + daySlots.map(s =>
                                '<span class="slot">' + formatTime(s.start_time) + '–' + formatTime(s.end_time) + '</span>'
                              ).join('') + '</div>'
                            : '<div class="schedule-day-off">' + escapeHtml(t('doctor.closed')) + '</div>') +
                    '</div>'
                );
            }).join('') +
        '</div>' +
        (slots.length === 0 ? '<p style="margin-top:12px;">' + escapeHtml(t('doctor.noAvailability')) + '</p>' : '');
    }

    function renderReview(r) {
        const text = name(r, 'review_text_ar', 'review_text_en');
        const author = (name(r, 'patient_first_name_ar', 'patient_first_name_en') || '').trim();
        const date = r.created_at ? new Date(r.created_at).toLocaleDateString(isAr() ? 'ar' : 'en-US') : '';

        return (
            '<div class="review-item">' +
                '<div class="review-header">' +
                    '<span class="review-author">' + escapeHtml(author || (isAr() ? 'مريض' : 'Patient')) + '</span>' +
                    '<span class="review-date">' + escapeHtml(date) + '</span>' +
                '</div>' +
                (r.rating != null ? '<div class="rating"><span class="rating-stars">★</span><span class="rating-value">' + Number(r.rating).toFixed(1) + '</span></div>' : '') +
                (text ? '<div class="review-text">' + escapeHtml(text) + '</div>' : '') +
            '</div>'
        );
    }

    function renderClinicSubItem(c) {
        const clinicName = escapeHtml(name(c, 'name_ar', 'name_en'));
        const address = escapeHtml(name(c, 'address_ar', 'address_en'));
        return (
            '<a class="sub-item" href="clinic.html?id=' + encodeURIComponent(c.id) + '" style="text-decoration:none;color:inherit;">' +
                '<div class="entity-avatar" style="width:38px;height:38px;font-size:13px;"><i class="fas fa-hospital"></i></div>' +
                '<div class="sub-item-body">' +
                    '<div class="sub-item-title">' + clinicName + (c.is_primary ? ' <span class="badge badge-primary">' + (isAr() ? 'رئيسية' : 'Primary') + '</span>' : '') + '</div>' +
                    (address ? '<div class="sub-item-subtitle">' + address + '</div>' : '') +
                '</div>' +
            '</a>'
        );
    }

    function hasMappableClinic(clinics) {
        return !!primaryClinicWithCoords(clinics);
    }

    function primaryClinicWithCoords(clinics) {
        const withCoords = (clinics || []).filter(c => c.latitude != null && c.longitude != null);
        if (withCoords.length === 0) return null;
        return withCoords.find(c => c.is_primary) || withCoords[0];
    }

    function renderMiniMap(clinics) {
        const clinic = primaryClinicWithCoords(clinics);
        if (!clinic || typeof MiniMap === 'undefined') return;
        MiniMap.render('doctorMiniMap', {
            lat: clinic.latitude,
            lng: clinic.longitude,
            title: name(clinic, 'name_ar', 'name_en')
        });
    }

    // ================= INIT =================

    function init() {
        load();
    }

    return { init };

})();

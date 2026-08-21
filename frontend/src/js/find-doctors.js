/**
 * MedOrbit v2 - Find Doctors
 * GET /api/doctors with specialty filter + pagination.
 */
const FindDoctors = (() => {

    const PAGE_SIZE = 12;

    // Fallback labels keep discovery usable if reference-data loading fails.
    // The live /specialties response replaces these entries with authoritative
    // UUID-backed options before a recommendation signal can be emitted.
    let specialties = [
        { en: 'Anesthesiology', ar: 'التخدير' },
        { en: 'Cardiology', ar: 'طب القلب' },
        { en: 'Dentistry', ar: 'طب الأسنان' },
        { en: 'Dermatology', ar: 'طب الجلدية' },
        { en: 'Emergency Medicine', ar: 'طب الطوارئ' },
        { en: 'Endocrinology', ar: 'طب الغدد الصماء' },
        { en: 'ENT', ar: 'طب الأنف والأذن والحنجرة' },
        { en: 'Gastroenterology', ar: 'طب الجهاز الهضمي' },
        { en: 'General Practice', ar: 'طب عام' },
        { en: 'General Surgery', ar: 'جراحة عامة' },
        { en: 'Geriatrics', ar: 'طب الشيخوخة' },
        { en: 'Hematology', ar: 'طب الدم' },
        { en: 'Nephrology', ar: 'طب الكلى' },
        { en: 'Neurology', ar: 'طب الأعصاب' },
        { en: 'Obstetrics & Gynecology', ar: 'طب النساء والتوليد' },
        { en: 'Oncology', ar: 'طب الأورام' },
        { en: 'Ophthalmology', ar: 'طب العيون' },
        { en: 'Orthopedics', ar: 'جراحة العظام' },
        { en: 'Pediatrics', ar: 'طب الأطفال' },
        { en: 'Physiotherapy', ar: 'طب إعادة التأهيل' },
        { en: 'Psychiatry', ar: 'طب نفسي' },
        { en: 'Pulmonology', ar: 'طب الرئة' },
        { en: 'Radiology', ar: 'الأشعة' },
        { en: 'Rheumatology', ar: 'طب الروماتيزم' },
        { en: 'Urology', ar: 'جراحة المسالك البولية' }
    ];

    const RECOMMENDED_LIMIT = 6;

    let currentPage = 1;
    let searchDebounceTimer = null;
    let activeController = null;
    let recommendedController = null;
    let recommendedDoctors; // undefined = not loaded yet, null = errored, array = loaded (cached across language changes)
    const LIST_CACHE_TTL = 60000; // 1 min — doctor list/filters rarely change that fast

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

    function doctorName(d) {
        const ar = isAr();
        const first = (ar ? d.first_name_ar : d.first_name_en) || d.first_name_ar || d.first_name_en || '';
        const last = (ar ? d.last_name_ar : d.last_name_en) || d.last_name_ar || d.last_name_en || '';
        return (first + ' ' + last).trim() || d.email || '';
    }

    function specialtyName(d) {
        return (isAr() ? d.specialty_ar : d.specialty_en) || d.specialty_ar || d.specialty_en || '';
    }

    // ================= SPECIALTY FILTER =================

    function renderSpecialtyOptions() {
        const select = document.getElementById('specialtyFilter');
        if (!select) return;
        const selected = select.value;
        const ar = isAr();

        select.innerHTML =
            '<option value="">' + escapeHtml(t('doctors.specialtyAll')) + '</option>' +
            specialties.map(s => `<option value="${escapeHtml(s.en)}" data-specialty-id="${escapeHtml(s.id || '')}">${escapeHtml(ar ? s.ar : s.en)}</option>`).join('');

        select.value = selected;
    }

    async function loadSpecialties() {
        const response = await API.get('/specialties');
        const rows = Array.isArray(response.data) ? response.data : [];
        specialties = rows
            .filter(s => s?.id && s?.name_en)
            .map(s => ({ id: s.id, en: s.name_en, ar: s.name_ar || s.name_en }));
    }

    function recordSpecialtySearch(select) {
        const specialtyId = select?.selectedOptions?.[0]?.dataset?.specialtyId;
        if (specialtyId && API.isAuthenticated()) {
            API.social.specialtySearch(specialtyId).catch(() => {});
        }
    }

    // ================= DATA =================

    async function loadDoctors(page = 1) {
        currentPage = page;

        const content = document.getElementById('doctorsContent');
        const pagination = document.getElementById('pagination');
        if (!content) return;

        // Cancel a still-in-flight previous request so a slow earlier
        // response can't land after a newer one and show stale results.
        if (activeController) activeController.abort();
        activeController = API.makeCancellable();

        content.innerHTML = renderSkeleton();
        if (pagination) pagination.innerHTML = '';

        const query = {
            page,
            limit: PAGE_SIZE,
            search: document.getElementById('searchInput')?.value.trim(),
            specialty: document.getElementById('specialtyFilter')?.value
        };

        try {
            const res = await API.doctors.list(query, { auth: true, signal: activeController.signal, cacheTTL: API.isAuthenticated() ? undefined : LIST_CACHE_TTL });
            const { doctors, pagination: pageInfo } = res.data;

            if (!doctors || doctors.length === 0) {
                content.innerHTML = renderEmpty();
                return;
            }

            content.innerHTML = '<div class="entity-grid">' + doctors.map(renderDoctorCard).join('') + '</div>';
            renderPagination(pageInfo);

        } catch (err) {
            if (err.name === 'AbortError') return; // superseded — the newer request will render
            console.error('FindDoctors: failed to load doctors', err);
            content.innerHTML = renderError();
        }
    }

    // ================= RECOMMENDED DOCTORS =================
    // Independent surface from the ordinary catalogue below: separate
    // request, separate loading/success/empty/error state, and a failure
    // here must never break ordinary search/filter/pagination.

    function renderRecommendedContent() {
        const content = document.getElementById('recommendedDoctorsContent');
        const section = document.getElementById('recommendedDoctorsSection');
        if (!content || !section) return;

        if (!recommendedDoctors || recommendedDoctors.length === 0) {
            section.hidden = true;
            return;
        }

        section.hidden = false;
        content.innerHTML = '<div class="entity-grid">' + recommendedDoctors.map(renderDoctorCard).join('') + '</div>';
    }

    function renderRecommendedError() {
        const content = document.getElementById('recommendedDoctorsContent');
        const section = document.getElementById('recommendedDoctorsSection');
        if (!content || !section) return;
        section.hidden = false;
        content.innerHTML = '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('doctors.recommendedUnavailable')) + '</p>' +
            '<button type="button" class="btn btn-secondary btn-sm" id="recommendedRetryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
            '</div>';
    }

    async function loadRecommendedDoctors() {
        const section = document.getElementById('recommendedDoctorsSection');
        const content = document.getElementById('recommendedDoctorsContent');
        if (!section || !content) return;

        if (recommendedController) recommendedController.abort();
        recommendedController = API.makeCancellable();

        section.hidden = false;
        content.innerHTML = renderSkeleton(RECOMMENDED_LIMIT);

        try {
            const res = await API.recommendations.doctors(RECOMMENDED_LIMIT, { signal: recommendedController.signal });
            recommendedDoctors = Array.isArray(res.data?.doctors) ? res.data.doctors : [];
            renderRecommendedContent();
        } catch (err) {
            if (err.name === 'AbortError') return; // superseded by a newer request
            console.error('FindDoctors: failed to load recommended doctors', err);
            recommendedDoctors = null;
            renderRecommendedError();
        }
    }

    // ================= RENDER =================

    function skeletonCard() {
        return '<div class="entity-card"><div class="entity-card-body">' +
            '<div class="skeleton" style="width:52px;height:52px;border-radius:50%;flex-shrink:0;"></div>' +
            '<div style="flex:1;"><div class="skeleton" style="height:16px;width:70%;margin-bottom:8px;"></div>' +
            '<div class="skeleton" style="height:12px;width:50%;"></div></div>' +
            '</div></div>';
    }

    function renderSkeleton(count = 6) {
        return '<div class="entity-grid">' + skeletonCard().repeat(count) + '</div>';
    }

    function renderEmpty() {
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas fa-user-doctor"></i></div>' +
            '<h3>' + escapeHtml(t('doctors.empty')) + '</h3>' +
            '</div>';
    }

    function renderError() {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('doctors.error')) + '</p>' +
            '<button type="button" class="btn btn-secondary btn-sm" id="retryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
            '</div>';
    }

    const REASON_KEYS = {
        FOLLOWED_DOCTOR: 'doctors.reasonFollowed',
        INTEREST_SPECIALTY: 'doctors.reasonSpecialty',
        TRENDING: 'doctors.reasonTrending',
        RECENT: 'doctors.reasonRecent'
    };

    function renderDoctorCard(d) {
        const ar = isAr();
        const name = escapeHtml(doctorName(d));
        const specialty = escapeHtml(specialtyName(d));
        const initials = (doctorName(d) || '?').trim().charAt(0).toUpperCase();
        const rating = d.average_rating != null ? Number(d.average_rating).toFixed(1) : null;
        const acceptingBadge = d.is_accepting_patients === false
            ? '<span class="badge badge-danger">' + escapeHtml(t('doctors.notAccepting')) + '</span>'
            : (d.is_accepting_patients ? '<span class="badge badge-success">' + escapeHtml(t('doctors.accepting')) + '</span>' : '');
        const reasonKey = d.reason_code && REASON_KEYS[d.reason_code];
        const reasonBadge = reasonKey
            ? '<span class="badge badge-info">' + escapeHtml(t(reasonKey)) + '</span>' : '';

        return (
            '<div class="entity-card">' +
                '<div class="entity-card-body">' +
                    '<div class="entity-avatar">' +
                        (d.profile_image_url ? '<img src="' + escapeHtml(API.assetUrl(d.profile_image_url)) + '" alt="">' : escapeHtml(initials)) +
                    '</div>' +
                    '<div class="entity-card-info">' +
                        '<div class="entity-card-title" title="' + name + '">' + name + '</div>' +
                        (specialty ? '<div class="entity-card-subtitle">' + specialty + '</div>' : '') +
                        '<div class="entity-card-meta">' +
                            (rating ? '<span class="rating"><span class="rating-stars">★</span><span class="rating-value">' + rating + (d.total_ratings ? ' (' + d.total_ratings + ')' : '') + '</span></span>' : '') +
                            (d.years_of_experience != null ? '<span><i class="fas fa-briefcase"></i>' + escapeHtml(String(d.years_of_experience)) + ' ' + escapeHtml(t('doctors.yearsExp')) + '</span>' : '') +
                            (d.consultation_fee != null ? '<span><i class="fas fa-shekel-sign"></i>' + escapeHtml(String(d.consultation_fee)) + '</span>' : '') +
                        '</div>' +
                        ((acceptingBadge || reasonBadge) ? '<div class="entity-card-badges">' + acceptingBadge + reasonBadge + '</div>' : '') +
                    '</div>' +
                '</div>' +
                '<div class="entity-card-footer">' +
                    '<a class="btn btn-primary btn-sm" href="doctor.html?id=' + encodeURIComponent(d.id) + '">' +
                        '<i class="fas fa-arrow-' + (ar ? 'left' : 'right') + '"></i> ' + escapeHtml(t('doctors.viewProfile')) +
                    '</a>' +
                '</div>' +
            '</div>'
        );
    }

    function renderPagination(pageInfo) {
        const el = document.getElementById('pagination');
        if (!el || !pageInfo || pageInfo.totalPages <= 1) {
            if (el) el.innerHTML = '';
            return;
        }

        const { page, totalPages } = pageInfo;
        let html = '';

        html += `<button type="button" class="pagination-btn" data-page="${page - 1}" ${page <= 1 ? 'disabled' : ''}><i class="fas fa-chevron-${isAr() ? 'right' : 'left'}"></i></button>`;

        const start = Math.max(1, page - 2);
        const end = Math.min(totalPages, page + 2);

        for (let p = start; p <= end; p++) {
            html += `<button type="button" class="pagination-btn${p === page ? ' active' : ''}" data-page="${p}">${p}</button>`;
        }

        html += `<button type="button" class="pagination-btn" data-page="${page + 1}" ${page >= totalPages ? 'disabled' : ''}><i class="fas fa-chevron-${isAr() ? 'left' : 'right'}"></i></button>`;

        el.innerHTML = html;

        el.querySelectorAll('.pagination-btn:not(:disabled)').forEach(btn => {
            btn.addEventListener('click', () => {
                loadDoctors(parseInt(btn.dataset.page, 10));
                window.scrollTo({ top: 0, behavior: 'smooth' });
            });
        });
    }

    // ================= INIT =================

    async function init() {
        try {
            await loadSpecialties();
        } catch (error) {
            console.warn('FindDoctors: specialties unavailable', error);
        }
        renderSpecialtyOptions();

        const params = new URLSearchParams(window.location.search);
        const initialSearch = params.get('search');
        if (initialSearch) {
            const input = document.getElementById('searchInput');
            if (input) input.value = initialSearch;
        }

        const initialSpecialty = params.get('specialty');
        if (initialSpecialty) {
            const select = document.getElementById('specialtyFilter');
            if (select) {
                select.value = initialSpecialty;
                recordSpecialtySearch(select);
            }
        }

        loadDoctors(1);
        if (API.isAuthenticated()) loadRecommendedDoctors();

        document.getElementById('searchInput')?.addEventListener('input', () => {
            clearTimeout(searchDebounceTimer);
            searchDebounceTimer = setTimeout(() => loadDoctors(1), 400);
        });

        document.getElementById('specialtyFilter')?.addEventListener('change', (event) => {
            recordSpecialtySearch(event.currentTarget);
            loadDoctors(1);
        });

        document.getElementById('filterToggleBtn')?.addEventListener('click', () => {
            document.getElementById('filterCollapsible')?.classList.toggle('open');
        });

        document.getElementById('doctorsContent')?.addEventListener('click', (e) => {
            if (e.target.closest('#retryBtn')) loadDoctors(currentPage);
        });

        document.getElementById('recommendedDoctorsContent')?.addEventListener('click', (e) => {
            if (e.target.closest('#recommendedRetryBtn')) loadRecommendedDoctors();
        });

        window.addEventListener('languageChanged', () => {
            renderSpecialtyOptions();
            loadDoctors(currentPage);
            // Cached data has both AR/EN fields — re-render, don't refetch.
            if (Array.isArray(recommendedDoctors)) renderRecommendedContent();
            else if (recommendedDoctors === null) renderRecommendedError();
        });
    }

    return { init };

})();

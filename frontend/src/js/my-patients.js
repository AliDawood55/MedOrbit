/**
 * MedOrbit v2 - My Patients (doctor's patient list)
 *
 * GET /doctors/me/patients (backend/src/routes/doctor.routes.js) — the
 * doctor id is resolved server-side from the JWT, never accepted from the
 * client, so a caller can only ever see their own roster. The list is
 * derived from appointment history (no dedicated relationship table), same
 * approach patient-detail.html's ownership check will need.
 */
const MyPatients = (() => {

    let patients = [];

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

    function fmtDate(value) {
        if (!value) return '';
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return String(value);
        return d.toLocaleDateString(isAr() ? 'ar' : 'en-US', { year: 'numeric', month: 'short', day: 'numeric' });
    }

    function patientName(p) {
        const ar = isAr();
        const first = (ar ? p.first_name_ar : p.first_name_en) || p.first_name_ar || p.first_name_en || '';
        const last = (ar ? p.last_name_ar : p.last_name_en) || p.last_name_ar || p.last_name_en || '';
        return (first + ' ' + last).trim() || p.email || '';
    }

    // GET /doctors/me/patients — always called (matches this codebase's
    // convention), rendering whatever comes back.
    async function loadPatients() {
        const content = document.getElementById('patientsContent');
        if (!content) return;

        content.innerHTML = renderSkeleton();

        try {
            const res = await API.care.myPatients();
            patients = Array.isArray(res?.data) ? res.data : [];
            render();
        } catch (err) {
            console.error('MyPatients: failed to load patients', err);
            content.innerHTML = renderError();
        }
    }

    function filteredPatients() {
        const query = (document.getElementById('patientSearchInput')?.value || '').trim().toLowerCase();
        const filter = document.getElementById('patientFilterSelect')?.value || 'all';

        return patients.filter((p) => {
            const matchesQuery = !query || patientName(p).toLowerCase().includes(query);
            const matchesFilter =
                filter === 'all' ||
                (filter === 'upcoming' && p.has_upcoming) ||
                (filter === 'past' && !p.has_upcoming);
            return matchesQuery && matchesFilter;
        });
    }

    function render() {
        const content = document.getElementById('patientsContent');
        if (!content) return;

        if (!patients.length) {
            content.innerHTML = renderEmpty();
            return;
        }

        const list = filteredPatients();
        if (!list.length) {
            content.innerHTML = renderFilteredEmpty();
            return;
        }

        content.innerHTML = '<div class="care-card-grid">' + list.map(renderPatientCard).join('') + '</div>';
    }

    function renderSkeleton() {
        const card = '<div class="care-person-card">' +
            '<div class="care-person-avatar skeleton" style="border-radius:50%;"></div>' +
            '<div class="care-person-info">' +
                '<div class="skeleton" style="height:14px;width:60%;margin-bottom:8px;"></div>' +
                '<div class="skeleton" style="height:11px;width:40%;margin-bottom:10px;"></div>' +
                '<div class="skeleton" style="height:11px;width:80%;"></div>' +
            '</div>' +
        '</div>';
        return '<div class="care-card-grid">' + card.repeat(3) + '</div>';
    }

    function renderEmpty() {
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas fa-user-injured"></i></div>' +
            '<h3>' + escapeHtml(t('myPatients.empty')) + '</h3>' +
            '<p>' + escapeHtml(t('myPatients.emptyHint')) + '</p>' +
        '</div>';
    }

    function renderError() {
        return '<div class="error-state">' +
            '<i class="fas fa-triangle-exclamation"></i>' +
            '<p>' + escapeHtml(t('myPatients.error')) + '</p>' +
            '<button type="button" class="btn btn-secondary btn-sm" id="patientsRetryBtn">' + escapeHtml(t('common.retry')) + '</button>' +
        '</div>';
    }

    // Search/filter matched zero of an otherwise non-empty roster. Runtime
    // bilingual copy (not an i18n.js key) since this state has no key of its
    // own yet — see PHASE 4 WAVE D1.
    function renderFilteredEmpty() {
        const ar = isAr();
        return '<div class="empty-state">' +
            '<div class="empty-state-icon"><i class="fas fa-magnifying-glass"></i></div>' +
            '<h3>' + escapeHtml(ar ? 'لا توجد نتائج مطابقة' : 'No matching patients') + '</h3>' +
            '<p>' + escapeHtml(ar ? 'جرّب تغيير كلمة البحث أو الفلتر.' : 'Try changing the search term or filter.') + '</p>' +
        '</div>';
    }

    function renderPatientCard(p) {
        const ar = isAr();
        const name = escapeHtml(patientName(p));
        const initials = (patientName(p) || '?').trim().charAt(0).toUpperCase();
        const nextDate = fmtDate(p.next_appointment_date);
        const lastDate = fmtDate(p.last_appointment_date);

        return (
            '<div class="care-person-card">' +
                '<div class="care-person-avatar">' +
                    (p.profile_image_url ? '<img src="' + escapeHtml(API.assetUrl(p.profile_image_url)) + '" alt="" data-fallback-initials="' + escapeHtml(initials) + '" onerror="MyPatients.__avatarFallback(this)">' : escapeHtml(initials)) +
                '</div>' +
                '<div class="care-person-info">' +
                    '<div class="care-person-name" title="' + name + '">' + name + '</div>' +
                    (p.has_upcoming ? '<div class="care-person-subtitle">' + escapeHtml(t('myPatients.upcomingBadge')) + '</div>' : '') +
                    '<div class="care-person-meta">' +
                        (nextDate ? '<span><i class="fas fa-calendar-check"></i>' + escapeHtml(t('myPatients.nextVisit')) + ': ' + escapeHtml(nextDate) + '</span>' : '') +
                        (lastDate ? '<span><i class="fas fa-clock-rotate-left"></i>' + escapeHtml(t('myPatients.lastVisit')) + ': ' + escapeHtml(lastDate) + '</span>' : '') +
                        (p.phone ? '<span><i class="fas fa-phone"></i>' + escapeHtml(p.phone) + '</span>' : '') +
                    '</div>' +
                    '<div class="care-person-actions">' +
                        '<a class="btn btn-primary btn-sm" href="patient-detail.html?id=' + encodeURIComponent(p.id) + '">' +
                            '<i class="fas fa-arrow-' + (ar ? 'left' : 'right') + '"></i> ' + escapeHtml(t('myPatients.viewDetails')) +
                        '</a>' +
                        '<a class="btn btn-secondary btn-sm" href="direct-messages.html?counterpart=' + encodeURIComponent(p.id) + '">' +
                            '<i class="fas fa-message"></i> ' + (ar ? 'راسل المريض' : 'Message patient') +
                        '</a>' +
                    '</div>' +
                '</div>' +
            '</div>'
        );
    }

    function init() {
        if (!API.requireAuth()) return;

        AuthGate.verifySession().then((state) => {
            if (state !== 'valid') return;
            const isDoctor = AuthGate.getVerifiedUser()?.role === 'doctor';
            if (!isDoctor) {
                document.getElementById('restrictedNotice').classList.remove('hidden');
                return;
            }

            document.getElementById('patientsPageContent').classList.remove('hidden');
            loadPatients();

            document.getElementById('patientSearchInput')?.addEventListener('input', render);
            document.getElementById('patientFilterSelect')?.addEventListener('change', render);
            document.getElementById('patientsContent')?.addEventListener('click', (e) => {
                if (e.target.closest('#patientsRetryBtn')) loadPatients();
            });
            // Filtered-empty copy is runtime bilingual text (not data-i18n),
            // so it needs its own re-render on language switch; skip this
            // while loading/error/true-empty/card-grid are showing so we
            // never clobber those states (mirrors my-records.js).
            window.addEventListener('languageChanged', () => {
                if (patients.length && !filteredPatients().length) render();
            });
        }).catch((err) => {
            console.error('MyPatients: failed to verify role', err);
            document.getElementById('restrictedNotice').classList.remove('hidden');
        });
    }

    // Swaps a broken avatar <img> for the same plain-text initials fallback
    // already used when no profile_image_url exists at all (mirrors
    // my-doctor.js). Invoked from a static onerror="MyPatients.__avatarFallback(this)"
    // attribute; the initials travel only as an HTML-escaped data attribute.
    function avatarFallback(img) {
        img.replaceWith(document.createTextNode(img.dataset.fallbackInitials || '?'));
    }

    return { init, __avatarFallback: avatarFallback };

})();

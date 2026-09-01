
const DoctorProfile = (() => {
    const DAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    let currentDoctor = null;
    let currentPosts = [];

    const isAr = () => (typeof I18n !== 'undefined' ? I18n.getLang() : 'ar') === 'ar';
    const t = (key) => typeof I18n !== 'undefined' ? I18n.t(key) : key;

    function escapeHtml(value) {
        if (value == null) return '';
        return String(value).replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }

    function assetUrl(value) {
        return API.assetUrl(value);
    }

    function localized(record, arKey, enKey) {
        return ((isAr() ? record?.[arKey] : record?.[enKey])
            || record?.[arKey] || record?.[enKey] || '').trim();
    }

    function displayName(doctor) {
        return `${localized(doctor, 'first_name_ar', 'first_name_en')} ${localized(doctor, 'last_name_ar', 'last_name_en')}`.trim();
    }

    function compactEmpty(ownerText, visitorText, href) {
        return '<div class="profile-compact-empty"><i class="fas fa-circle-info" aria-hidden="true"></i><span>'
            + escapeHtml(currentDoctor?.is_owner ? ownerText : visitorText) + '</span>'
            + (currentDoctor?.is_owner && href
                ? '<a class="text-link" href="' + href + '">' + escapeHtml(isAr() ? 'إضافة معلومات' : 'Add information') + '</a>'
                : '') + '</div>';
    }

    function tagList(values) {
        if (!Array.isArray(values) || !values.length) return '';
        return '<div class="profile-chip-list">' + values.map((value) =>
            '<span class="profile-chip">' + escapeHtml(value) + '</span>'
        ).join('') + '</div>';
    }

    function renderSkeleton() {
        return '<section class="doctor-hero skeleton-card" aria-busy="true">'
            + '<div class="skeleton doctor-avatar-skeleton"></div>'
            + '<div class="doctor-hero-copy"><div class="skeleton skeleton-line-lg"></div>'
            + '<div class="skeleton skeleton-line-md"></div><div class="skeleton skeleton-line-sm"></div></div></section>';
    }

    function renderState(icon, title, retry = false) {
        return '<div class="empty-state profile-state"><div class="empty-state-icon"><i class="fas ' + icon + '"></i></div>'
            + '<h2>' + escapeHtml(title) + '</h2>'
            + (retry ? '<button type="button" class="btn btn-secondary" id="retryBtn">' + escapeHtml(t('common.retry')) + '</button>' : '')
            + '</div>';
    }

    function heroActions(doctor) {
        if (doctor.is_owner) {
            return '<a class="btn btn-primary" href="doctor-profile-edit.html"><i class="fas fa-pen"></i>'
                + escapeHtml(isAr() ? 'تعديل الملف المهني' : 'Edit professional profile') + '</a>';
        }
        const user = API.getUser();
        const canMessage = ['patient', 'doctor'].includes(user?.role);
        const showMessage = !API.isAuthenticated() || canMessage;
        const redirect = encodeURIComponent('doctor.html?id=' + doctor.id);
        const messageHref = canMessage
            ? 'direct-messages.html?counterpart=' + encodeURIComponent(doctor.id)
            : 'login.html?redirect=' + redirect;
        const bookingAction = doctor.is_accepting_patients
            ? '<a class="btn btn-secondary" href="book-appointment.html?doctorId=' + encodeURIComponent(doctor.id) + '"><i class="fas fa-calendar-plus"></i>'
                + escapeHtml(t('doctor.bookAppointment')) + '</a>'
            : '<span class="btn btn-secondary disabled" aria-disabled="true"><i class="fas fa-calendar-xmark"></i>'
                + escapeHtml(isAr() ? 'لا يستقبل مواعيد جديدة حالياً' : 'Not currently accepting new appointments') + '</span>';
        return (showMessage ? '<a class="btn btn-primary" id="doctorMessageBtn" href="' + messageHref + '"><i class="fas fa-message"></i>'
            + escapeHtml(isAr() ? 'مراسلة' : 'Message') + '</a>' : '')
            + bookingAction
            + '<button type="button" class="btn btn-ghost" id="doctorFollowBtn"><i class="fas '
            + (doctor.is_following ? 'fa-user-check' : 'fa-user-plus') + '"></i><span>'
            + escapeHtml(doctor.is_following ? (isAr() ? 'متابَع' : 'Following') : (isAr() ? 'متابعة' : 'Follow'))
            + '</span></button>';
    }

    function renderHero(doctor) {
        const fullName = displayName(doctor) || (isAr() ? 'طبيب MedOrbit' : 'MedOrbit Doctor');
        const specialty = localized(doctor, 'specialty_ar', 'specialty_en');
        const rating = Number(doctor.average_rating || 0).toFixed(1);
        const initials = fullName.charAt(0).toUpperCase();
        const meta = [
            doctor.city ? '<span><i class="fas fa-location-dot"></i>' + escapeHtml(doctor.city) + '</span>' : '',
            doctor.years_of_experience != null ? '<span><i class="fas fa-briefcase"></i>' + escapeHtml(doctor.years_of_experience) + ' ' + escapeHtml(t('doctors.yearsExp')) + '</span>' : '',
            '<span><i class="fas fa-star"></i>' + escapeHtml(rating) + ' · ' + escapeHtml(doctor.total_ratings || 0) + ' ' + escapeHtml(isAr() ? 'تقييم' : 'ratings') + '</span>',
            '<span><i class="fas fa-users"></i><strong id="doctorFollowerCount">' + escapeHtml(doctor.follower_count || 0) + '</strong> ' + escapeHtml(isAr() ? 'متابع' : 'followers') + '</span>'
        ].filter(Boolean).join('');

        return '<section class="doctor-hero">'
            + '<div class="profile-avatar doctor-profile-avatar">'
            + (doctor.profile_image_url
                ? '<img src="' + escapeHtml(assetUrl(doctor.profile_image_url)) + '" alt="" data-fallback-initials="' + escapeHtml(initials) + '" onerror="DoctorProfile.__avatarFallback(this)">'
                : '<span>' + escapeHtml(initials) + '</span>') + '</div>'
            + '<div class="doctor-hero-copy"><div class="doctor-name-row"><h1>' + escapeHtml(fullName) + '</h1>'
            + (doctor.is_verified ? '<span class="verified-badge"><i class="fas fa-circle-check"></i>' + escapeHtml(isAr() ? 'طبيب معتمد' : 'Verified doctor') + '</span>' : '')
            + '</div>'
            + (specialty ? '<p class="doctor-specialty">' + escapeHtml(specialty)
                + (doctor.sub_specialty ? ' · ' + escapeHtml(doctor.sub_specialty) : '') + '</p>' : '')
            + (doctor.professional_headline ? '<p class="doctor-headline">' + escapeHtml(doctor.professional_headline) + '</p>' : '')
            + '<div class="doctor-meta">' + meta + '</div>'
            + '<span class="availability-pill ' + (doctor.is_accepting_patients ? 'available' : 'unavailable') + '">'
            + '<i class="fas fa-circle"></i>' + escapeHtml(doctor.is_accepting_patients ? t('doctors.accepting') : t('doctors.notAccepting')) + '</span>'
            + '</div><div class="doctor-primary-actions">' + heroActions(doctor) + '</div></section>';
    }

    function renderAbout(doctor) {
        const bio = doctor.professional_bio || localized(doctor, 'professional_bio_ar', 'professional_bio_en');
        const editHref = 'doctor-profile-edit.html';
        const section = (icon, title, content, emptyOwner, emptyVisitor) =>
            '<section class="profile-detail-card"><h2><i class="fas ' + icon + '"></i>' + escapeHtml(title) + '</h2>'
            + (content || compactEmpty(emptyOwner, emptyVisitor, editHref)) + '</section>';
        const list = (values) => Array.isArray(values) && values.length
            ? '<ul class="profile-clean-list">' + values.map((value) => '<li>' + escapeHtml(value) + '</li>').join('') + '</ul>'
            : '';

        return '<div class="profile-about-grid">'
            + section('fa-user-doctor', isAr() ? 'السيرة المهنية' : 'Professional bio',
                bio ? '<p class="profile-long-copy">' + escapeHtml(bio) + '</p>' : '',
                isAr() ? 'أضف سيرتك المهنية لبناء الثقة.' : 'Add your professional bio to build trust.',
                isAr() ? 'لم تُضف سيرة مهنية بعد.' : 'No professional bio listed yet.')
            + section('fa-stethoscope', isAr() ? 'مجالات الخبرة' : 'Areas of expertise', tagList(doctor.areas_of_expertise),
                isAr() ? 'أضف مجالات خبرتك.' : 'Add your areas of expertise.',
                isAr() ? 'لم تُدرج مجالات خبرة بعد.' : 'No expertise areas listed yet.')
            + section('fa-lightbulb', isAr() ? 'الاهتمامات المهنية' : 'Professional interests', tagList(doctor.professional_interests),
                isAr() ? 'أضف اهتماماتك المهنية.' : 'Add your professional interests.',
                isAr() ? 'لم تُدرج اهتمامات مهنية بعد.' : 'No professional interests listed yet.')
            + section('fa-graduation-cap', isAr() ? 'التعليم' : 'Education', list(doctor.education),
                isAr() ? 'أضف مؤهلاتك التعليمية.' : 'Add your education.',
                isAr() ? 'لم تُدرج معلومات تعليمية بعد.' : 'No education listed yet.')
            + section('fa-certificate', isAr() ? 'الشهادات' : 'Certifications', list(doctor.certifications),
                isAr() ? 'أضف شهاداتك المهنية.' : 'Add your certifications.',
                isAr() ? 'لم تُدرج شهادات بعد.' : 'No certifications listed yet.')
            + section('fa-language', isAr() ? 'اللغات' : 'Languages', tagList(doctor.languages_spoken),
                isAr() ? 'أضف اللغات التي تتحدثها.' : 'Add the languages you speak.',
                isAr() ? 'لم تُدرج لغات بعد.' : 'No languages listed yet.')
            + '</div>';
    }

    function renderSchedule(slots) {
        if (!slots.length) return compactEmpty(
            isAr() ? 'أضف أوقات التوفر.' : 'Add your availability.',
            isAr() ? 'لم يحدد الطبيب أوقات التوفر بعد.' : 'Availability has not been listed yet.',
            null
        );
        const days = Array.from({ length: 7 }, () => []);
        slots.forEach((slot) => {
            const day = Number(slot.day_of_week);
            if (day >= 0 && day < 7) days[day].push(slot);
        });
        return '<div class="schedule-grid">' + days.map((daySlots, index) =>
            '<div class="schedule-day' + (index === new Date().getDay() ? ' today' : '') + '"><strong>'
            + escapeHtml(t('day.' + DAY_KEYS[index])) + '</strong>'
            + (daySlots.length ? daySlots.map((slot) => '<span class="slot">'
                + escapeHtml(String(slot.start_time).slice(0, 5)) + '–' + escapeHtml(String(slot.end_time).slice(0, 5)) + '</span>').join('')
                : '<span class="schedule-day-off">' + escapeHtml(t('doctor.closed')) + '</span>') + '</div>'
        ).join('') + '</div>';
    }

    function renderReview(review) {
        const copy = review.review_text || localized(review, 'review_text_ar', 'review_text_en');
        const author = localized(review, 'patient_first_name_ar', 'patient_first_name_en') || (isAr() ? 'مريض' : 'Patient');
        const date = review.created_at ? new Date(review.created_at).toLocaleDateString(isAr() ? 'ar' : 'en-US') : '';
        return '<article class="review-item"><div class="review-header"><strong>' + escapeHtml(author) + '</strong><span>' + escapeHtml(date) + '</span></div>'
            + '<div class="rating"><i class="fas fa-star"></i>' + escapeHtml(Number(review.rating || 0).toFixed(1)) + '</div>'
            + (copy ? '<p class="review-text">' + escapeHtml(copy) + '</p>' : '') + '</article>';
    }

    function renderReviews(reviews) {
        return reviews.length ? '<div class="review-list">' + reviews.map(renderReview).join('') + '</div>'
            : compactEmpty(isAr() ? 'لا توجد تقييمات بعد.' : 'No reviews yet.', isAr() ? 'لا توجد تقييمات بعد.' : 'No reviews yet.');
    }

    function renderPostCard(post) {
        const title = post.title || localized(post, 'title_ar', 'title_en');
        const preview = post.body?.length > 150 ? `${post.body.slice(0, 150)}…` : (post.body || '');
        return '<button type="button" class="doctor-post-card" data-post-id="' + escapeHtml(post.id) + '"><span class="doctor-post-icon"><i class="fas fa-newspaper"></i></span>'
            + '<span><strong>' + escapeHtml(title) + '</strong><small>' + escapeHtml(preview) + '</small></span></button>';
    }

    function renderPosts(posts) {
        return posts.length ? '<div class="doctor-post-grid">' + posts.map(renderPostCard).join('') + '</div>'
            : compactEmpty(isAr() ? 'انشر أول منشور صحي.' : 'Publish your first health post.',
                isAr() ? 'لا توجد منشورات منشورة بعد.' : 'No published posts yet.',
                currentDoctor?.is_owner ? 'doctor-posts.html' : null);
    }

    function renderClinics(clinics) {
        if (!clinics.length) return compactEmpty(
            isAr() ? 'أضف معلومات العيادة.' : 'Add clinic information.',
            isAr() ? 'لا توجد عيادات مدرجة بعد.' : 'No clinics listed yet.',
            null
        );
        return '<div class="clinic-profile-grid">' + clinics.map((clinic) => {
            const clinicName = localized(clinic, 'name_ar', 'name_en');
            const address = localized(clinic, 'address_ar', 'address_en');
            return '<a class="clinic-profile-card" href="clinic.html?id=' + encodeURIComponent(clinic.id) + '"><i class="fas fa-hospital"></i><span><strong>'
                + escapeHtml(clinicName) + '</strong><small>' + escapeHtml([address, clinic.city].filter(Boolean).join(' · ')) + '</small></span></a>';
        }).join('') + '</div>'
            + (clinics.some((clinic) => clinic.latitude != null && clinic.longitude != null)
                ? '<div id="doctorMiniMap" class="mini-map profile-map"></div>' : '');
    }

    function renderProfile(doctor, clinics, slots, reviews, posts) {
        const tabs = [
            ['about', 'fa-user', isAr() ? 'نبذة' : 'About'],
            ['posts', 'fa-newspaper', isAr() ? 'المنشورات' : 'Posts'],
            ['reviews', 'fa-star', isAr() ? 'التقييمات' : 'Reviews'],
            ['availability', 'fa-calendar-week', isAr() ? 'التوفر' : 'Availability'],
            ['clinics', 'fa-hospital', isAr() ? 'العيادات' : 'Clinics']
        ];
        const social = renderSocialLinks(doctor.social_links);
        return renderHero(doctor)
            + (social ? '<div class="doctor-profile-social">' + social + '</div>' : '')
            + '<section class="doctor-profile-body"><div class="profile-tabs" role="tablist">'
            + tabs.map((tab, index) => '<button type="button" class="profile-tab' + (index === 0 ? ' active' : '')
                + '" data-tab="' + tab[0] + '" role="tab" aria-selected="' + (index === 0) + '"><i class="fas ' + tab[1] + '"></i>' + escapeHtml(tab[2]) + '</button>').join('')
            + '</div><div class="profile-tab-panels">'
            + '<div class="profile-tab-panel active" data-panel="about">' + renderAbout(doctor) + '</div>'
            + '<div class="profile-tab-panel" data-panel="posts">' + renderPosts(posts) + '</div>'
            + '<div class="profile-tab-panel" data-panel="reviews">' + renderReviews(reviews) + '</div>'
            + '<div class="profile-tab-panel" data-panel="availability">' + renderSchedule(slots) + '</div>'
            + '<div class="profile-tab-panel" data-panel="clinics">' + renderClinics(clinics) + '</div>'
            + '</div></section>';
    }

    function renderSocialLinks(links) {
        if (!links || typeof links !== 'object') return '';
        const config = { website:['fa-globe','Website'], instagram:['fa-instagram','Instagram'], facebook:['fa-facebook','Facebook'], tiktok:['fa-tiktok','TikTok'], linkedin:['fa-linkedin','LinkedIn'], whatsapp:['fa-whatsapp','WhatsApp'], youtube:['fa-youtube','YouTube'], x:['fa-x-twitter','X'] };
        return Object.entries(config).map(([key, [icon, label]]) => {
            const href = String(links[key] || '').trim();
            return /^https:\/\//i.test(href) ? '<a class="btn btn-ghost btn-sm" href="' + escapeHtml(href) + '" target="_blank" rel="noopener noreferrer"><i class="fab ' + icon + '"></i> ' + escapeHtml(label) + '</a>' : '';
        }).join('');
    }

    function wireTabs(container) {
        container.querySelectorAll('.profile-tab').forEach((button) => button.addEventListener('click', () => {
            container.querySelectorAll('.profile-tab').forEach((item) => {
                const selected = item === button;
                item.classList.toggle('active', selected);
                item.setAttribute('aria-selected', String(selected));
            });
            container.querySelectorAll('.profile-tab-panel').forEach((panel) =>
                panel.classList.toggle('active', panel.dataset.panel === button.dataset.tab));
        }));
    }

    function wireFollow(container, doctor) {
        const button = container.querySelector('#doctorFollowBtn');
        if (!button) return;
        let following = Boolean(doctor.is_following);
        button.addEventListener('click', async () => {
            if (!API.isAuthenticated()) {
                location.href = 'login.html?redirect=' + encodeURIComponent('doctor.html?id=' + doctor.id);
                return;
            }
            button.disabled = true;
            try {
                const response = following ? await API.social.unfollow(doctor.id) : await API.social.follow(doctor.id);
                const next = Boolean(response.data.following);
                if (next !== following) {
                    const count = document.getElementById('doctorFollowerCount');
                    count.textContent = String(Math.max(0, Number(count.textContent) + (next ? 1 : -1)));
                }
                following = next;
                button.querySelector('i').className = 'fas ' + (following ? 'fa-user-check' : 'fa-user-plus');
                button.querySelector('span').textContent = following
                    ? (isAr() ? 'متابَع' : 'Following') : (isAr() ? 'متابعة' : 'Follow');
            } catch (err) {
                Toast?.error(err.message || (isAr() ? 'تعذر تحديث المتابعة' : 'Unable to update follow'));
            } finally {
                button.disabled = false;
            }
        });
    }

    function openPost(post) {
        const backdrop = document.createElement('div');
        backdrop.className = 'modal-backdrop';
        const modal = document.createElement('section');
        modal.className = 'modal-box';
        const title = document.createElement('h2');
        title.textContent = post.title || localized(post, 'title_ar', 'title_en');
        const body = document.createElement('p');
        body.className = 'profile-long-copy';
        body.textContent = post.body || '';
        const close = document.createElement('button');
        close.type = 'button';
        close.className = 'btn btn-secondary';
        close.textContent = isAr() ? 'إغلاق' : 'Close';
        const actions = document.createElement('div');
        actions.className = 'modal-actions';
        actions.appendChild(close);
        modal.append(title, body, actions);
        backdrop.appendChild(modal);
        document.body.appendChild(backdrop);
        const remove = () => backdrop.remove();
        close.addEventListener('click', remove);
        backdrop.addEventListener('click', (event) => { if (event.target === backdrop) remove(); });
    }

    function renderMap(clinics) {
        const clinic = clinics.find((item) => item.is_primary && item.latitude != null && item.longitude != null)
            || clinics.find((item) => item.latitude != null && item.longitude != null);
        if (clinic && typeof MiniMap !== 'undefined') {
            MiniMap.render('doctorMiniMap', { lat: clinic.latitude, lng: clinic.longitude, title: localized(clinic, 'name_ar', 'name_en') });
        }
    }

    async function load() {
        const id = new URLSearchParams(location.search).get('id');
        const content = document.getElementById('doctorContent');
        if (!id) {
            content.innerHTML = renderState('fa-user-doctor', t('doctor.notFound'));
            return;
        }
        content.innerHTML = renderSkeleton();
        try {
            const [profileResponse, availabilityResponse, postsResponse] = await Promise.all([
                API.doctors.get(id),
                API.doctors.availability(id, null).catch(() => null),
                API.care.doctorPosts(id).catch(() => null)
            ]);
            const payload = profileResponse.data;
            currentDoctor = payload.doctor;
            currentPosts = Array.isArray(postsResponse?.data) ? postsResponse.data : [];
            const clinics = payload.clinics || [];
            const slots = availabilityResponse?.data?.slots || payload.availability || [];
            content.innerHTML = renderProfile(currentDoctor, clinics, slots, payload.reviews || [], currentPosts);
            wireTabs(content);
            wireFollow(content, currentDoctor);
            content.querySelectorAll('[data-post-id]').forEach((card) => card.addEventListener('click', () => {
                const post = currentPosts.find((item) => String(item.id) === card.dataset.postId);
                if (post) openPost(post);
            }));
            renderMap(clinics);
            if (API.isAuthenticated()) API.social.doctorView(currentDoctor.id).catch(() => {});
        } catch (err) {
            content.innerHTML = err?.status === 404
                ? renderState('fa-user-doctor', t('doctor.notFound'))
                : renderState('fa-triangle-exclamation', t('doctors.error'), true);
            document.getElementById('retryBtn')?.addEventListener('click', load);
        }
    }

    function init() {
        load();
        window.addEventListener('languageChanged', () => { if (currentDoctor) load(); });
    }

function avatarFallback(img) {
        const span = document.createElement('span');
        span.textContent = img.dataset.fallbackInitials || '?';
        img.replaceWith(span);
    }

    return { init, __avatarFallback: avatarFallback };
})();

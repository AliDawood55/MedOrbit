const SocialFeed = (() => {

    const PAGE_SIZE = 10;
    const REQUEST_TIMEOUT_MS = 12000;
    const RETRY_DELAY_MS = 800;

    let items = [];
    let cursor = null;
    let loading = false;
    let viewObserver = null;
    let composerSubmitting = false;
    let composerProfile = null;

    const viewedPosts = new Set();
    const pendingLikes = new Set();
    const pendingFollows = new Set();

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const isAr = () => document.documentElement.dir === 'rtl';
    const t = (key) => (typeof I18n !== 'undefined' ? I18n.t(key) : key);

    function attrEscape(v) {
        return (typeof CSS !== 'undefined' && CSS.escape) ? CSS.escape(String(v)) : String(v).replace(/["\\]/g, '\\$&');
    }

    function doctorName(d) {
        return isAr()
            ? `${d.first_name_ar || ''} ${d.last_name_ar || ''}`.trim()
            : `${d.first_name_en || ''} ${d.last_name_en || ''}`.trim();
    }

    function doctorSpecialty(d) {
        return isAr() ? (d.specialty_ar || '') : (d.specialty_en || '');
    }

    function reasonLabel(code) {
        return {
            FOLLOWED_DOCTOR: isAr() ? 'لأنك تتابع هذا الطبيب' : 'Because you follow this doctor',
            INTEREST_SPECIALTY: isAr() ? 'بناءً على اهتمامك بهذا التخصص' : 'Based on your specialty interest',
            INTEREST_CATEGORY: isAr() ? 'بناءً على اهتماماتك' : 'Based on your interests',
            TRENDING: isAr() ? 'رائج' : 'Trending',
            RECENT: isAr() ? 'حديث' : 'Recent'
        }[code] || '';
    }

    function categoryLabel(cat) {
        const key = {
            health_tip: 'doctorPosts.categoryHealthTip',
            announcement: 'doctorPosts.categoryAnnouncement',
            clinic_news: 'doctorPosts.categoryClinicNews',
            article: 'doctorPosts.categoryArticle'
        }[cat];
        return key ? t(key) : (cat || '');
    }

    function formatDate(value) {
        const d = new Date(value);
        if (Number.isNaN(d.getTime())) return '';
        try {
            return new Intl.DateTimeFormat(isAr() ? 'ar' : 'en-US', { dateStyle: 'medium', timeStyle: 'short' }).format(d);
        } catch {
            return d.toLocaleString();
        }
    }

    function requireLogin() {
        if (!API.isAuthenticated()) {
            window.location.href = 'login.html?redirect=feed.html';
            return false;
        }
        return true;
    }

    function announce(message) {
        const live = document.getElementById('feedStatusLive');
        if (live) live.textContent = message;
    }

    function makeTimedController() {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
        return { signal: controller.signal, clear: () => clearTimeout(timer) };
    }

function avatarInitial(d) {
        return esc((doctorName(d) || 'D').trim().charAt(0).toUpperCase() || 'D');
    }

    function avatarMarkup(d) {
        if (d.profile_image_url) {

return `<img src="${esc(API.assetUrl(d.profile_image_url))}" alt="" data-avatar-fallback="${avatarInitial(d)}">`;
        }
        return avatarInitial(d);
    }

    function attachAvatarFallbacks(container) {
        container.querySelectorAll('img[data-avatar-fallback]').forEach((img) => {
            img.addEventListener('error', () => {
                const span = img.parentElement;
                if (span) span.textContent = img.dataset.avatarFallback;
            }, { once: true });
        });
    }

    function followButtonInner(following) {
        return (
            `<span class="btn-label"><i class="fas ${following ? 'fa-check' : 'fa-plus'}" aria-hidden="true"></i> ${esc(t(following ? 'feed.following' : 'feed.follow'))}</span>` +
            `<span class="spinner spinner-sm btn-spinner"></span>`
        );
    }

    function card(p) {
        const why = reasonLabel(p.reason_code);
        const liked = !!p.liked_by_me;
        const following = !!p.following_doctor;
        const ownDoctor = !!p.is_own_doctor;
        const title = isAr() ? (p.title_ar || p.title_en) : (p.title_en || p.title_ar);
        const specialty = doctorSpecialty(p.doctor);

        return (
            `<article class="card feed-card" data-post="${esc(p.id)}">` +
                `<div class="feed-card-header">` +
                    `<span class="feed-avatar">${avatarMarkup(p.doctor)}</span>` +
                    `<div class="feed-card-header-main">` +
                        `<div class="feed-doctor-name">${esc(doctorName(p.doctor))}</div>` +
                        `<div class="feed-meta">${specialty ? esc(specialty) + ' · ' : ''}${esc(formatDate(p.published_at))}</div>` +
                    `</div>` +
                    (ownDoctor ? '' :
                        `<button type="button" class="btn btn-secondary btn-sm feed-follow-btn${following ? ' following' : ''}" data-follow="${esc(p.doctor.id)}" aria-pressed="${following}">` +
                            followButtonInner(following) +
                        `</button>`) +
                `</div>` +
                (why ? `<div class="feed-reason"><i class="fas fa-star" aria-hidden="true"></i>${esc(why)}</div>` : '') +
                `<div class="feed-card-body">` +
                    `<span class="feed-category">${esc(categoryLabel(p.category))}</span>` +
                    (title ? `<h2 class="feed-title">${esc(title)}</h2>` : '') +
                    `<div class="feed-body">${esc(p.body)}</div>` +
                `</div>` +
                `<div class="feed-card-footer">` +
                    `<button type="button" class="feed-action-btn${liked ? ' liked' : ''}" data-like="${esc(p.id)}" aria-pressed="${liked}" aria-label="${esc(t('feed.like'))}">` +
                        `<i class="fas fa-heart" aria-hidden="true"></i><span>${esc(p.like_count || 0)}</span>` +
                    `</button>` +
                    `<button type="button" class="feed-action-btn" data-comments="${esc(p.id)}" aria-label="${esc(t('feed.comment'))}">` +
                        `<i class="fas fa-comment" aria-hidden="true"></i><span>${esc(p.comment_count || 0)}</span>` +
                    `</button>` +
                `</div>` +
                `<div class="comments-panel hidden" id="comments-${esc(p.id)}"></div>` +
            `</article>`
        );
    }

    function render() {
        const list = document.getElementById('feedList');
        list.innerHTML = items.map(card).join('');
        document.getElementById('feedEmpty').classList.toggle('hidden', items.length > 0);
        attachAvatarFallbacks(list);
        wire();
    }

    function showSkeleton(show) {
        document.getElementById('feedSkeleton').classList.toggle('hidden', !show);
    }

    function showError(show) {
        document.getElementById('feedError').classList.toggle('hidden', !show);
    }

async function load(reset = false) {
        if (loading) return;
        loading = true;

        if (reset) {
            items = [];
            cursor = null;
            document.getElementById('feedList').innerHTML = '';
            document.getElementById('feedEmpty').classList.add('hidden');
            document.getElementById('feedMore').classList.add('hidden');
        }
        showError(false);
        showSkeleton(reset);

        const query = { limit: PAGE_SIZE, ...(cursor ? { cursor } : {}) };
        const maxAttempts = 2;
        let lastErr = null;

        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            const { signal, clear } = makeTimedController();
            try {
                const res = await API.social.feed(query, { signal });
                clear();
                const newItems = Array.isArray(res?.data?.items) ? res.data.items : [];
                items = items.concat(newItems);
                cursor = res?.data?.next_cursor || null;
                render();
                document.getElementById('feedMore').classList.toggle('hidden', !res?.data?.has_more);
                loading = false;
                showSkeleton(false);
                if (reset) {
                    const stream = document.getElementById('feedStream');
                    if (stream) stream.scrollTop = 0;
                }
                return;
            } catch (err) {
                clear();
                lastErr = err;
                const clientError = err?.status >= 400 && err?.status < 500;
                if (attempt < maxAttempts && !clientError) {
                    await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
                    continue;
                }
                break;
            }
        }

        console.error('SocialFeed: failed to load feed', lastErr);
        loading = false;
        showSkeleton(false);
        if (!items.length) {
            showError(true);
        } else if (typeof Toast !== 'undefined') {
            Toast.error(t('feed.errorTitle'));
        }
    }

function updateLikeButton(btn, post) {
        btn.classList.toggle('liked', !!post.liked_by_me);
        btn.setAttribute('aria-pressed', String(!!post.liked_by_me));
        const span = btn.querySelector('span');
        if (span) span.textContent = String(post.like_count || 0);
    }

    async function handleLike(btn) {
        if (!requireLogin()) return;
        const id = btn.dataset.like;
        if (pendingLikes.has(id)) return;
        const post = items.find(x => x.id === id);
        if (!post) return;

        pendingLikes.add(id);
        btn.classList.add('pending');

        const wasLiked = !!post.liked_by_me;
        post.liked_by_me = !wasLiked;
        post.like_count = Math.max(0, (post.like_count || 0) + (wasLiked ? -1 : 1));
        updateLikeButton(btn, post);

        try {
            if (wasLiked) await API.social.unlike(id);
            else await API.social.like(id);
        } catch (err) {
            console.error('SocialFeed: like failed', err);
            post.liked_by_me = wasLiked;
            post.like_count = Math.max(0, (post.like_count || 0) + (wasLiked ? 1 : -1));
            updateLikeButton(btn, post);
            if (typeof Toast !== 'undefined') Toast.error(t('feed.likeError'));
        } finally {
            pendingLikes.delete(id);
            btn.classList.remove('pending');
        }
    }

async function handleFollow(btn) {
        if (!requireLogin()) return;
        const doctorId = btn.dataset.follow;
        if (pendingFollows.has(doctorId)) return;
        const post = items.find(x => x.doctor.id === doctorId);
        if (!post) return;
        if (post.is_own_doctor) return;

        pendingFollows.add(doctorId);
        btn.classList.add('loading');
        btn.disabled = true;

        const wasFollowing = !!post.following_doctor;
        try {
            if (wasFollowing) await API.social.unfollow(doctorId);
            else await API.social.follow(doctorId);

            const nowFollowing = !wasFollowing;
            items.forEach(p => { if (p.doctor.id === doctorId) p.following_doctor = nowFollowing; });
            document.querySelectorAll(`[data-follow="${attrEscape(doctorId)}"]`).forEach(b => {
                b.classList.toggle('following', nowFollowing);
                b.setAttribute('aria-pressed', String(nowFollowing));
                b.innerHTML = followButtonInner(nowFollowing);
            });
        } catch (err) {
            console.error('SocialFeed: follow failed', err);
            if (typeof Toast !== 'undefined') Toast.error(t('feed.followError'));
        } finally {
            pendingFollows.delete(doctorId);
            document.querySelectorAll(`[data-follow="${attrEscape(doctorId)}"]`).forEach(b => {
                b.classList.remove('loading');
                b.disabled = false;
            });
        }
    }

function renderComments(postId, panel, comments) {
        const rows = comments.map(c => {
            const author = isAr()
                ? `${c.first_name_ar || ''} ${c.last_name_ar || ''}`.trim()
                : `${c.first_name_en || ''} ${c.last_name_en || ''}`.trim();
            return `<div class="comment-row"><div class="comment-author">${esc(author)}</div><div>${esc(c.body)}</div></div>`;
        }).join('');

        const formHtml = API.isAuthenticated()
            ? `<form class="comment-form" data-comment-form="${esc(postId)}">` +
                `<input maxlength="1000" required placeholder="${esc(t('feed.commentPlaceholder'))}" aria-label="${esc(t('feed.commentPlaceholder'))}">` +
                `<button type="submit" class="btn btn-primary btn-sm">${esc(t('feed.commentSend'))}</button>` +
              `</form>`
            : '';

        panel.innerHTML = rows + formHtml;

        const form = panel.querySelector('form');
        if (!form) return;

        form.addEventListener('submit', async (e) => {
            e.preventDefault();
            if (form.dataset.submitting === '1') return;

            const input = form.querySelector('input');
            const value = input.value.trim();
            if (!value) return;

            form.dataset.submitting = '1';
            const submitBtn = form.querySelector('button');
            submitBtn.disabled = true;
            input.disabled = true;

            try {
                await API.social.addComment(postId, { body: value });
                input.value = '';

                const post = items.find(x => x.id === postId);
                if (post) {
                    post.comment_count = (post.comment_count || 0) + 1;
                    const countSpan = document.querySelector(`[data-comments="${attrEscape(postId)}"] span`);
                    if (countSpan) countSpan.textContent = String(post.comment_count);
                }

                await loadComments(postId, panel);
            } catch (err) {
                console.error('SocialFeed: failed to add comment', err);
                if (typeof Toast !== 'undefined') Toast.error(t('feed.commentError'));
                submitBtn.disabled = false;
                input.disabled = false;
                form.dataset.submitting = '';
            }
        });
    }

    async function loadComments(postId, panel) {
        panel.innerHTML = `<div class="spinner" role="status" aria-label="${esc(t('common.loading'))}"></div>`;

        const { signal, clear } = makeTimedController();
        try {
            const res = await API.social.comments(postId, { signal });
            clear();
            renderComments(postId, panel, Array.isArray(res?.data) ? res.data : []);
        } catch (err) {
            clear();
            console.error('SocialFeed: failed to load comments', err);
            panel.innerHTML = `<p style="padding:10px 0;color:var(--danger);font-size:13px;">${esc(t('feed.commentError'))}</p>`;
        }
    }

    function toggleComments(postId) {
        const panel = document.getElementById(`comments-${postId}`);
        if (!panel) return;
        const nowHidden = panel.classList.toggle('hidden');
        if (!nowHidden) loadComments(postId, panel);
    }

const feedDesktopMedia = (typeof window.matchMedia === 'function')
        ? window.matchMedia('(min-width: 1025px)')
        : null;

    function currentObserverRoot() {
        return (feedDesktopMedia && feedDesktopMedia.matches)
            ? document.getElementById('feedStream')
            : null;
    }

function observeViews() {
        viewObserver?.disconnect();
        if (!API.isAuthenticated() || typeof IntersectionObserver === 'undefined') {
            viewObserver = null;
            return;
        }

        viewObserver = new IntersectionObserver((entries) => {
            entries.forEach((entry) => {
                if (!entry.isIntersecting || entry.intersectionRatio < 0.5) return;
                const id = entry.target.dataset.post;
                if (!id || viewedPosts.has(id)) return;
                viewedPosts.add(id);
                viewObserver.unobserve(entry.target);
                API.social.view(id).catch(() => {});
            });
        }, { root: currentObserverRoot(), threshold: 0.5 });

        document.querySelectorAll('[data-post]').forEach((el) => {
            if (!viewedPosts.has(el.dataset.post)) viewObserver.observe(el);
        });
    }

    function wire() {
        document.querySelectorAll('[data-like]').forEach(btn => btn.addEventListener('click', () => handleLike(btn)));
        document.querySelectorAll('[data-follow]').forEach(btn => btn.addEventListener('click', () => handleFollow(btn)));
        document.querySelectorAll('[data-comments]').forEach(btn => btn.addEventListener('click', () => toggleComments(btn.dataset.comments)));
        observeViews();
    }

function composerDisplayName(profile) {
        const name = isAr()
            ? [profile.first_name_ar, profile.last_name_ar].filter(Boolean).join(' ')
            : [profile.first_name_en, profile.last_name_en].filter(Boolean).join(' ');
        return name || profile.email || '';
    }

    async function submitComposerPost() {
        if (composerSubmitting) return;

        const alertBox = document.getElementById('composerAlert');
        alertBox.className = 'alert';

        const bodyInput = document.getElementById('composerBody');
        const categorySelect = document.getElementById('composerCategory');
        const bodyValue = bodyInput.value.trim();

        if (!bodyValue) {
            alertBox.classList.add('error');
            alertBox.textContent = t('feed.composerBodyRequired');
            bodyInput.focus();
            return;
        }

        composerSubmitting = true;
        const submitBtn = document.getElementById('composerSubmit');
        submitBtn.classList.add('loading');
        submitBtn.disabled = true;

        try {
            await API.care.createPost({
                category: categorySelect.value,
                body: bodyValue,

title: bodyValue.slice(0, 140),
                isPublished: true
            });

            bodyInput.value = '';
            categorySelect.selectedIndex = 0;
            if (typeof Toast !== 'undefined') Toast.success(t('feed.publishSuccess'));
            announce(t('feed.publishSuccess'));
            await load(true);
        } catch (err) {
            console.error('SocialFeed: failed to publish post', err);
            alertBox.classList.add('error');
            alertBox.textContent = err?.message || t('feed.publishError');
            announce(t('feed.publishError'));
        } finally {
            composerSubmitting = false;
            submitBtn.classList.remove('loading');
            submitBtn.disabled = false;
        }
    }

    async function initComposer() {
        if (!API.isAuthenticated()) return;

const cachedUser = API.getUser();
        if (cachedUser && cachedUser.role !== 'doctor') return;

        const state = await AuthGate.verifySession();
        if (state !== 'valid') return;

        const profile = AuthGate.getVerifiedUser();
        if (!profile || profile.role !== 'doctor') return;

        composerProfile = profile;
        renderComposerIdentity();
        document.getElementById('feedComposer').classList.remove('hidden');
        document.getElementById('composerSubmit').addEventListener('click', submitComposerPost);
        wireComposerExpansion();
    }

function wireComposerExpansion() {
        const composer = document.getElementById('feedComposer');
        const bodyInput = document.getElementById('composerBody');

        composer.addEventListener('focusin', () => composer.classList.add('expanded'));
        composer.addEventListener('focusout', (e) => {
            if (composer.contains(e.relatedTarget)) return;
            if (bodyInput.value.trim()) return;
            composer.classList.remove('expanded');
        });
    }

    function renderComposerIdentity() {
        if (!composerProfile) return;
        const displayName = composerDisplayName(composerProfile);
        const initial = esc((displayName.trim().charAt(0) || '?').toUpperCase());
        const avatarEl = document.getElementById('composerAvatar');

        document.getElementById('composerName').textContent = displayName;
        avatarEl.innerHTML = composerProfile.avatar_url
            ? `<img src="${esc(API.assetUrl(composerProfile.avatar_url))}" alt="" data-avatar-fallback="${initial}">`
            : initial;
        attachAvatarFallbacks(avatarEl);
    }

function init() {
        document.getElementById('feedMore').addEventListener('click', () => load(false));
        document.getElementById('feedRetryBtn').addEventListener('click', () => load(true));

        window.addEventListener('languageChanged', () => {
            if (items.length) render();
            renderComposerIdentity();
        });

feedDesktopMedia?.addEventListener('change', observeViews);

        initComposer();
        load(true);
    }

    return { init };
})();

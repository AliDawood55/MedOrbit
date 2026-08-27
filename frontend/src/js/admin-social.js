const AdminSocial = (() => {
    const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[char]));
    const localized = (arValue, enValue) => (
        typeof I18n !== 'undefined' && typeof I18n.localizedContent === 'function'
            ? I18n.localizedContent(arValue, enValue)
            : (arValue || enValue || '')
    );

    const pendingActions = new Set();

    const CONFIRM_TEXT = {
        approve: { post: 'Approve this post?', comment: 'Approve this comment?' },
        hide: { post: 'Hide this post?', comment: 'Hide this comment?' },
        reject: { post: 'Reject this post?', comment: 'Reject this comment?' },
    };

    function showAlert(message) {
        const el = document.getElementById('moderationAlert');
        el.className = 'alert alert-error';
        el.textContent = message;
    }

    function clearAlert() {
        const el = document.getElementById('moderationAlert');
        el.className = 'alert';
        el.textContent = '';
    }

    const actions = (type, id) => (
        `<div class="moderation-actions"><button class="btn btn-primary btn-sm" data-${type}="${escapeHtml(id)}" data-action="approve">Approve</button>` +
        `<button class="btn btn-secondary btn-sm" data-${type}="${escapeHtml(id)}" data-action="hide">Hide</button>` +
        `<button class="btn btn-secondary btn-sm" data-${type}="${escapeHtml(id)}" data-action="reject">Reject</button></div>`
    );

    function setItemDisabled(type, id, disabled) {
        document.querySelectorAll(`[data-${type}="${CSS.escape(String(id))}"]`).forEach((button) => {
            button.disabled = disabled;
        });
    }

    async function moderate(type, id, action) {
        const key = `${type}:${id}`;
        if (pendingActions.has(key)) return;
        if (!window.confirm(CONFIRM_TEXT[action][type])) return;

        pendingActions.add(key);
        setItemDisabled(type, id, true);
        try {
            if (type === 'post') {
                await API.social.moderatePost(id, action);
            } else {
                await API.social.moderateComment(id, action);
            }
            Toast.success('Moderation action applied');
            if (type === 'post') {
                await posts();
            } else {
                await comments();
            }
        } catch (error) {
            Toast.error(error.message || 'Moderation action failed');
            setItemDisabled(type, id, false);
        } finally {
            pendingActions.delete(key);
        }
    }

    function wireActions(type) {
        document.querySelectorAll(`[data-${type}]`).forEach((button) => {
            button.onclick = () => moderate(type, button.dataset[type], button.dataset.action);
        });
    }

    async function posts() {
        const filter = document.getElementById('postModerationFilter').value;
        try {
            const response = await API.social.moderationPosts(filter ? { moderation_status: filter } : {});
            document.getElementById('moderationPosts').innerHTML = (response.data || []).map((post) => (
                `<article class="moderation-item"><strong>${escapeHtml(localized(post.title_ar, post.title_en) || 'Untitled')}</strong>` +
                `<p>${escapeHtml(post.body)}</p><small>${escapeHtml(post.status)} · ${escapeHtml(post.moderation_status)}</small>${actions('post', post.id)}</article>`
            )).join('') || '<p>No posts.</p>';
            wireActions('post');
        } catch (error) {
            showAlert(error.message || 'Unable to load posts');
        }
    }

    async function comments() {
        const filter = document.getElementById('commentModerationFilter').value;
        try {
            const response = await API.social.moderationComments(filter ? { moderation_status: filter } : {});
            document.getElementById('moderationComments').innerHTML = (response.data || []).map((comment) => (
                `<article class="moderation-item"><p>${escapeHtml(comment.body)}</p><small>${escapeHtml(comment.moderation_status)}</small>` +
                `${actions('comment', comment.id)}</article>`
            )).join('') || '<p>No comments.</p>';
            wireActions('comment');
        } catch (error) {
            showAlert(error.message || 'Unable to load comments');
        }
    }

    async function init() {
        if (!API.requireAuth()) return;

        const state = await AuthGate.verifySession();
        if (state !== 'valid') return;

        const currentUser = AuthGate.getVerifiedUser();
        if (!currentUser || !['admin', 'super_admin'].includes(currentUser.role)) {
            location.href = 'dashboard.html';
            return;
        }
        try {
            document.getElementById('postModerationFilter').onchange = posts;
            document.getElementById('commentModerationFilter').onchange = comments;
            window.addEventListener('languageChanged', posts);

            clearAlert();
            await Promise.all([posts(), comments()]);
        } catch (error) {
            showAlert(error.message || 'Unable to load moderation queue');
        }
    }

    return { init };
})();

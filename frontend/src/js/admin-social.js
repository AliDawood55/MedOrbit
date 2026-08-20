const AdminSocial = (() => {
    const escapeHtml = (value) => String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
    }[char]));
    const localized = (arValue, enValue) => (
        typeof I18n !== 'undefined' && typeof I18n.localizedContent === 'function'
            ? I18n.localizedContent(arValue, enValue)
            : (arValue || enValue || '')
    );

    function guard() {
        const user = API.getUser();
        if (!API.isAuthenticated() || !['admin', 'super_admin'].includes(user?.role)) {
            window.location.href = 'dashboard.html';
            return false;
        }
        return true;
    }

    const actions = (type, id) => (
        `<div class="moderation-actions"><button class="btn btn-primary btn-sm" data-${type}="${escapeHtml(id)}" data-action="approve">Approve</button>` +
        `<button class="btn btn-secondary btn-sm" data-${type}="${escapeHtml(id)}" data-action="hide">Hide</button>` +
        `<button class="btn btn-secondary btn-sm" data-${type}="${escapeHtml(id)}" data-action="reject">Reject</button></div>`
    );

    async function posts() {
        const filter = document.getElementById('postModerationFilter').value;
        const response = await API.social.moderationPosts(filter ? { moderation_status: filter } : {});
        document.getElementById('moderationPosts').innerHTML = (response.data || []).map((post) => (
            `<article class="moderation-item"><strong>${escapeHtml(localized(post.title_ar, post.title_en) || 'Untitled')}</strong>` +
            `<p>${escapeHtml(post.body)}</p><small>${escapeHtml(post.status)} · ${escapeHtml(post.moderation_status)}</small>${actions('post', post.id)}</article>`
        )).join('') || '<p>No posts.</p>';
        document.querySelectorAll('[data-post]').forEach((button) => {
            button.onclick = async () => {
                await API.social.moderatePost(button.dataset.post, button.dataset.action);
                await posts();
            };
        });
    }

    async function comments() {
        const filter = document.getElementById('commentModerationFilter').value;
        const response = await API.social.moderationComments(filter ? { moderation_status: filter } : {});
        document.getElementById('moderationComments').innerHTML = (response.data || []).map((comment) => (
            `<article class="moderation-item"><p>${escapeHtml(comment.body)}</p><small>${escapeHtml(comment.moderation_status)}</small>` +
            `${actions('comment', comment.id)}</article>`
        )).join('') || '<p>No comments.</p>';
        document.querySelectorAll('[data-comment]').forEach((button) => {
            button.onclick = async () => {
                await API.social.moderateComment(button.dataset.comment, button.dataset.action);
                await comments();
            };
        });
    }

    async function init() {
        if (!guard()) return;
        document.getElementById('postModerationFilter').onchange = posts;
        document.getElementById('commentModerationFilter').onchange = comments;
        window.addEventListener('languageChanged', posts);
        try {
            await Promise.all([posts(), comments()]);
        } catch (error) {
            document.getElementById('moderationAlert').className = 'alert alert-error';
            document.getElementById('moderationAlert').textContent = error.message || 'Unable to load moderation queue';
        }
    }

    return { init };
})();

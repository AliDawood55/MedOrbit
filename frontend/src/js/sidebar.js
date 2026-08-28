const Sidebar = (() => {

    let conversations = [];
    let activeId = null;
    let searchDebounceTimer = null;
    let activeController = null;

    function isArLang() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

    function isEnabled() {
        return typeof API !== 'undefined' && API.isAuthenticated();
    }

    function panel() {
        return document.getElementById('sidebarPanel');
    }

    function escapeHtml(s) {
        if (s == null) return '';
        return String(s)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function formatRelativeTime(dateStr) {
        if (!dateStr) return '';
        const diffMin = Math.round((Date.now() - new Date(dateStr).getTime()) / 60000);
        const ar = isArLang();

        if (diffMin < 1) return ar ? 'الآن' : 'now';
        if (diffMin < 60) return ar ? `منذ ${diffMin} د` : `${diffMin}m ago`;
        const diffH = Math.round(diffMin / 60);
        if (diffH < 24) return ar ? `منذ ${diffH} س` : `${diffH}h ago`;
        const diffD = Math.round(diffH / 24);
        return ar ? `منذ ${diffD} يوم` : `${diffD}d ago`;
    }

function updateVisibility() {
        const app = document.getElementById('app');
        const p = panel();
        const toggleBtn = document.getElementById('sidebarToggleBtn');
        if (!app || !p) return;

        if (isEnabled()) {
            app.classList.add('sidebar-enabled');
            p.classList.remove('hidden');
            if (toggleBtn) toggleBtn.style.display = '';
            refresh();
        } else {
            app.classList.remove('sidebar-enabled');
            p.classList.add('hidden');
            p.classList.remove('sidebar-open');
            if (toggleBtn) toggleBtn.style.display = 'none';
            conversations = [];
        }
    }

async function refresh() {
        if (!isEnabled()) return;

        if (activeController) activeController.abort();
        activeController = API.makeCancellable();

        try {
            const res = await API.conversations.list({ limit: 50 }, { signal: activeController.signal });
            conversations = res?.data?.conversations || [];
            render();
        } catch (err) {
            if (err.name === 'AbortError') return;
            console.error('Sidebar: failed to load conversations', err);
        }
    }

    async function search(query) {
        if (!isEnabled()) return;
        if (!query || query.trim().length < 2) {
            return refresh();
        }

        if (activeController) activeController.abort();
        activeController = API.makeCancellable();

        try {
            const res = await API.conversations.search(query.trim(), { signal: activeController.signal });
            conversations = res?.data?.conversations || [];
            render();
        } catch (err) {
            if (err.name === 'AbortError') return;
            console.error('Sidebar: search failed', err);
        }
    }

function render() {
        const list = document.getElementById('sidebarList');
        if (!list) return;

        if (conversations.length === 0) {
            list.innerHTML =
                '<div class="sidebar-empty">' +
                    '<i class="fas fa-comments"></i>' +
                    '<p>' + (isArLang() ? 'لا توجد محادثات بعد' : 'No conversations yet') + '</p>' +
                '</div>';
            return;
        }

        list.innerHTML = '';
        conversations.forEach((c) => {
            const item = document.createElement('div');
            item.className = 'sidebar-item' + (c.id === activeId ? ' active' : '');
            item.dataset.id = c.id;

            const title = c.title || (isArLang() ? 'محادثة جديدة' : 'New conversation');
            const meta = formatRelativeTime(c.last_message_at || c.started_at) +
                (c.message_count != null ? ' · ' + c.message_count : '');

            item.innerHTML =
                '<div class="sidebar-item-main">' +
                    '<div class="sidebar-item-title">' + escapeHtml(title) + '</div>' +
                    '<div class="sidebar-item-meta">' + escapeHtml(meta) + '</div>' +
                '</div>' +
                '<div class="sidebar-item-actions">' +
                    '<button type="button" class="sidebar-item-btn" data-action="rename" title="' + (isArLang() ? 'إعادة تسمية' : 'Rename') + '"><i class="fas fa-pen"></i></button>' +
                    '<button type="button" class="sidebar-item-btn" data-action="delete" title="' + (isArLang() ? 'حذف' : 'Delete') + '"><i class="fas fa-trash"></i></button>' +
                '</div>';

            item.querySelector('.sidebar-item-main')?.addEventListener('click', () => openConversation(c.id));
            item.querySelector('[data-action="rename"]')?.addEventListener('click', (e) => {
                e.stopPropagation();
                startRename(item, c);
            });
            item.querySelector('[data-action="delete"]')?.addEventListener('click', (e) => {
                e.stopPropagation();
                removeConversation(c.id);
            });

            list.appendChild(item);
        });
    }

function openConversation(id) {
        if (typeof Chat !== 'undefined' && Chat.loadConversation) {
            Chat.loadConversation(id);
        }
        closeMobileDrawer();
    }

    function startRename(item, conversation) {
        const titleEl = item.querySelector('.sidebar-item-title');
        if (!titleEl) return;

        const current = conversation.title || '';
        const input = document.createElement('input');
        input.type = 'text';
        input.className = 'sidebar-rename-input';
        input.value = current;

        titleEl.replaceWith(input);
        input.focus();
        input.select();

        let committed = false;
        const commit = async () => {
            if (committed) return;
            committed = true;

            const newTitle = input.value.trim();
            if (newTitle && newTitle !== current) {

conversation.title = newTitle;
                render();
                try {
                    await API.conversations.rename(conversation.id, newTitle);
                } catch (err) {
                    console.error('Sidebar: rename failed', err);
                    conversation.title = current;
                    render();
                    if (typeof Toast !== 'undefined') {
                        Toast.error(isArLang() ? 'تعذر إعادة تسمية المحادثة' : 'Could not rename the conversation');
                    }
                }
            } else {
                render();
            }
        };

        input.addEventListener('blur', commit);
        input.addEventListener('keydown', (e) => {
            if (e.key === 'Enter') { e.preventDefault(); input.blur(); }
            if (e.key === 'Escape') { e.preventDefault(); committed = true; render(); }
        });
    }

    async function removeConversation(id) {
        const ar = isArLang();
        if (!window.confirm(ar ? 'حذف هذه المحادثة نهائياً؟' : 'Delete this conversation permanently?')) return;

        try {
            await API.conversations.remove(id);
            conversations = conversations.filter((c) => c.id !== id);
            render();

            if (id === activeId && typeof Chat !== 'undefined' && Chat.clearChat) {
                Chat.clearChat();
            }
        } catch (err) {
            console.error('Sidebar: delete failed', err);
            if (typeof Toast !== 'undefined') {
                Toast.error(ar ? 'تعذر حذف المحادثة' : 'Could not delete the conversation');
            }
        }
    }

    function setActiveConversation(id) {
        activeId = id || null;
        document.querySelectorAll('.sidebar-item').forEach((el) => {
            el.classList.toggle('active', el.dataset.id === activeId);
        });

if (activeId && !conversations.some((c) => c.id === activeId)) {
            refresh();
        }
    }

function toggleCollapse() {
        document.getElementById('app')?.classList.toggle('sidebar-collapsed');
    }

    function openMobileDrawer() {
        panel()?.classList.add('sidebar-open');
        document.getElementById('sidebarBackdrop')?.classList.add('visible');
        if (typeof Dom !== 'undefined') Dom.lockScroll();
    }

    function closeMobileDrawer() {
        const wasOpen = panel()?.classList.contains('sidebar-open');
        panel()?.classList.remove('sidebar-open');
        document.getElementById('sidebarBackdrop')?.classList.remove('visible');
        if (wasOpen && typeof Dom !== 'undefined') Dom.unlockScroll();
    }

    function toggleSidebar() {
        if (window.matchMedia('(max-width: 768px)').matches) {
            if (panel()?.classList.contains('sidebar-open')) {
                closeMobileDrawer();
            } else {
                openMobileDrawer();
            }
        } else {
            toggleCollapse();
        }
    }

function init() {
        updateVisibility();

        document.getElementById('sidebarNewBtn')?.addEventListener('click', () => {
            if (typeof Chat !== 'undefined' && Chat.clearChat) Chat.clearChat();
            closeMobileDrawer();
        });

        document.getElementById('sidebarToggleBtn')?.addEventListener('click', toggleSidebar);
        document.getElementById('sidebarBackdrop')?.addEventListener('click', closeMobileDrawer);

        const searchInput = document.getElementById('sidebarSearch');
        searchInput?.addEventListener('input', () => {
            clearTimeout(searchDebounceTimer);
            searchDebounceTimer = setTimeout(() => search(searchInput.value), 350);
        });

        window.addEventListener('auth:changed', updateVisibility);
        window.addEventListener('chat:conversationChanged', (e) => {
            setActiveConversation(e.detail?.conversationId || null);
        });
    }

    return { init, refresh, setActiveConversation };

})();

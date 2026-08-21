const AdminUsers = (() => {
    const byId = (id) => document.getElementById(id);
    const isAr = () => I18n.getLang() === 'ar';
    const t = (key) => I18n.t(key);
    const format = (key, params) => Object.entries(params).reduce(
        (str, [name, value]) => str.replace(`{${name}}`, value), t(key)
    );

    let currentUser = null;
    let users = [];
    let requestSeq = 0;
    let searchDebounce = null;
    const pendingIds = new Set();

    function escapeHtml(value) {
        return String(value ?? '').replace(/[&<>"']/g, (char) => ({
            '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
        }[char]));
    }

    function displayName(user) {
        const full = [user.first_name_en, user.last_name_en].filter(Boolean).join(' ').trim();
        return full || user.email;
    }

    const ROLE_KEYS = {
        patient: 'adminUsers.rolePatient',
        doctor: 'adminUsers.roleDoctor',
        admin: 'adminUsers.roleAdmin',
        super_admin: 'adminUsers.roleSuperAdmin'
    };

    function roleLabel(role) {
        const key = ROLE_KEYS[role];
        return key ? t(key) : role;
    }

    function localize() {
        byId('adminUsersTitle').textContent = t('adminUsers.title');
        byId('adminUsersSubtitle').textContent = t('adminUsers.subtitle');
        byId('userSearchLabel').textContent = isAr() ? 'ابحث عن المستخدمين' : 'Search users';
        byId('userSearchInput').placeholder = t('adminUsers.searchPlaceholder');
        byId('userRoleFilterLabel').textContent = isAr() ? 'الدور' : 'Role';
        byId('userStatusFilterLabel').textContent = isAr() ? 'الحالة' : 'Status';
        byId('roleOptAll').textContent = t('adminUsers.roleAll');
        byId('roleOptPatient').textContent = t('adminUsers.rolePatient');
        byId('roleOptDoctor').textContent = t('adminUsers.roleDoctor');
        byId('roleOptAdmin').textContent = t('adminUsers.roleAdmin');
        byId('roleOptSuperAdmin').textContent = t('adminUsers.roleSuperAdmin');
        byId('statusOptAll').textContent = t('adminUsers.statusAll');
        byId('statusOptActive').textContent = t('adminUsers.statusActive');
        byId('statusOptInactive').textContent = t('adminUsers.statusInactive');
        render();
    }

    function feedback(message, type = 'error') {
        const node = byId('usersFeedback');
        if (!message) {
            node.classList.add('hidden');
            node.textContent = '';
            return;
        }
        node.textContent = message;
        node.className = `page-feedback ${type}`;
    }

    function mutationEligibility(user) {
        if (currentUser && user.id === currentUser.id) return { action: null, protectedReason: 'adminUsers.currentAccount' };
        if (user.role === 'super_admin') return { action: null, protectedReason: 'adminUsers.protectedAccount' };
        if (user.role === 'admin' && currentUser?.role !== 'super_admin') return { action: null, protectedReason: 'adminUsers.protectedAccount' };
        return { action: user.is_active ? 'deactivate' : 'reactivate', protectedReason: null };
    }

    function renderUserCard(user) {
        const item = document.createElement('div');
        item.className = 'application-history-item';

        const detail = document.createElement('div');
        const name = document.createElement('strong');
        name.textContent = displayName(user);
        const email = document.createElement('div');
        email.className = 'text-muted';
        email.textContent = user.email;
        const meta = document.createElement('div');
        meta.className = 'text-muted';
        meta.textContent = roleLabel(user.role) + ' · ' + (user.email_verified ? t('adminUsers.verified') : t('adminUsers.unverified'));
        detail.append(name, email, meta);

        const actions = document.createElement('div');
        actions.className = 'application-actions';

        const statusBadge = document.createElement('span');
        statusBadge.className = `badge ${user.is_active ? 'badge-success' : 'badge-danger'}`;
        statusBadge.textContent = user.is_active ? t('adminUsers.statusActive') : t('adminUsers.statusInactive');
        actions.appendChild(statusBadge);

        const { action, protectedReason } = mutationEligibility(user);
        if (protectedReason) {
            const tag = document.createElement('span');
            tag.className = 'badge badge-info';
            tag.textContent = t(protectedReason);
            actions.appendChild(tag);
        } else if (action) {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = `btn btn-sm ${action === 'deactivate' ? 'btn-secondary' : 'btn-primary'}`;
            button.textContent = t(action === 'deactivate' ? 'adminUsers.deactivate' : 'adminUsers.reactivate');
            button.disabled = pendingIds.has(user.id);
            button.addEventListener('click', () => mutate(user, action));
            actions.appendChild(button);
        }

        item.append(detail, actions);
        return item;
    }

    function render() {
        const root = byId('usersList');
        root.textContent = '';
        if (!users.length) {
            const empty = document.createElement('div');
            empty.className = 'profile-compact-empty';
            empty.textContent = t('adminUsers.noUsers');
            root.appendChild(empty);
            return;
        }
        users.forEach((user) => root.appendChild(renderUserCard(user)));
    }

    function currentQuery() {
        const query = {};
        const search = byId('userSearchInput').value.trim();
        const role = byId('userRoleFilter').value;
        const active = byId('userStatusFilter').value;
        if (search) query.search = search;
        if (role) query.role = role;
        if (active) query.active = active;
        return query;
    }

    async function load() {
        const seq = ++requestSeq;
        try {
            const response = await API.adminUsers.list(currentQuery());
            if (seq !== requestSeq) return;
            users = Array.isArray(response?.data) ? response.data : [];
            feedback(null);
            render();
        } catch (err) {
            if (seq !== requestSeq) return;
            feedback(err.message || t('adminUsers.loadError'));
        }
    }

    async function mutate(user, action) {
        const name = displayName(user);
        const confirmed = window.confirm(format(
            action === 'deactivate' ? 'adminUsers.confirmDeactivate' : 'adminUsers.confirmReactivate',
            { name }
        ));
        if (!confirmed || pendingIds.has(user.id)) return;

        pendingIds.add(user.id);
        render();
        try {
            const response = action === 'deactivate'
                ? await API.adminUsers.deactivate(user.id)
                : await API.adminUsers.reactivate(user.id);
            const updated = response?.data;
            const index = users.findIndex((entry) => entry.id === user.id);
            if (updated && index !== -1) users[index] = { ...users[index], ...updated };
            Toast.success(t(action === 'deactivate' ? 'adminUsers.deactivateSuccess' : 'adminUsers.reactivateSuccess'));
        } catch (err) {
            Toast.error(err.message || t('adminUsers.operationFailed'));
        } finally {
            pendingIds.delete(user.id);
            render();
        }
    }

    function debouncedSearch() {
        clearTimeout(searchDebounce);
        searchDebounce = setTimeout(load, 400);
    }

    async function init() {
        if (!API.requireAuth()) return;
        try {
            const me = await API.users.me();
            currentUser = me?.data || null;
            if (!currentUser || !['admin', 'super_admin'].includes(currentUser.role)) {
                location.href = 'dashboard.html';
                return;
            }
            localize();
            window.addEventListener('languageChanged', localize);
            byId('userSearchInput').addEventListener('input', debouncedSearch);
            byId('userRoleFilter').addEventListener('change', load);
            byId('userStatusFilter').addEventListener('change', load);
            byId('refreshUsers').addEventListener('click', () => load());
            await load();
        } catch (err) {
            feedback(err.message || t('adminUsers.loadError'));
        }
    }

    return { init };
})();

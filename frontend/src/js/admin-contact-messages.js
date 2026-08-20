const AdminContactInbox = (() => {
    const PAGE_SIZE = 30;
    const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const byId = (id) => document.getElementById(id);
    const isAr = () => I18n.getLang() === 'ar';
    let items = [];
    let selectedId = null;
    let selectedItem = null;
    let offset = 0;
    let hasNext = false;

    function copy(ar, en) { return isAr() ? ar : en; }

    function localize() {
        byId('adminContactTitle').textContent = copy('رسائل التواصل', 'Contact Messages');
        byId('adminContactSubtitle').textContent = copy('راجع طلبات الدعم الجديدة وحافظ على تحديث حالتها.', 'Review new support requests and keep their status current.');
        const hint = byId('selectContactHint');
        if (hint) hint.textContent = copy('اختر رسالة لمراجعتها.', 'Select a message to review it.');
        renderList();
        renderPager();
        if (selectedItem) renderDetail(selectedItem);
    }

    function statusLabel(status) {
        const labels = isAr()
            ? { new: 'جديدة', read: 'مقروءة', resolved: 'محلولة' }
            : { new: 'New', read: 'Read', resolved: 'Resolved' };
        return labels[status] || status;
    }

    function renderList() {
        const root = byId('adminContactList');
        root.textContent = '';
        if (!items.length) {
            const state = document.createElement('div');
            state.className = 'profile-compact-empty';
            state.textContent = copy('لا توجد رسائل بهذه الحالة.', 'No messages in this state.');
            root.appendChild(state);
            return;
        }
        items.forEach((item) => {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = `contact-list-item ${item.status}${item.id === selectedId ? ' active' : ''}`;
            const dot = document.createElement('span');
            dot.className = 'status-dot';
            const text = document.createElement('span');
            text.className = 'contact-list-copy';
            const subject = document.createElement('strong');
            subject.textContent = item.subject;
            const sender = document.createElement('span');
            sender.textContent = `${item.sender_name} · ${item.sender_email}`;
            const meta = document.createElement('small');
            meta.textContent = `${statusLabel(item.status)} · ${new Date(item.created_at).toLocaleString(isAr() ? 'ar' : 'en-US')}`;
            text.append(subject, sender, meta);
            button.append(dot, text);
            button.addEventListener('click', () => open(item.id));
            root.appendChild(button);
        });
    }

    function renderPager() {
        const first = items.length ? offset + 1 : 0;
        byId('contactPageStatus').textContent = copy(`الرسائل ${first}–${offset + items.length}`, `Messages ${first}–${offset + items.length}`);
        byId('contactPrevPage').disabled = offset === 0;
        byId('contactNextPage').disabled = !hasNext;
    }

    async function load(preferredId = null) {
        const status = byId('contactStatusFilter').value;
        const response = await API.contact.adminList({ ...(status ? { status } : {}), limit: PAGE_SIZE + 1, offset });
        const rows = response?.data?.items || [];
        hasNext = rows.length > PAGE_SIZE;
        items = rows.slice(0, PAGE_SIZE);
        renderList();
        renderPager();
        if (preferredId) await open(preferredId);
        else if (selectedId && items.some((item) => item.id === selectedId)) await open(selectedId, false);
    }

    function renderDetail(item) {
        const root = byId('adminContactDetail');
        root.textContent = '';
        const header = document.createElement('div');
        header.className = 'contact-detail-header';
        const heading = document.createElement('h2');
        heading.textContent = item.subject;
        const badge = document.createElement('span');
        badge.className = `status-badge ${item.status}`;
        badge.textContent = statusLabel(item.status);
        header.append(heading, badge);
        const meta = document.createElement('div');
        meta.className = 'contact-detail-meta';
        [item.sender_name, item.sender_email, new Date(item.created_at).toLocaleString(isAr() ? 'ar' : 'en-US')].forEach((value) => {
            const line = document.createElement('span');
            line.textContent = value;
            meta.appendChild(line);
        });
        const body = document.createElement('div');
        body.className = 'contact-message-body';
        body.textContent = item.message;
        const actions = document.createElement('div');
        actions.className = 'contact-detail-actions';
        if (item.status !== 'resolved') {
            const resolve = document.createElement('button');
            resolve.type = 'button';
            resolve.className = 'btn btn-primary';
            resolve.textContent = copy('وضع علامة كمحلولة', 'Mark resolved');
            resolve.addEventListener('click', async () => {
                resolve.disabled = true;
                try {
                    await API.contact.resolve(item.id);
                    await load(item.id);
                } catch (err) {
                    resolve.disabled = false;
                    Toast.error(err.message || copy('تعذر تحديث الرسالة.', 'Unable to update the message.'));
                }
            });
            actions.appendChild(resolve);
        }
        root.append(header, meta, body, actions);
    }

    async function open(id, mark = true) {
        selectedId = id;
        renderList();
        const response = await API.contact.adminGet(id);
        const item = response.data;
        if (mark && item.status === 'new') {
            await API.contact.markRead(id);
            item.status = 'read';
            const local = items.find((entry) => entry.id === id);
            if (local) local.status = 'read';
            window.dispatchEvent(new CustomEvent('notifications:changed'));
            renderList();
        }
        selectedItem = item;
        renderDetail(item);
    }

    async function init() {
        if (!API.requireAuth()) return;
        try {
            const me = await API.users.me();
            if (!['admin', 'super_admin'].includes(me?.data?.role)) {
                location.href = 'dashboard.html';
                return;
            }
            localize();
            window.addEventListener('languageChanged', localize);
            byId('contactStatusFilter').addEventListener('change', () => { offset = 0; load(); });
            byId('refreshContactList').addEventListener('click', () => load());
            byId('contactPrevPage').addEventListener('click', () => { offset = Math.max(0, offset - PAGE_SIZE); load(); });
            byId('contactNextPage').addEventListener('click', () => { if (hasNext) { offset += PAGE_SIZE; load(); } });
            const preferred = new URLSearchParams(location.search).get('message');
            await load(UUID_PATTERN.test(preferred || '') ? preferred : null);
        } catch (err) {
            byId('adminContactList').textContent = err.message || copy('تعذر تحميل رسائل التواصل.', 'Unable to load contact messages.');
        }
    }

    return { init };
})();

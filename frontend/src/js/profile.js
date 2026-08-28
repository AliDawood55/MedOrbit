const Profile = (() => {

    let profile = null;

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

    function showAlert(boxId, message, type = 'error') {
        const box = document.getElementById(boxId);
        if (!box) return;
        box.className = 'alert ' + type;
        box.textContent = message;
    }

    function clearAlert(boxId) {
        const box = document.getElementById(boxId);
        if (box) box.className = 'alert';
    }

    function setLoading(btnId, loading) {
        const btn = document.getElementById(btnId);
        if (!btn) return;
        btn.classList.toggle('loading', loading);
        btn.disabled = loading;
    }

async function load() {
        document.getElementById('loadingState')?.classList.remove('hidden');
        document.getElementById('errorState')?.classList.add('hidden');
        document.getElementById('profileContent')?.classList.add('hidden');

        const state = await AuthGate.verifySession();
        if (state !== 'valid') return;

        try {
            profile = AuthGate.getVerifiedUser();
            render();
            document.getElementById('profileContent')?.classList.remove('hidden');
        } catch (err) {
            console.error('Profile: failed to load', err);
            document.getElementById('errorState')?.classList.remove('hidden');
        } finally {
            document.getElementById('loadingState')?.classList.add('hidden');
        }
    }

    function displayName() {
        if (!profile) return '';
        const name = isAr()
            ? [profile.first_name_ar, profile.last_name_ar].filter(Boolean).join(' ')
            : [profile.first_name_en, profile.last_name_en].filter(Boolean).join(' ');
        return name || profile.email;
    }

    function renderAvatar() {
        const el = document.getElementById('avatarDisplay');
        if (!el) return;
        if (profile.avatar_url) {
            el.innerHTML = '<img src="' + escapeHtml(API.assetUrl(profile.avatar_url)) + '" alt="">';
        } else {
            const initial = (displayName() || profile.email || '?').trim().charAt(0).toUpperCase();
            el.textContent = initial || '?';
        }
    }

    function render() {
        renderAvatar();

        const avatarEditBtn = document.getElementById('avatarEditBtn');
        if (avatarEditBtn) {
            avatarEditBtn.title = t('profile.changePhoto');
            avatarEditBtn.setAttribute('aria-label', t('profile.changePhoto'));
        }

        document.getElementById('profileName').textContent = displayName();
        document.getElementById('profileEmail').textContent = profile.email || '';

        const sinceLabel = t('profile.memberSince');
        if (profile.created_at) {
            const date = new Date(profile.created_at);
            const formatted = isNaN(date) ? '' : date.toLocaleDateString(isAr() ? 'ar-EG' : 'en-US', { year: 'numeric', month: 'long' });
            document.getElementById('profileSince').textContent = formatted ? sinceLabel + ' ' + formatted : '';
        }

        document.getElementById('firstNameAr').value = profile.first_name_ar || '';
        document.getElementById('lastNameAr').value = profile.last_name_ar || '';
        document.getElementById('firstNameEn').value = profile.first_name_en || '';
        document.getElementById('lastNameEn').value = profile.last_name_en || '';
        document.getElementById('phone').value = profile.phone || '';
        document.getElementById('address').value = profile.address || '';
        document.getElementById('city').value = profile.city || '';

        const genderInput = document.querySelector('input[name="gender"][value="' + (profile.gender || '') + '"]');
        if (genderInput) genderInput.checked = true;

        renderLangOptions();
    }

const MAX_AVATAR_BYTES = 2 * 1024 * 1024;

    async function handleAvatarSelect(file) {
        clearAlert('formAlert');
        if (!file) return;

        const ext = (file.name || '').split('.').pop().toLowerCase();
        if (!['jpg', 'jpeg', 'png'].includes(ext) || file.size > MAX_AVATAR_BYTES) {
            showAlert('formAlert', t('profile.avatarError'));
            return;
        }

        const editBtn = document.getElementById('avatarEditBtn');
        editBtn?.classList.add('uploading');

        try {
            const res = await API.users.uploadAvatar(file);
            profile.avatar_url = res?.data?.avatar || profile.avatar_url;
            renderAvatar();
        } catch (err) {
            console.error('Profile: avatar upload failed', err);
            showAlert('formAlert', t('profile.avatarError'));
        } finally {
            editBtn?.classList.remove('uploading');
        }
    }

async function submitProfile(e) {
        e.preventDefault();
        clearAlert('formAlert');

        const firstNameAr = document.getElementById('firstNameAr').value.trim();
        const lastNameAr = document.getElementById('lastNameAr').value.trim();
        const firstNameEn = document.getElementById('firstNameEn').value.trim();
        const lastNameEn = document.getElementById('lastNameEn').value.trim();

        if (!firstNameAr || !lastNameAr || !firstNameEn || !lastNameEn) {
            showAlert('formAlert', t('profile.errorRequired'));
            return;
        }

        const body = {
            firstNameAr,
            lastNameAr,
            firstNameEn,
            lastNameEn,
            phone: document.getElementById('phone').value.trim(),
            gender: document.querySelector('input[name="gender"]:checked')?.value || null,
            address: document.getElementById('address').value.trim(),
            city: document.getElementById('city').value.trim()
        };

        setLoading('saveProfileBtn', true);
        try {
            await API.users.updateMe(body);
            Object.assign(profile, {
                first_name_ar: firstNameAr, last_name_ar: lastNameAr,
                first_name_en: firstNameEn, last_name_en: lastNameEn,
                phone: body.phone, gender: body.gender, address: body.address, city: body.city
            });

const cachedUser = API.getUser();
            if (cachedUser) {
                API.setSession({ user: { ...cachedUser, name: displayName() } });
            }

            document.getElementById('profileName').textContent = displayName();
            showAlert('formAlert', t('profile.saveSuccess'), 'success');
        } catch (err) {
            console.error('Profile: save failed', err);
            showAlert('formAlert', t('profile.saveError'));
        } finally {
            setLoading('saveProfileBtn', false);
        }
    }

function renderLangOptions() {
        const lang = isAr() ? 'ar' : 'en';
        ['ar', 'en'].forEach(code => {
            const opt = document.getElementById(code === 'ar' ? 'langOptionAr' : 'langOptionEn');
            const input = opt?.querySelector('input');
            const check = opt?.querySelector('i');
            const active = code === lang;
            opt?.classList.toggle('active', active);
            if (input) input.checked = active;
            if (check) check.style.display = active ? '' : 'none';
        });
    }

    async function selectLanguage(lang) {
        if (lang === (isAr() ? 'ar' : 'en')) return;

        I18n.setLang(lang);
        renderLangOptions();

        try {
            await API.users.updatePreferences({ language: lang });
        } catch (err) {
            console.error('Profile: failed to save language preference', err);

}
    }

function wirePasswordStrength() {
        const pwInput = document.getElementById('newPassword');
        const strengthEl = document.getElementById('pwStrength');
        if (!pwInput || !strengthEl) return;

        pwInput.addEventListener('input', () => {
            const v = pwInput.value;
            let score = 0;
            if (v.length >= 8) score++;
            if (/[A-Z]/.test(v)) score++;
            if (/[0-9]/.test(v)) score++;
            if (/[^A-Za-z0-9]/.test(v)) score++;

            const classes = ['', 'weak', 'medium', 'medium', 'strong'];
            strengthEl.querySelectorAll('.bar').forEach((bar, i) => {
                bar.className = 'bar' + (i < score ? ' ' + classes[score] : '');
            });
        });
    }

    function wirePasswordToggles() {
        document.querySelectorAll('.toggle-password').forEach((toggle) => {
            toggle.addEventListener('click', function () {
                const input = this.closest('.input-wrapper')?.querySelector('input');
                if (!input) return;
                if (input.type === 'password') {
                    input.type = 'text';
                    this.classList.replace('fa-eye', 'fa-eye-slash');
                } else {
                    input.type = 'password';
                    this.classList.replace('fa-eye-slash', 'fa-eye');
                }
            });
        });
    }

    async function submitPasswordChange(e) {
        e.preventDefault();
        clearAlert('passwordAlert');

        const currentPassword = document.getElementById('currentPassword').value;
        const newPassword = document.getElementById('newPassword').value;

        if (!currentPassword || !newPassword) {
            showAlert('passwordAlert', t('profile.errorRequired'));
            return;
        }

        setLoading('changePasswordBtn', true);
        try {
            await API.post('/auth/change-password', { currentPassword, newPassword });

showAlert('passwordAlert', t('profile.passwordChanged'), 'success');
            document.querySelectorAll('#passwordForm input, #passwordForm button').forEach(el => { el.disabled = true; });

            setTimeout(() => {
                API.clearSession();
                window.location.href = 'login.html';
            }, 2000);
        } catch (err) {
            console.error('Profile: password change failed', err);
            showAlert('passwordAlert', t('profile.saveError'));
        } finally {
            setLoading('changePasswordBtn', false);
        }
    }

function init() {
        if (!API.requireAuth()) return;

        document.getElementById('retryLoadBtn')?.addEventListener('click', load);
        document.getElementById('profileForm')?.addEventListener('submit', submitProfile);
        document.getElementById('passwordForm')?.addEventListener('submit', submitPasswordChange);

        document.getElementById('avatarEditBtn')?.addEventListener('click', () => {
            document.getElementById('avatarInput')?.click();
        });
        document.getElementById('avatarInput')?.addEventListener('change', (e) => {
            const file = e.target.files?.[0];
            if (file) handleAvatarSelect(file);
            e.target.value = '';
        });

        document.getElementById('langOptionAr')?.addEventListener('click', () => selectLanguage('ar'));
        document.getElementById('langOptionEn')?.addEventListener('click', () => selectLanguage('en'));

        wirePasswordToggles();
        wirePasswordStrength();

        window.addEventListener('languageChanged', () => {
            if (profile) render();
        });

        load();
    }

    return { init };

})();

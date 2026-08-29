(function () {

    function showAlert(message, type = 'error') {
        const box = document.getElementById('alertBox');
        const msg = document.getElementById('alertMsg');
        if (!box || !msg) return;
        box.className = 'alert ' + type;
        const icon = box.querySelector('i');
        if (icon) icon.className = type === 'error' ? 'fas fa-circle-exclamation' : 'fas fa-circle-check';
        msg.textContent = message;
    }

    function clearAlert() {
        const box = document.getElementById('alertBox');
        if (box) box.className = 'alert';
    }

    function setLoading(btnId, loading) {
        const btn = document.getElementById(btnId);
        if (!btn) return;
        btn.classList.toggle('loading', loading);
        btn.disabled = loading;
    }

    function isAr() {
        return (typeof I18n !== 'undefined' ? I18n.getLang() : (document.documentElement.lang || 'ar')) === 'ar';
    }

function authErrorMessage(err) {
        const ar = isAr();
        const map = {
            INVALID_CREDENTIALS: ar ? 'البريد الإلكتروني أو كلمة المرور غير صحيحة' : 'Incorrect email or password',
            EMAIL_NOT_VERIFIED: ar ? 'يرجى تفعيل بريدك الإلكتروني قبل تسجيل الدخول' : 'Please verify your email before logging in',
            INVALID_TOKEN: ar ? 'الرابط غير صالح أو منتهي الصلاحية' : 'This link is invalid or has expired',
            RATE_LIMITED: ar ? 'محاولات كثيرة جداً، حاول لاحقاً' : 'Too many attempts, please try again later',
            UNAUTHORIZED: ar ? 'بيانات الدخول غير صحيحة' : 'Invalid credentials'
        };
        return map[err?.code] || (ar ? 'تعذّر إكمال الطلب. حاول مرة أخرى.' : 'Could not complete the request. Please try again.');
    }

    function connectionErrorMessage() {
        return isAr()
            ? 'تعذّر الاتصال بالخدمة. تحقق من اتصالك ثم حاول مرة أخرى.'
            : 'Could not reach the service. Check your connection and try again.';
    }

    function alertForError(err) {
        showAlert(err?.status ? authErrorMessage(err) : connectionErrorMessage());
    }

function intendedDestination() {
        if (typeof AuthGate === 'undefined') return null;
        return AuthGate.readIntendedDestination();
    }

function authFlowUrl(page) {
        const next = intendedDestination();
        const params = new URLSearchParams();
        if (next) params.set('redirect', next);
        if (typeof AuthGate !== 'undefined' && AuthGate.isDoctorApplicationIntent()) {
            params.set('intent', 'doctor');
        }
        const query = params.toString();
        return query ? page + '?' + query : page;
    }

function verificationUrl(email) {
    const target = authFlowUrl('verify-email.html');
    return target + (target.includes('?') ? '&' : '?') +
        'email=' + encodeURIComponent(email || '');
}

function showVerificationAction(email) {
    const action = document.getElementById('verificationAction');
    const link = document.getElementById('verificationActionLink');

    if (link) {
        link.href = verificationUrl(email);
    }

    action?.classList.remove('hidden');
}

// ================= LOGIN =================
async function handleLogin(e) {
        e.preventDefault();
        clearAlert();

        const email = document.getElementById('email')?.value.trim();
        const password = document.getElementById('password')?.value;

        if (!email || !password) {
            showAlert(isAr() ? 'يرجى إدخال البريد الإلكتروني وكلمة المرور' : 'Please enter your email and password');
            return;
        }

        setLoading('loginBtn', true);
        try {
            const res = await API.post('/auth/login', { email, password }, { auth: false });
            API.setSession(res?.data || {});
            showAlert(isAr() ? 'تم تسجيل الدخول بنجاح!' : 'Logged in successfully!', 'success');

            const redirect = intendedDestination();
            const landing = typeof AuthGate !== 'undefined'
                ? AuthGate.defaultLandingPage(res?.data?.user)
                : 'dashboard.html';
            if (typeof AuthGate !== 'undefined') AuthGate.clearIntendedDestination();
            setTimeout(() => {
                window.location.href = redirect || landing;
            }, 500);
        } catch (err) {
            if (err?.code === 'EMAIL_NOT_VERIFIED') {
                showAlert(authErrorMessage(err));
                showVerificationAction(email);
            } else {
                alertForError(err);
            }
        } finally {
            setLoading('loginBtn', false);
        }
    }

async function handleRegister(e) {
        e.preventDefault();
        clearAlert();

        const firstNameAr = document.getElementById('firstNameAr')?.value.trim();
        const lastNameAr = document.getElementById('lastNameAr')?.value.trim();
        const firstNameEn = document.getElementById('firstNameEn')?.value.trim();
        const lastNameEn = document.getElementById('lastNameEn')?.value.trim();
        const email = document.getElementById('email')?.value.trim();
        const phone = document.getElementById('phone')?.value.trim();
        const gender = document.querySelector('input[name="gender"]:checked')?.value;
        const password = document.getElementById('password')?.value;

        if (!firstNameAr || !lastNameAr || !firstNameEn || !lastNameEn || !email || !password) {
            showAlert(isAr() ? 'يرجى ملء جميع الحقول المطلوبة' : 'Please fill in all required fields');
            return;
        }

        setLoading('registerBtn', true);
        try {
            await API.post('/auth/register', {
                email,
                password,
                role: 'patient',
                firstNameAr,
                lastNameAr,
                firstNameEn,
                lastNameEn,
                phone,
                gender
            }, { auth: false });

            showAlert(isAr()
                ? 'تم إنشاء الحساب بنجاح! يرجى التحقق من بريدك الإلكتروني ثم تسجيل الدخول.'
                : 'Account created! Please check your email to verify it, then log in.', 'success');

        // Keep the person in the verification flow instead of returning them
        // to login before their email has been activated.
        setTimeout(() => {
            window.location.href = verificationUrl(email);
        }, 900);
        } catch (err) {
            alertForError(err);
        } finally {
            setLoading('registerBtn', false);
        }
    }

async function handleForgot(e) {
        e.preventDefault();
        clearAlert();

        const email = document.getElementById('email')?.value.trim();
        if (!email) {
            showAlert(isAr() ? 'يرجى إدخال بريدك الإلكتروني' : 'Please enter your email');
            return;
        }

        setLoading('forgotBtn', true);
        try {
            await API.post('/auth/forgot-password', { email }, { auth: false });
            showAlert(isAr()
                ? 'إذا كان البريد مسجلاً، تم إرسال رابط إعادة التعيين إليه'
                : 'If that email is registered, a reset link has been sent', 'success');
        } catch (err) {
            alertForError(err);
        } finally {
            setLoading('forgotBtn', false);
        }
    }

function initResetPage() {
        const token = new URLSearchParams(window.location.search).get('token');
        if (token) return;

        showAlert(isAr()
            ? 'رابط إعادة التعيين غير صالح أو منتهي الصلاحية'
            : 'This reset link is invalid or has expired');

        const form = document.getElementById('resetForm');
        form?.querySelectorAll('input, button').forEach((el) => { el.disabled = true; });
    }

    async function handleReset(e) {
        e.preventDefault();
        clearAlert();

        const token = new URLSearchParams(window.location.search).get('token');
        const password = document.getElementById('password')?.value;

        if (!token) {
            showAlert(isAr() ? 'رابط إعادة التعيين غير صالح أو منتهي الصلاحية' : 'This reset link is invalid or has expired');
            return;
        }
        if (!password) {
            showAlert(isAr() ? 'يرجى إدخال كلمة المرور الجديدة' : 'Please enter your new password');
            return;
        }

        setLoading('resetBtn', true);
        try {
            await API.post('/auth/reset-password', { token, newPassword: password }, { auth: false });
            showAlert(isAr()
                ? 'تم تغيير كلمة المرور بنجاح! يمكنك تسجيل الدخول الآن.'
                : 'Password changed successfully! You can log in now.', 'success');
            setTimeout(() => { window.location.href = authFlowUrl('login.html'); }, 1800);
        } catch (err) {
            alertForError(err);
        } finally {
            setLoading('resetBtn', false);
        }
    }

function setVerifyState(state, text) {
        const statusEl = document.getElementById('verifyStatus');
        const iconEl = document.getElementById('verifyIcon');
        if (statusEl) statusEl.textContent = text;
        if (iconEl) {
            const iconByState = {
                loading: 'fa-circle-notch fa-spin',
                success: 'fa-circle-check',
                error: 'fa-circle-xmark',
                info: 'fa-envelope-circle-check'
            };
            iconEl.className = 'auth-status-icon ' + state + ' fas ' + (iconByState[state] || 'fa-circle-info');
        }
    }

    async function runVerify() {
        const resendSection = document.getElementById('resendSection');
        const token = new URLSearchParams(window.location.search).get('token');
        const email = new URLSearchParams(window.location.search).get('email')?.trim() || '';
        const resendEmail = document.getElementById('resendEmail');
        if (resendEmail && email) resendEmail.value = email;

        if (!token) {
            if (email) {
                setVerifyState('info', isAr()
                    ? 'تم إنشاء حسابك. تحقق من بريدك الإلكتروني ثم افتح رابط التفعيل.'
                    : 'Your account was created. Check your email and open the verification link.');
                resendSection?.classList.remove('hidden');
                return;
            }
            setVerifyState('error', isAr() ? 'لم يتم العثور على رمز التحقق' : 'No verification token found');
            resendSection?.classList.remove('hidden');
            return;
        }

        setVerifyState('loading', isAr() ? 'جارِ التحقق من بريدك الإلكتروني...' : 'Verifying your email...');

        try {
            await API.post('/auth/verify-email', { token }, { auth: false });
            setVerifyState('success', isAr() ? 'تم تفعيل بريدك الإلكتروني بنجاح!' : 'Your email has been verified!');
        } catch (err) {
            setVerifyState('error', err?.status ? authErrorMessage(err) : connectionErrorMessage());
            resendSection?.classList.remove('hidden');
        }
    }

    async function handleResend(e) {
        e.preventDefault();
        clearAlert();

        const email = document.getElementById('resendEmail')?.value.trim();
        if (!email) {
            showAlert(isAr() ? 'يرجى إدخال بريدك الإلكتروني' : 'Please enter your email');
            return;
        }

        setLoading('resendBtn', true);
        try {
            await API.post('/auth/resend-verification', { email }, { auth: false });
            showAlert(isAr()
                ? 'إذا كان البريد مسجلاً وغير مفعّل، تم إرسال رابط تحقق جديد'
                : 'If that email is registered and unverified, a new verification link has been sent', 'success');
        } catch (err) {
            alertForError(err);
        } finally {
            setLoading('resendBtn', false);
        }
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

function wirePasswordStrength() {
        const pwInput = document.getElementById('password');
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

document.addEventListener('DOMContentLoaded', () => {
        document.getElementById('loginForm')?.addEventListener('submit', handleLogin);
        document.getElementById('registerForm')?.addEventListener('submit', handleRegister);
        document.getElementById('forgotForm')?.addEventListener('submit', handleForgot);
        document.getElementById('resetForm')?.addEventListener('submit', handleReset);
        document.getElementById('resendForm')?.addEventListener('submit', handleResend);

        wirePasswordToggles();
        wirePasswordStrength();

        if (document.getElementById('resetForm')) initResetPage();
        if (document.getElementById('verifyStatus')) runVerify();
    });

})();

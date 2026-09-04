/**
 * MedOrbit v2 - Auth Pages Logic
 * Shared across login.html, register.html, forgot-password.html,
 * reset-password.html, and verify-email.html. Every request goes through
 * the shared API module (no direct fetch here) so session storage and
 * error shapes stay consistent everywhere.
 */
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

    function isClinicSignupIntent() {
        return typeof AuthGate !== 'undefined' && AuthGate.isClinicApplicationIntent();
    }

    // This is deliberately a front-end draft. The secure account is still
    // created through the existing patient-registration endpoint; the clinic
    // details are submitted only after sign-in on clinic-application.html.
    function configureClinicSignupForm() {
        const clinicIntent = isClinicSignupIntent();
        document.querySelectorAll('#signupSocialLinks .social-link-non-patient').forEach((element) => element.classList.toggle('hidden', !clinicIntent));
        if (!clinicIntent) return;
        // Clinic onboarding collects legal organisation details and completes
        // through email verification. Do not silently create a patient account
        // through the generic Google flow while this intent is active.
        document.querySelector('.oauth-block')?.classList.add('hidden');
        document.getElementById('personalNameArRow')?.classList.add('hidden');
        document.getElementById('personalNameEnRow')?.classList.add('hidden');
        document.getElementById('clinicSignupFields')?.classList.remove('hidden');
        document.getElementById('genderGroup')?.classList.add('hidden');
        document.getElementById('clinicExtraPhonesGroup')?.classList.remove('hidden');
        ['firstNameAr', 'lastNameAr', 'firstNameEn', 'lastNameEn'].forEach((id) => document.getElementById(id)?.removeAttribute('required'));
        ['clinicSignupName', 'clinicSignupAddress'].forEach((id) => document.getElementById(id)?.setAttribute('required', 'required'));
        document.getElementById('addClinicPhone')?.addEventListener('click', addClinicPhoneField);
    }

    function addClinicPhoneField() {
        const container = document.getElementById('clinicExtraPhones');
        if (!container) return;
        const row = document.createElement('div');
        row.className = 'input-wrapper';
        row.style.marginBottom = '8px';
        const removeLabel = isAr() ? 'إزالة الرقم' : 'Remove phone number';
        row.innerHTML = `<i class="fas fa-phone"></i><input type="tel" class="clinic-extra-phone" dir="ltr" placeholder="+970-59-1234567"><button type="button" class="icon-btn" aria-label="${removeLabel}"><i class="fas fa-xmark"></i></button>`;
        row.querySelector('button')?.addEventListener('click', () => row.remove());
        container.appendChild(row);
    }

    /**
     * Map known backend error codes to friendly bilingual messages.
     * Unknown server responses use a generic message so implementation details
     * never reach the account screens.
     */
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

    /**
     * The destination the visitor was originally trying to reach, validated by
     * the one shared sanitizer in auth-gate.js. Returns null for anything that
     * is not a real in-app page, so a crafted ?redirect= can never turn a
     * successful login into an off-site redirect.
     */
    function intendedDestination() {
        if (typeof AuthGate === 'undefined') return null;
        return AuthGate.readIntendedDestination();
    }

    /** Carries the intended destination across an auth-flow page hop. */
    function authFlowUrl(page) {
        const next = intendedDestination();
        const params = new URLSearchParams();
        if (next) params.set('redirect', next);
        if (typeof AuthGate !== 'undefined' && AuthGate.isDoctorApplicationIntent()) params.set('intent', 'doctor');
        if (typeof AuthGate !== 'undefined' && AuthGate.isClinicApplicationIntent()) params.set('intent', 'clinic');
        const query = params.toString();
        return query ? page + '?' + query : page;
    }

    function verificationUrl(email) {
        const target = authFlowUrl('verify-email.html');
        return target + (target.includes('?') ? '&' : '?') + 'email=' + encodeURIComponent(email || '');
    }

    function showVerificationAction(email) {
        const action = document.getElementById('verificationAction');
        const link = document.getElementById('verificationActionLink');
        if (link) link.href = verificationUrl(email);
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

    // ================= REGISTER =================
    function optionalSocialLinks(prefix, patientOnly = false) {
        const allFields = {
            website: `${prefix}Website`, instagram: `${prefix}Instagram`,
            tiktok: `${prefix}TikTok`, linkedin: `${prefix}LinkedIn`,
            whatsapp: `${prefix}WhatsApp`, facebook: `${prefix}Facebook`
        };
        const fields = patientOnly ? { whatsapp: allFields.whatsapp } : allFields;
        const links = {};
        for (const [key, id] of Object.entries(fields)) {
            const value = document.getElementById(id)?.value.trim();
            if (!value) continue;
            if (key === 'whatsapp') {
                const number = value.replace(/[^\d]/g, '').replace(/^00/, '');
                if (number.length < 8 || number.length > 15) {
                    throw new Error(isAr() ? 'أدخل رقم واتساب صحيحاً مع رمز الدولة.' : 'Enter a valid WhatsApp number with its country code.');
                }
                links[key] = number;
                continue;
            }
            if (!/^https:\/\//i.test(value)) {
                throw new Error(isAr() ? 'استخدم رابط HTTPS صحيحاً لكل حساب عام.' : 'Use a valid HTTPS URL for every public link.');
            }
            links[key] = value;
        }
        return links;
    }

    async function handleRegister(e) {
        e.preventDefault();
        clearAlert();

        const clinicIntent = isClinicSignupIntent();
        const clinicName = document.getElementById('clinicSignupName')?.value.trim();
        const clinicAddress = document.getElementById('clinicSignupAddress')?.value.trim();
        // Registration collects information in the visitor's selected language.
        // The clinic-application workflow keeps the canonical bilingual fields
        // for directory data, so seed both with this initial account value.
        const clinicNameAr = clinicIntent ? clinicName : null;
        const clinicNameEn = clinicIntent ? clinicName : null;
        const clinicAddressAr = clinicIntent ? clinicAddress : null;
        const clinicAddressEn = clinicIntent ? clinicAddress : null;
        const firstNameAr = clinicIntent ? clinicNameAr : document.getElementById('firstNameAr')?.value.trim();
        const lastNameAr = clinicIntent ? 'Clinic' : document.getElementById('lastNameAr')?.value.trim();
        const firstNameEn = clinicIntent ? clinicNameEn : document.getElementById('firstNameEn')?.value.trim();
        const lastNameEn = clinicIntent ? 'Clinic' : document.getElementById('lastNameEn')?.value.trim();
        const email = document.getElementById('email')?.value.trim();
        const phone = document.getElementById('phone')?.value.trim();
        const extraPhones = clinicIntent
            ? Array.from(document.querySelectorAll('.clinic-extra-phone')).map((input) => input.value.trim()).filter(Boolean)
            : [];
        const gender = document.querySelector('input[name="gender"]:checked')?.value;
        const password = document.getElementById('password')?.value;
        let socialLinks;

        try {
            socialLinks = optionalSocialLinks('signup', !clinicIntent);
        } catch (err) {
            showAlert(err.message);
            return;
        }
        const registrationSocialLinks = clinicIntent && socialLinks.whatsapp
            ? { whatsapp: socialLinks.whatsapp }
            : (clinicIntent ? {} : socialLinks);

        if (!firstNameAr || !lastNameAr || !firstNameEn || !lastNameEn || !email || !password || (clinicIntent && !clinicAddress)) {
            showAlert(isAr() ? 'يرجى ملء جميع الحقول المطلوبة' : 'Please fill in all required fields');
            return;
        }

        setLoading('registerBtn', true);
        try {
            if (clinicIntent) {
                sessionStorage.setItem('medorbit_clinic_application_draft', JSON.stringify({
                    name_ar: clinicNameAr, name_en: clinicNameEn,
                    address_ar: clinicAddressAr, address_en: clinicAddressEn,
                    phone, extra_phones: extraPhones, email, social_links: socialLinks
                }));
            }
            await API.post('/auth/register', {
                email,
                password,
                role: clinicIntent ? 'clinic' : 'patient',
                firstNameAr,
                lastNameAr,
                firstNameEn,
                lastNameEn,
                phone,
                gender,
                socialLinks: registrationSocialLinks
            }, { auth: false });

            showAlert(isAr()
                ? 'تم إنشاء الحساب بنجاح! يرجى التحقق من بريدك الإلكتروني ثم تسجيل الدخول.'
                : 'Account created! Please check your email to verify it, then log in.', 'success');

            // Do not send a newly registered person back to login before they
            // can activate their account. The verification page pre-fills the
            // address and has a resend action if delivery is delayed.
            setTimeout(() => { window.location.href = verificationUrl(email); }, 900);
        } catch (err) {
            alertForError(err);
        } finally {
            setLoading('registerBtn', false);
        }
    }

    // ================= FORGOT PASSWORD =================
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

    // ================= RESET PASSWORD =================
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

    // ================= VERIFY EMAIL =================
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

    // ================= SHARED: password visibility toggle =================
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

    // ================= SHARED: password strength meter =================
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

    // ================= INIT (per page, by element presence) =================
    document.addEventListener('DOMContentLoaded', () => {
        configureClinicSignupForm();
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

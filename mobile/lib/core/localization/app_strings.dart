import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../locale/locale_controller.dart';

/// Hand-maintained Arabic/English string table for the screens this app
/// implements. Deliberately not a full port of the web frontend's
/// `i18n.js` (700+ keys covering pages this app doesn't have yet) — just
/// enough for auth, home, and the four patient feature screens.
class AppStrings {
  const AppStrings(this.isArabic);

  final bool isArabic;

  String _t(String ar, String en) => isArabic ? ar : en;

  // Common
  String get appName => 'MedOrbit';
  String get retry => _t('إعادة المحاولة', 'Retry');
  String get cancel => _t('إلغاء', 'Cancel');
  String get close => _t('إغلاق', 'Close');
  String get ok => _t('حسنًا', 'OK');
  String get loading => _t('جارٍ التحميل...', 'Loading...');
  String get errorGeneric => _t(
    'حدث خطأ ما. حاول مرة أخرى.',
    'Something went wrong. Please try again.',
  );

  /// Shown whenever the AI service itself is not reachable or not healthy.
  /// Deliberately says nothing about hosts, ports or diagnostics.
  String get aiServiceUnavailable => _t(
    'الخدمة غير متاحة حاليًا. تحقق من اتصالك ثم حاول مرة أخرى.',
    'This service is temporarily unavailable. Check your connection and try again.',
  );

  // Chat failure categories. Kept distinct so an unreachable service is never
  // described as "slow" — that reads as "your question is still being
  // answered", which is misleading in a medical context.
  String get chatErrTitle =>
      _t('تعذّر إرسال الرسالة', 'Could not send message');
  String get chatErrTimeout => _t(
    'استغرقت الاستجابة وقتًا أطول من المتوقع. حاول مرة أخرى.',
    'The response took longer than expected. Please try again.',
  );
  String get chatErrUnavailable => _t(
    'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم أعد المحاولة.',
    'Could not reach the service. Check your connection and try again.',
  );
  String get chatErrInvalidResponse => _t(
    'وصل رد غير مكتمل. أعد المحاولة.',
    'The reply was incomplete. Please try again.',
  );
  String get chatErrServer => _t(
    'تعذّر إكمال الطلب. أعد المحاولة.',
    'We could not complete the request. Please try again.',
  );
  String get comingSoon => _t(
    'هذه الميزة غير متاحة حالياً',
    'This feature is currently unavailable',
  );
  String get brandTagline =>
      _t('منصة رعاية صحية ذكية', 'Smart Healthcare Platform');

  // Chat entitlement failures. Kept apart from the transport categories above
  // — these are the backend enforcing a real quota/subscription rule, not a
  // network or server fault, so they get their own title and never claim the
  // problem is connectivity.
  String get chatErrQuotaTitle =>
      _t('تم استهلاك رسائلك المجانية', 'Free messages used');
  String get chatErrQuotaMessage => _t(
    'استخدمت جميع رسائلك المجانية لهذه الفترة. سيتم تجديدها تلقائيًا — يرجى المحاولة لاحقًا.',
    "You've used all your free messages for this period. They reset automatically — please try again later.",
  );
  String get chatErrDuplicateTitle => _t('جارٍ المعالجة', 'Still processing');
  String get chatErrDuplicateMessage => _t(
    'رسالتك السابقة ما زالت قيد المعالجة. انتظر لحظة قبل إعادة المحاولة.',
    'Your previous message is still being processed. Wait a moment before retrying.',
  );
  String get chatErrEntitlementUnavailable => _t(
    'تعذّر التحقق من صلاحيتك حاليًا. حاول مرة أخرى.',
    'Could not verify your access right now. Please try again.',
  );
  String get chatErrSubscriptionRequiredTitle =>
      _t('يلزم اشتراك', 'Subscription required');
  String get chatErrSubscriptionRequired => _t(
    'هذه الميزة تتطلب اشتراك Pro.',
    'This feature requires a Pro subscription.',
  );
  String get chatErrSubscriptionInactiveTitle =>
      _t('الاشتراك غير نشط', 'Subscription inactive');
  String get chatErrSubscriptionInactive => _t(
    'اشتراكك غير نشط حاليًا.',
    'Your subscription is not currently active.',
  );
  String get moreActionsTooltip => _t('المزيد من الإجراءات', 'More actions');
  String get appStarting => _t('جارٍ تجهيز ميد أوربت', 'Preparing MedOrbit');

  // Auth
  String get welcomeTitle =>
      _t('مرحبًا بك في ميد أوربت', 'Welcome to MedOrbit');
  String get signInSubtitle =>
      _t('سجّل الدخول للمتابعة', 'Sign in to continue');
  String get emailLabel => _t('البريد الإلكتروني', 'Email');
  String get emailPlaceholder =>
      _t('example@medorbit.com', 'example@medorbit.com');
  String get emailRequired =>
      _t('البريد الإلكتروني مطلوب.', 'Email is required.');
  String get invalidEmail =>
      _t('أدخل بريدًا إلكترونيًا صالحًا.', 'Enter a valid email address.');
  String requiredField(String label) =>
      _t('$label مطلوب.', '$label is required.');
  String get passwordLabel => _t('كلمة المرور', 'Password');
  String get passwordPlaceholder =>
      _t('أدخل كلمة المرور', 'Enter your password');
  String get logIn => _t('تسجيل الدخول', 'Log In');
  String get orDivider => _t('أو', 'OR');
  String get continueWithGoogle =>
      _t('المتابعة باستخدام جوجل', 'Continue with Google');
  String get invalidCredentials => _t(
    'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    'Incorrect email or password.',
  );
  String get emailNotVerified => _t(
    'يرجى تفعيل بريدك الإلكتروني قبل تسجيل الدخول.',
    'Please verify your email before signing in.',
  );
  String get authRateLimited => _t(
    'محاولات كثيرة جدًا. حاول مرة أخرى لاحقًا.',
    'Too many attempts. Please try again later.',
  );
  String get authConnectionError => _t(
    'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم حاول مرة أخرى.',
    'Could not reach the service. Check your connection and try again.',
  );
  String get authRequestError => _t(
    'تعذّر إكمال الطلب. حاول مرة أخرى.',
    'Could not complete the request. Please try again.',
  );
  String get registrationValidationError => _t(
    'يرجى مراجعة البيانات التي أدخلتها ثم المحاولة مرة أخرى.',
    'Please review the information you entered and try again.',
  );
  String get googleSignInError => _t(
    'تعذّر تسجيل الدخول باستخدام جوجل. حاول مرة أخرى.',
    'Could not sign in with Google. Please try again.',
  );
  String get noAccountCta =>
      _t('ليس لديك حساب؟ إنشاء حساب', "Don't have an account? Register");
  String get haveAccountCta =>
      _t('لديك حساب؟ تسجيل الدخول', 'Already have an account? Log in');
  String get createAccountTitle => _t('إنشاء حساب', 'Create Account');
  String get personalDetailsSection =>
      _t('البيانات الشخصية', 'Personal Details');
  String get contactSection => _t('معلومات التواصل', 'Contact Info');
  String get securitySection => _t('الأمان', 'Security');
  String get authHelpSection => _t('بحاجة إلى مساعدة؟', 'Need help?');
  String get firstNameEnLabel =>
      _t('الاسم الأول (إنجليزي)', 'First Name (English)');
  String get lastNameEnLabel =>
      _t('اسم العائلة (إنجليزي)', 'Last Name (English)');
  String get firstNameArLabel =>
      _t('الاسم الأول (عربي)', 'First Name (Arabic)');
  String get lastNameArLabel => _t('اسم العائلة (عربي)', 'Last Name (Arabic)');
  String get phoneOptionalLabel =>
      _t('رقم الهاتف (اختياري)', 'Phone (optional)');
  String get maleLabel => _t('ذكر', 'Male');
  String get femaleLabel => _t('أنثى', 'Female');
  String get registerButton => _t('إنشاء حساب', 'Register');
  String get registrationStepOne =>
      _t('الخطوة 1 من 2: بيانات الحساب', 'Step 1 of 2: Account details');
  String get verificationStepTwo =>
      _t('الخطوة 2 من 2: تأكيد البريد', 'Step 2 of 2: Email verification');
  String get continueToVerification =>
      _t('المتابعة إلى التحقق', 'Continue to verification');
  String get termsAgreement => _t(
    'أوافق على شروط الاستخدام وسياسة الخصوصية',
    'I agree to the Terms of Use and Privacy Policy',
  );
  String get termsRequired =>
      _t('يجب الموافقة للمتابعة.', 'You must agree before continuing.');
  String get passwordRequired =>
      _t('كلمة المرور مطلوبة.', 'Password is required.');
  String get confirmPasswordRequired =>
      _t('أكد كلمة المرور.', 'Confirm your password.');
  String get passwordPolicyError => _t(
    'استخدم 8 أحرف على الأقل تشمل حرفًا كبيرًا وصغيرًا ورقمًا ورمزًا خاصًا.',
    'Use 8+ characters including uppercase, lowercase, a number, and a special character.',
  );
  String get showPassword => _t('إظهار كلمة المرور', 'Show password');
  String get hidePassword => _t('إخفاء كلمة المرور', 'Hide password');
  String get registerSuccessMessage => _t(
    'تم إنشاء الحساب بنجاح. تحقق من بريدك الإلكتروني لتفعيله ثم سجّل الدخول.',
    'Account created. Check your email to verify it, then log in.',
  );
  String get registerSubtitle => _t(
    'أنشئ حسابك لإدارة المواعيد والوصفات والسجلات.',
    'Create your account to manage appointments, prescriptions, and records.',
  );
  String get verifyEmailHint => _t(
    'إذا لم يصلك الرمز، يمكنك طلب إعادة الإرسال.',
    'If you did not receive the code, you can request it again.',
  );
  String get forgotPasswordTitle => _t('نسيت كلمة المرور؟', 'Forgot Password?');
  String get forgotPasswordSubtitle => _t(
    'أدخل بريدك الإلكتروني وسنرسل لك رابط إعادة التعيين.',
    'Enter your email and we will send a reset link.',
  );
  String get sendResetLinkButton =>
      _t('إرسال رابط إعادة التعيين', 'Send Reset Link');
  String get resetLinkSentTitle =>
      _t('تحقق من بريدك الإلكتروني', 'Check your email');
  String get resetLinkSentHint => _t(
    'إذا كان البريد الإلكتروني موجودًا، فقد تم إرسال رابط لإعادة التعيين.',
    'If the email exists, a reset link has been sent.',
  );
  String get verifyCodeTitle => _t('تحقق من البريد الإلكتروني', 'Verify Email');
  String get verifyCodeSubtitle => _t(
    'أدخل رمز التحقق الموجود في البريد الإلكتروني.',
    'Enter the verification code from your email.',
  );
  String get codeSentTitle => _t('تحقق من صندوق الوارد', 'Check your inbox');
  String codeSentTo(String email) => _t(
    'أرسلنا رمزًا من 6 أرقام إلى $email',
    'We sent a 6-digit code to $email',
  );
  String get enterEmailToVerify => _t(
    'أدخل بريد الحساب لتأكيد الرمز.',
    'Enter the account email to verify the code.',
  );
  String get enterSixDigitCode =>
      _t('أدخل الرمز المكون من 6 أرقام', 'Enter the 6-digit code');
  String otpDigitLabel(int position) =>
      _t('رقم التحقق $position من 6', 'Verification digit $position of 6');
  String get otpIncomplete =>
      _t('أدخل الأرقام الستة.', 'Enter all six digits.');
  String get verifyingEmail =>
      _t('جارٍ التحقق من البريد الإلكتروني', 'Verifying email');
  String get verificationCodeLabel => _t('رمز التحقق', 'Verification Code');
  String get verificationCodePlaceholder => _t('123456', '123456');
  String get verifyEmailButton => _t('تحقق الآن', 'Verify Now');
  String get verifySuccessTitle =>
      _t('تم التحقق من البريد الإلكتروني', 'Email verified');
  String get verifySuccessHint => _t(
    'أصبح حسابك جاهزًا. يمكنك تسجيل الدخول الآن.',
    'Your account is ready. You can log in now.',
  );
  String get verifyCodeMissing => _t(
    'أدخل رمز التحقق أو افتح الرابط من البريد الإلكتروني.',
    'Enter the verification code or open the link from your email.',
  );
  String get resendVerificationTitle =>
      _t('لم يصلك الرمز؟', 'Did not receive the code?');
  String get resendVerificationHint => _t(
    'يمكنك طلب رمز جديد بعد انتهاء العد التنازلي.',
    'You can request a new code when the countdown ends.',
  );
  String get resendVerificationButton => _t('إعادة إرسال الرمز', 'Resend code');
  String resendIn(int seconds) =>
      _t('إعادة الإرسال خلال $seconds ث', 'Resend in ${seconds}s');
  String get resendSuccess => _t(
    'تم إرسال رمز جديد إذا كان الحساب مؤهلًا.',
    'A new code was sent if the account is eligible.',
  );
  String get invalidVerificationCode => _t(
    'رمز التحقق غير صحيح. حاول مرة أخرى.',
    'That verification code is incorrect. Try again.',
  );
  String get expiredVerificationCode => _t(
    'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.',
    'That code has expired. Request a new one.',
  );
  String get usedVerificationCode => _t(
    'تم استخدام هذا الرمز من قبل. حاول تسجيل الدخول.',
    'That code was already used. Try logging in.',
  );
  String get verificationRateLimited => _t(
    'محاولات كثيرة. انتظر قليلًا ثم حاول مجددًا.',
    'Too many attempts. Wait a while and try again.',
  );
  String get verificationValidationError => _t(
    'تحقق من البريد والرمز ثم حاول مجددًا.',
    'Check the email and code, then try again.',
  );
  String get resetPasswordTitle =>
      _t('إعادة تعيين كلمة المرور', 'Reset Password');
  String get resetPasswordSubtitle => _t(
    'أدخل كلمة مرور جديدة لحسابك.',
    'Enter a new password for your account.',
  );
  String get resetTokenLabel => _t('رمز/رابط التحقق', 'Reset Token / Code');
  String get resetTokenPlaceholder =>
      _t('أدخل الرمز من البريد الإلكتروني', 'Enter the code from your email');
  String get resetTokenRequired =>
      _t('رمز إعادة التعيين مطلوب.', 'Reset token is required.');
  String get resetInvalidToken => _t(
    'رابط إعادة التعيين غير صالح أو منتهي الصلاحية.',
    'This reset link is invalid or has expired.',
  );
  String get resetValidationError => _t(
    'تحقق من رمز إعادة التعيين ومتطلبات كلمة المرور ثم حاول مجددًا.',
    'Check the reset token and password requirements, then try again.',
  );
  String get newPasswordLabel => _t('كلمة المرور الجديدة', 'New Password');
  String get newPasswordPlaceholder =>
      _t('أدخل كلمة المرور الجديدة', 'Enter your new password');
  String get confirmPasswordLabel =>
      _t('تأكيد كلمة المرور', 'Confirm Password');
  String get confirmPasswordPlaceholder =>
      _t('أعد إدخال كلمة المرور', 'Re-enter your password');
  String get resetPasswordButton =>
      _t('تعيين كلمة المرور الجديدة', 'Set New Password');
  String get resetPasswordSuccessTitle =>
      _t('تم تحديث كلمة المرور', 'Password updated');
  String get resetPasswordSuccessHint =>
      _t('يمكنك تسجيل الدخول الآن.', 'You can log in now.');
  String get passwordMismatch =>
      _t('كلمتا المرور غير متطابقتين', 'Passwords do not match');
  String get passwordStrengthHint => _t(
    'استخدم 8 أحرف على الأقل مع حرف إنجليزي كبير وصغير ورقم ورمز.',
    'Use 8+ characters with uppercase, lowercase, a number, and a symbol.',
  );
  String get backToLogin => _t('العودة لتسجيل الدخول', 'Back to Login');

  /// Maps a backend/transport error code to safe localized verification copy.
  /// The raw server [message] is never rendered: [hadError] is only a signal
  /// that an error exists (so a genuinely error-free state returns null), and
  /// any unrecognized code falls back to [errorGeneric].
  ///
  /// Verified `/auth/verify-email` codes: VALIDATION_ERROR (400),
  /// INVALID_VERIFICATION_TOKEN (400), VERIFICATION_TOKEN_USED (409),
  /// VERIFICATION_TOKEN_EXPIRED (410), RATE_LIMITED (429). Transport codes
  /// come from [ApiException] (`network/api_exception.dart`).
  String? verificationError(String? code, {required bool hadError}) =>
      switch (code) {
        'INVALID_VERIFICATION_TOKEN' => invalidVerificationCode,
        'VERIFICATION_TOKEN_EXPIRED' => expiredVerificationCode,
        'VERIFICATION_TOKEN_USED' => usedVerificationCode,
        'RATE_LIMITED' => verificationRateLimited,
        'VALIDATION_ERROR' => verificationValidationError,
        'CONNECT_TIMEOUT' ||
        'SEND_TIMEOUT' ||
        'RECEIVE_TIMEOUT' ||
        'SERVICE_UNAVAILABLE' => authConnectionError,
        _ => hadError ? errorGeneric : null,
      };

  // Bottom nav
  String get navHome => _t('الرئيسية', 'Home');
  String get navRecords => _t('السجلات', 'Records');
  String get navPrescriptions => _t('الوصفات', 'Prescriptions');
  String get navAppointments => _t('المواعيد', 'Appointments');
  String get navFeedback => _t('آراؤكم', 'Feedback');
  String get navDiscover => _t('استكشف', 'Discover');
  String get navServices => _t('الخدمات', 'Services');
  String get profileGroupAccount => _t('الحساب', 'Account');
  String get profileGroupServices => _t('خدمات ميدأوربت', 'MedOrbit services');
  String get profileGroupRoleTools => _t('أدوات الدور', 'Role tools');
  String get profileGroupPreferences =>
      _t('التفضيلات والأمان', 'Preferences & security');

  String get discoverTitle => _t('استكشف ميدأوربت', 'Discover MedOrbit');
  String get discoverSubtitle => _t(
    'ابحث عن الأطباء والعيادات المعتمدة من مكان واحد.',
    'Find approved doctors and clinics from one place.',
  );
  String get servicesTitle => _t('خدمات ميدأوربت', 'MedOrbit services');
  String get servicesSubtitle => _t(
    'خدماتك المشتركة وأدوات دورك منظمة في مكان واحد.',
    'Your shared services and role tools, organized in one place.',
  );
  String get servicesSharedGroup => _t('الخدمات المشتركة', 'Shared services');
  String get servicesCommunicationGroup =>
      _t('التواصل والأدوات الذكية', 'Communication & AI tools');
  String get servicesPatientGroup => _t('رعايتي الصحية', 'My care');
  String get servicesDoctorGroup => _t('أدوات الطبيب', 'Doctor tools');
  String get servicesAdminGroup => _t('أدوات الإدارة', 'Administration tools');

  // Home
  String get welcomeBack => _t('مرحبًا بعودتك', 'Welcome back');
  String get homeSharedTitle => _t('ميدأوربت معك', 'Your MedOrbit');
  String get homeSharedSubtitle => _t(
    'الخدمات المشتركة تبقى متاحة مهما كان نوع حسابك.',
    'Shared MedOrbit services stay available for every account.',
  );
  String get homeRoleToolsTitle => _t('مساحة دورك', 'Your role workspace');
  String get homeRoleToolsSubtitle => _t(
    'أدوات إضافية مخصصة لمسؤوليات هذا الحساب.',
    'Additional tools tailored to this account’s responsibilities.',
  );
  String get homeAiDescription => _t(
    'افتح المحادثة الطبية والطبيب الصوتي وأدوات التحليل.',
    'Open medical chat, Voice Doctor, and analysis tools.',
  );
  String get patientDashboardSubtitle => _t(
    'إليك نظرة سريعة على صحتك ورعايتك.',
    'Here is a quick look at your health and care.',
  );
  String get doctorDashboardSubtitle => _t(
    'إليك نظرة سريعة على حسابك المهني.',
    'Here is a quick look at your professional account.',
  );
  String get adminDashboardSubtitle => _t(
    'إليك نظرة سريعة على حساب الإدارة.',
    'Here is a quick look at your administration account.',
  );
  String get adminMobileDashboardTitle => _t('مساحة الإدارة', 'Administration');
  String get adminMobileDashboardHint => _t(
    'لا تتضمن حسابات الإدارة بيانات صحية أو أدوات طبية. أدوات الإدارة أدناه تعمل على البيانات التشغيلية فقط.',
    'Administration accounts do not include health data or medical tools. The tools below act on operational data only.',
  );
  String get adminStatsUsers => _t('إجمالي المستخدمين', 'Total users');
  String get adminStatsPatients => _t('المرضى', 'Patients');
  String get adminStatsDoctors => _t('الأطباء', 'Doctors');
  String get adminStatsAppointments => _t('إجمالي المواعيد', 'Appointments');
  String get adminStatsRecords => _t('السجلات الطبية', 'Medical records');
  String get adminStatsPrescriptions => _t('الوصفات الطبية', 'Prescriptions');
  String get adminStatsRating => _t('متوسط التقييم', 'Average rating');
  String get profileLoadErrorTitle =>
      _t('تعذر تحميل ملفك الشخصي', 'Could not load your profile');
  String get profileLoadErrorMessage => _t(
    'تحقق من الاتصال ثم أعد المحاولة.',
    'Check your connection and try again.',
  );
  String get loadingProfile =>
      _t('جارٍ تحميل ملفك الشخصي...', 'Loading your profile...');
  String get rolePatient => _t('مريض', 'Patient');
  String get roleDoctor => _t('طبيب', 'Doctor');
  String get roleAdmin => _t('مسؤول', 'Administrator');
  String get dashboardStatisticsTitle => _t('نظرة عامة', 'Overview');
  String get dashboardStatisticsSubtitle => _t(
    'ملخص مباشر لبياناتك الصحية المتاحة.',
    'A live summary of your available health data.',
  );
  String get upcomingAppointmentsStat =>
      _t('مواعيد قادمة', 'Upcoming appointments');
  String get prescriptionsStat => _t('وصفات طبية', 'Prescriptions');
  String get medicalRecordsStat => _t('سجلات طبية', 'Medical records');
  String get statLoadError => _t(
    'تعذر تحميل العدد. اضغط لإعادة المحاولة.',
    'Count unavailable. Tap to retry.',
  );
  String get quickActionsTitle => _t('إجراءات سريعة', 'Quick Actions');
  String get quickActionsSubtitle => _t(
    'ابحث أو انتقل إلى الخدمات المتاحة.',
    'Search or open an available service.',
  );
  String get dashboardSearchLabel =>
      _t('البحث في الإجراءات السريعة', 'Search quick actions');
  String get dashboardSearchPlaceholder =>
      _t('ابحث في لوحة التحكم...', 'Search the dashboard...');
  String get dashboardSearchNoResults =>
      _t('لا توجد نتائج مطابقة', 'No matching actions');
  String get dashboardSearchNoResultsHint =>
      _t('جرّب كلمة بحث أخرى.', 'Try a different search term.');
  String get clearSearch => _t('مسح البحث', 'Clear search');
  String get quickGroupCare => _t('الرعاية والمواعيد', 'Care and appointments');
  String get quickGroupHealthData => _t('بياناتي الصحية', 'My health data');
  String get quickClinicsNearbyLabel =>
      _t('العيادات القريبة', 'Clinics nearby');
  String get quickClinicsNearbyDescription => _t(
    'ابحث عن العيادات والمرافق الصحية القريبة منك في نابلس.',
    'Find clinics and healthcare facilities around Nablus.',
  );
  String get quickFindDoctorLabel => _t('ابحث عن طبيب', 'Find a doctor');
  String get quickFindDoctorDescription => _t(
    'تصفح الأطباء المسجلين في المرافق الصحية.',
    'Browse doctors listed by healthcare facilities.',
  );
  String get quickMedicalChatLabel => _t('المحادثة الطبية', 'Medical chat');
  String get quickMedicalChatDescription => _t(
    'احصل على إرشاد طبي عام ونتائج الرعاية القريبة.',
    'Get general medical guidance and nearby care results.',
  );
  String get quickGroupSupport => _t('الدعم والمشاركة', 'Support and feedback');
  String get quickAppointmentsDescription => _t(
    'راجع مواعيدك وحالاتها.',
    'Review your appointments and their status.',
  );
  String get quickBookAppointmentDescription => _t(
    'احجز موعدًا جديدًا مع طبيبك المفضل.',
    'Book a new appointment with your doctor.',
  );
  String get quickPrescriptionsDescription =>
      _t('اعرض وصفاتك وأدويتك.', 'View your prescriptions and medicines.');
  String get prescriptionPdfAction =>
      _t('فتح ملف الوصفة PDF', 'Open prescription PDF');
  String get prescriptionPdfDownloadError => _t(
    'تعذر تنزيل ملف الوصفة. حاول مرة أخرى.',
    'Could not download the prescription PDF. Please try again.',
  );
  String get prescriptionPdfOpenError => _t(
    'تم تنزيل ملف الوصفة، لكن تعذر فتحه.',
    'The prescription PDF was downloaded but could not be opened.',
  );
  String get quickRecordsDescription =>
      _t('راجع سجلك الطبي المتاح.', 'Review your available medical history.');
  String get quickMyDoctorsDescription => _t(
    'راجع أطباء الرعاية والملاحظات المشتركة.',
    'Review your care doctors and shared notes.',
  );
  String get quickSavedPlacesDescription => _t(
    'راجع الأماكن التي حفظتها من المحادثات الطبية.',
    'Review places you saved from medical conversations.',
  );
  String get savedPlacesTitle => _t('الأماكن المحفوظة', 'Saved Places');
  String get savedPlacesSubtitle => _t(
    'أماكن الرعاية التي حفظتها أثناء استخدام المحادثة الطبية.',
    'Care places you saved while using medical chat.',
  );
  String get savedPlacesLoadErrorTitle =>
      _t('تعذر تحميل الأماكن المحفوظة', 'Could not load saved places');
  String get savedPlacesLoadErrorHint => _t(
    'تحقق من اتصالك ثم حاول مرة أخرى.',
    'Check your connection and try again.',
  );
  String get savedPlacesEmptyTitle =>
      _t('لا توجد أماكن محفوظة', 'No saved places yet');
  String get savedPlacesEmptyHint => _t(
    'يمكنك حفظ مكان من نتائج المحادثة الطبية وسيظهر هنا.',
    'Save a place from medical chat results and it will appear here.',
  );
  String get savedPlaceFallbackName => _t('مكان رعاية', 'Care place');
  String savedPlaceDistance(double kilometers) => _t(
    '${kilometers.toStringAsFixed(1)} كم',
    '${kilometers.toStringAsFixed(1)} km away',
  );
  String get myDoctorsTitle => _t('أطبائي', 'My Doctors');
  String get myDoctorsSubtitle => _t(
    'الأطباء الذين لديك معهم علاقة رعاية نشطة.',
    'Doctors with whom you have an active care relationship.',
  );
  String get myDoctorsLoadErrorTitle =>
      _t('تعذر تحميل أطبائك', 'Could not load your doctors');
  String get myDoctorsLoadErrorHint => _t(
    'تحقق من اتصالك ثم حاول مرة أخرى.',
    'Check your connection and try again.',
  );
  String get myDoctorsEmptyTitle =>
      _t('لا يوجد أطباء مرتبطون بحسابك', 'No care doctors yet');
  String get myDoctorsEmptyHint => _t(
    'سيظهر الطبيب هنا بعد إتمام موعد وعلاقة رعاية.',
    'A doctor appears here after an appointment establishes a care relationship.',
  );
  String get myDoctorsCareRelationship =>
      _t('علاقة رعاية نشطة', 'Active care relationship');
  String myDoctorsNextAppointment(String date) =>
      _t('الموعد القادم: $date', 'Next appointment: $date');
  String myDoctorsLastAppointment(String date) =>
      _t('آخر موعد: $date', 'Last appointment: $date');
  String get sharedDoctorNotesAction =>
      _t('الملاحظات المشتركة', 'Shared notes');
  String get sharedDoctorNotesTitle =>
      _t('ملاحظات الطبيب المشتركة', 'Shared doctor notes');
  String get sharedDoctorNotesSubtitle => _t(
    'ملاحظات وسجلات شاركها طبيبك معك.',
    'Notes and records your doctor has shared with you.',
  );
  String sharedDoctorNotesFor(String doctor) => _t(
    'الملاحظات التي شاركها $doctor معك.',
    'Notes $doctor has shared with you.',
  );
  String get sharedDoctorNotesLoadErrorTitle =>
      _t('تعذر تحميل الملاحظات المشتركة', 'Could not load shared notes');
  String get sharedDoctorNotesLoadErrorHint => _t(
    'تحقق من اتصالك ثم حاول مرة أخرى.',
    'Check your connection and try again.',
  );
  String get sharedDoctorNotesEmptyTitle =>
      _t('لا توجد ملاحظات مشتركة', 'No shared notes yet');
  String get sharedDoctorNotesEmptyHint => _t(
    'ستظهر هنا فقط الملاحظات التي جعلها طبيبك مرئية لك.',
    'Only notes your doctor made visible to you appear here.',
  );
  String get sharedNoteDiagnosis => _t('التشخيص', 'Diagnosis');
  String get sharedNoteTreatmentPlan => _t('خطة العلاج', 'Treatment plan');
  String get sharedNoteClinicalNotes =>
      _t('الملاحظات السريرية', 'Clinical notes');
  String get quickFeedbackDescription =>
      _t('شارك رأيك في تجربتك.', 'Share feedback about your experience.');
  String get quickContactDescription => _t(
    'أرسل رسالة مباشرة إلى فريق ميد أوربت.',
    'Send a message to the MedOrbit team.',
  );
  String get contactTitle => _t('تواصل معنا', 'Contact us');
  String get contactSubtitle => _t(
    'أرسل استفسارك إلى فريق الدعم وسيراجعه فريق الإدارة.',
    'Send your question to support; the administration team will review it.',
  );
  String get contactSubjectLabel => _t('الموضوع', 'Subject');
  String get contactMessageLabel => _t('رسالتك', 'Your message');
  String get contactSubjectRequired =>
      _t('الموضوع مطلوب.', 'A subject is required.');
  String get contactMessageRequired =>
      _t('الرسالة مطلوبة.', 'A message is required.');
  String get contactSendAction => _t('إرسال الرسالة', 'Send message');
  String get contactSentSuccess =>
      _t('تم إرسال رسالتك بنجاح.', 'Your message was sent successfully.');
  String get contactSentError => _t(
    'تعذر إرسال الرسالة. حاول مرة أخرى.',
    'Could not send the message. Please try again.',
  );
  String get quickVirtualDoctorDescription =>
      _t('ابدأ جلسة مع الطبيب الافتراضي.', 'Start a Virtual Doctor session.');
  String get upcomingAppointmentsTitle =>
      _t('المواعيد القادمة', 'Upcoming Appointments');
  String get recentPrescriptionsTitle =>
      _t('أحدث الوصفات الطبية', 'Recent Prescriptions');
  String get recentMedicalRecordsTitle =>
      _t('أحدث السجلات الطبية', 'Recent Medical Records');
  String get loadingAppointments =>
      _t('جارٍ تحميل المواعيد...', 'Loading appointments...');
  String get loadingPrescriptions =>
      _t('جارٍ تحميل الوصفات...', 'Loading prescriptions...');
  String get loadingMedicalRecords =>
      _t('جارٍ تحميل السجلات...', 'Loading medical records...');
  String get prescriptionsLoadErrorTitle =>
      _t('تعذر تحميل الوصفات الطبية', 'Could not load prescriptions');
  String get recordsLoadErrorTitle =>
      _t('تعذر تحميل السجلات الطبية', 'Could not load medical records');
  String get noUpcomingAppointments =>
      _t('لا توجد مواعيد قادمة', 'No upcoming appointments');
  String get noUpcomingAppointmentsHint => _t(
    'يمكنك مراجعة جميع مواعيدك من صفحة المواعيد.',
    'Review all your appointments on the appointments page.',
  );
  String get appointmentsLoadErrorTitle =>
      _t('تعذر تحميل المواعيد', 'Could not load appointments');
  String get appointmentsLoadErrorMessage => _t(
    'تحقق من الاتصال ثم أعد المحاولة.',
    'Check your connection and try again.',
  );
  String get viewAll => _t('عرض الكل', 'View all');
  String get openAppointments => _t('فتح المواعيد', 'Open appointments');
  String get logoutTooltip => _t('تسجيل الخروج', 'Log out');
  String get languageToggleTooltip => _t('English', 'العربية');

  // Records
  String get recordsTitle => _t('سجلاتي الطبية', 'My Medical Records');
  String get recordsSubtitle => _t(
    'راجع تاريخ مواعيدك وتشخيصاتك ووصفاتك الطبية بترتيب زمني.',
    'Review your appointments, diagnoses, and prescriptions in one timeline.',
  );
  String get recordFiltersLabel =>
      _t('البحث وتصفية السجلات الطبية', 'Search and filter medical records');
  String get recordFiltersTitle => _t('البحث والتصفية', 'Search and filters');
  String get recordSearchLabel =>
      _t('البحث في السجلات', 'Search medical records');
  String get recordSearchPlaceholder => _t(
    'ابحث بالعنوان أو التشخيص أو الطبيب أو الدواء أو الرقم...',
    'Search by title, diagnosis, doctor, medicine, or number...',
  );
  String get recordDateFilterLabel => _t('تاريخ السجل', 'Record date');
  String get recordTypeFilterLabel => _t('نوع السجل', 'Record type');
  String get filterAllRecordTypes => _t('كل الأنواع', 'All record types');
  String get recordsNoResultsTitle =>
      _t('لا توجد سجلات مطابقة', 'No matching records');
  String get recordsNoResultsHint => _t(
    'جرّب تغيير البحث أو عوامل التصفية.',
    'Try changing your search or filters.',
  );
  String get medicalTimelineTitle =>
      _t('السجل الزمني الطبي', 'Medical timeline');
  String get medicalTimelineSubtitle => _t(
    'أحدث الأنشطة الطبية أولًا.',
    'Your latest medical activity appears first.',
  );
  String recordResultsCount(int count) => _t('$count سجل', '$count records');
  String get dateUnavailable => _t('التاريخ غير متاح', 'Date unavailable');
  String get recordNotesPreviewLabel => _t('ملخص', 'Summary');
  String get viewRecordDetails => _t('عرض التفاصيل', 'View details');
  String get recordOverviewTitle => _t('نظرة عامة', 'Overview');
  String get recordVitalsTitle => _t('العلامات الحيوية', 'Vitals');
  String get recordNumberLabel => _t('رقم السجل', 'Record number');
  String get appointmentNumberLabel => _t('رقم الموعد', 'Appointment number');
  String get recordStatusLabel => _t('الحالة', 'Status');
  String get recordEntryDateLabel => _t('تاريخ السجل', 'Record date');
  String get recordSubtypeConsultation => _t('استشارة', 'Consultation');
  String get recordSubtypeLabResult => _t('نتيجة مختبر', 'Lab result');
  String get recordSubtypeDiagnosis => _t('تشخيص', 'Diagnosis');
  String get recordSubtypeImaging => _t('تصوير طبي', 'Imaging');
  String get recordSubtypeProcedure => _t('إجراء طبي', 'Procedure');
  String get medicalAppointmentFallback =>
      _t('موعد طبي', 'Medical appointment');
  String get typeAppointment => _t('موعد', 'Appointment');
  String get typeRecord => _t('سجل', 'Record');
  String get typePrescription => _t('وصفة طبية', 'Prescription');
  String get recordsEmptyTitle => _t('لا توجد سجلات بعد', 'No records yet');
  String get recordsEmptyHint => _t(
    'ستظهر مواعيدك وسجلاتك ووصفاتك الطبية هنا.',
    'Your appointments, records, and prescriptions will appear here.',
  );
  String get loadErrorTitle => _t('تعذر تحميل البيانات', 'Failed to load data');
  String get detailDate => _t('التاريخ', 'Date');
  String get detailTime => _t('الوقت', 'Time');
  String get detailDoctor => _t('الطبيب', 'Doctor');
  String get detailSpecialty => _t('التخصص', 'Specialty');
  String get detailType => _t('النوع', 'Type');
  String get detailReason => _t('سبب الزيارة', 'Reason for Visit');
  String get detailDiagnosis => _t('التشخيص', 'Diagnosis');
  String get detailTreatmentPlan => _t('خطة العلاج', 'Treatment Plan');
  String get detailChiefComplaint => _t('الشكوى الرئيسية', 'Chief Complaint');
  String get detailAttachments => _t('المرفقات', 'Attachments');
  String get detailInstructions => _t('التعليمات', 'Instructions');
  String get detailMedications => _t('الأدوية', 'Medications');
  String get detailPrescriptionNumber =>
      _t('رقم الوصفة', 'Prescription Number');
  String get detailValidUntil => _t('صالحة حتى', 'Valid Until');

  // Prescriptions
  String get prescriptionsTitle => _t('وصفاتي الطبية', 'My Prescriptions');
  String get prescriptionsSubtitle => _t(
    'تتبّع وصفاتك الطبية الحالية والسابقة.',
    'Track your current and previous prescriptions.',
  );
  String get prescriptionFiltersLabel =>
      _t('البحث وتصفية الوصفات الطبية', 'Search and filter prescriptions');
  String get prescriptionFiltersTitle =>
      _t('البحث والتصفية', 'Search and filters');
  String get prescriptionSearchLabel =>
      _t('البحث في الوصفات', 'Search prescriptions');
  String get prescriptionSearchPlaceholder => _t(
    'ابحث برقم الوصفة أو التشخيص أو اسم الدواء...',
    'Search by number, diagnosis, or medicine...',
  );
  String get prescriptionStatusFilterLabel =>
      _t('حالة الوصفة', 'Prescription status');
  String get prescriptionDateFilterLabel => _t('تاريخ الإصدار', 'Issued date');
  String get filterAllPrescriptions => _t('كل الوصفات', 'All prescriptions');
  String get filterAnyDate => _t('أي تاريخ', 'Any date');
  String get filterLast30Days => _t('آخر 30 يومًا', 'Last 30 days');
  String get filterLastYear => _t('آخر سنة', 'Last year');
  String get prescriptionsEmptyTitle =>
      _t('لا توجد وصفات طبية بعد', 'No prescriptions yet');
  String get prescriptionsEmptyHint => _t(
    'ستظهر الوصفات الطبية التي يصفها طبيبك هنا.',
    "Prescriptions written by your doctor will appear here.",
  );
  String get prescriptionsNoResultsTitle =>
      _t('لا توجد وصفات مطابقة', 'No matching prescriptions');
  String get prescriptionsNoResultsHint => _t(
    'جرّب تغيير البحث أو عوامل التصفية.',
    'Try changing your search or filters.',
  );
  String get clearFilters => _t('مسح عوامل التصفية', 'Clear filters');
  String get prescriptionResultsTitle =>
      _t('الوصفات المتاحة', 'Available prescriptions');
  String prescriptionResultsCount(int count) =>
      _t('$count وصفة', '$count prescriptions');
  String prescriptionNumberValue(String value) =>
      _t('رقم الوصفة $value', 'Prescription number $value');
  String get issuedDateLabel => _t('تاريخ الإصدار', 'Issued date');
  String issuedDateValue(String value) =>
      _t('تاريخ الإصدار $value', 'Issued $value');
  String medicationCount(int count) => _t('$count دواء', '$count medications');
  String get viewPrescriptionDetails => _t('عرض التفاصيل', 'View details');
  String get prescriptionFallbackTitle => _t('وصفة طبية', 'Prescription');
  String get prescriptionDetailsTitle =>
      _t('تفاصيل الوصفة', 'Prescription details');
  String get noMedicationItemsTitle =>
      _t('لا توجد أدوية مفصلة', 'No medication items listed');
  String get noMedicationItemsHint => _t(
    'لا تحتوي هذه الوصفة على تفاصيل أدوية إضافية.',
    'This prescription has no additional medication details.',
  );
  String medicationFallbackName(int index) =>
      _t('الدواء $index', 'Medication $index');
  String get medicationDosage => _t('الجرعة', 'Dosage');
  String get medicationFrequency => _t('التكرار', 'Frequency');
  String get medicationDuration => _t('المدة', 'Duration');
  String get medicationQuantity => _t('الكمية', 'Quantity');
  String get medicationInstructions =>
      _t('تعليمات الدواء', 'Medication instructions');
  String get statusActive => _t('نشطة', 'Active');
  String get statusExpired => _t('منتهية', 'Expired');
  String get statusCompleted => _t('مكتملة', 'Completed');
  String get statusCancelled => _t('ملغاة', 'Cancelled');
  String get doctorNotes => _t('ملاحظات الطبيب', "Doctor's Notes");
  String get openPrescriptionPdf => _t('عرض PDF', 'Open PDF');
  String get preparingPrescriptionPdf => _t('جارٍ تحضير PDF', 'Preparing PDF');
  String get prescriptionPdfDownloadFailed => _t(
    'تعذر تحميل ملف PDF للوصفة. حاول مرة أخرى.',
    'Could not download prescription PDF. Please try again.',
  );
  String get prescriptionPdfOpenFailed => _t(
    'تعذر فتح ملف PDF. حاول مرة أخرى.',
    'Could not open PDF. Please try again.',
  );

  // Appointments
  String get appointmentsTitle => _t('مواعيدي', 'My Appointments');
  String get appointmentsSubtitle => _t(
    'إدارة مواعيدك الطبية القادمة والسابقة.',
    'Manage your upcoming and previous medical appointments.',
  );
  String get appointmentFiltersLabel =>
      _t('تصفية المواعيد حسب الحالة', 'Filter appointments by status');
  String get tabUpcoming => _t('القادمة', 'Upcoming');
  String get tabPast => _t('السابقة', 'Past');
  String get tabCancelled => _t('الملغاة', 'Cancelled');
  String get emptyUpcoming =>
      _t('لا توجد مواعيد قادمة', 'No upcoming appointments');
  String get emptyUpcomingHint => _t(
    'ستظهر مواعيدك المجدولة أو المؤكدة هنا.',
    'Your scheduled or confirmed appointments will appear here.',
  );
  String get emptyPast => _t('لا توجد مواعيد سابقة', 'No past appointments');
  String get emptyPastHint => _t(
    'ستظهر المواعيد المكتملة والسابقة هنا.',
    'Completed and previous appointments will appear here.',
  );
  String get emptyCancelledTab =>
      _t('لا توجد مواعيد ملغاة', 'No cancelled appointments');
  String get emptyCancelledHint => _t(
    'لا توجد مواعيد ملغاة في حسابك.',
    'There are no cancelled appointments in your account.',
  );
  String get cancelAppointmentAction =>
      _t('إلغاء الموعد', 'Cancel Appointment');
  String get cancelDialogTitle =>
      _t('إلغاء الموعد؟', 'Cancel this appointment?');
  String get cancelDialogBody => _t(
    'هل أنت متأكد من رغبتك في إلغاء هذا الموعد؟',
    'Are you sure you want to cancel this appointment?',
  );
  String get cancelReasonHint => _t('السبب (اختياري)', 'Reason (optional)');
  String get cancelReasonPlaceholder => _t(
    'اكتب سبب الإلغاء إن رغبت...',
    'Add a cancellation reason if needed...',
  );
  String get cancelConfirm => _t('تأكيد الإلغاء', 'Confirm Cancel');
  String get cancelSuccessMessage =>
      _t('تم إلغاء الموعد', 'Appointment cancelled');
  String get cancelErrorMessage => _t(
    'تعذر إلغاء الموعد. حاول مرة أخرى.',
    'Could not cancel the appointment. Try again.',
  );
  String get cancellingAppointment => _t('جارٍ الإلغاء...', 'Cancelling...');
  String get visitReasonLabel => _t('سبب الزيارة', 'Reason for visit');
  String get doctorNameUnavailable =>
      _t('بيانات الطبيب غير متاحة', 'Doctor details unavailable');
  String get appointmentTypeTelemedicine =>
      _t('استشارة عبر الإنترنت', 'Online Consultation');
  String get appointmentTypeInPerson =>
      _t('زيارة في العيادة', 'In-person visit');
  String appointmentNumberValue(String value) =>
      _t('رقم الموعد $value', 'Appointment number $value');
  String get statusScheduled => _t('مجدول', 'Scheduled');
  String get statusConfirmed => _t('مؤكد', 'Confirmed');
  String get statusInProgress => _t('جارٍ الآن', 'In Progress');
  String get statusAppointmentCompleted => _t('مكتمل', 'Completed');
  String get statusAppointmentCancelled => _t('ملغى', 'Cancelled');
  String get statusNoShow => _t('لم يحضر', 'No Show');
  String get bookNewAppointment => _t('حجز موعد جديد', 'Book New Appointment');

  // Appointment booking wizard
  String get bookingWizardTitle => _t('حجز موعد', 'Book Appointment');
  String get bookingStepDoctor => _t('الطبيب', 'Doctor');
  String get bookingStepSlot => _t('الموعد', 'Time Slot');
  String get bookingStepConfirm => _t('التأكيد', 'Confirm');
  String get chooseDoctorTitle => _t('اختر الطبيب', 'Choose a doctor');
  String get searchDoctorsHint =>
      _t('ابحث عن طبيب بالاسم...', 'Search for a doctor by name...');
  String get noDoctorsFound =>
      _t('لم يتم العثور على أطباء مطابقين', 'No matching doctors found');
  String get couldNotLoadDoctors =>
      _t('تعذر تحميل قائمة الأطباء', 'Could not load doctors');
  String get changeDoctorAction => _t('تغيير الطبيب', 'Change doctor');
  String get doctorNotFoundMessage =>
      _t('الطبيب غير موجود', 'Doctor not found');
  String get doctorLoadErrorMessage =>
      _t('تعذر تحميل بيانات الطبيب', "Could not load this doctor's data");
  String get doctorLabel => _t('الطبيب', 'Doctor');
  String get clinicLabel => _t('العيادة', 'Clinic');
  String get dateLabel => _t('التاريخ', 'Date');
  String get timeLabel => _t('الوقت', 'Time');
  String get appointmentTypeLabel => _t('نوع الموعد', 'Appointment type');
  String get chooseClinicLabel => _t('اختر العيادة', 'Select clinic');
  String get changeClinicAction => _t('تغيير العيادة', 'Change clinic');
  String get chooseDateLabel => _t('اختر التاريخ', 'Select date');
  String get changeDateAction => _t('تغيير التاريخ', 'Change date');
  String get availableSlotsLabel => _t('الأوقات المتاحة', 'Available times');
  String get slotHonestyNote => _t(
    'الأوقات المعروضة تعتمد على جدول الطبيب، ويتم تأكيد الموعد عند إتمام الحجز.',
    "Shown times are based on the doctor's schedule and are confirmed when booking is completed.",
  );
  String get noClinicsTitle => _t(
    'لا توجد عيادات متاحة لهذا الطبيب',
    'No clinics available for this doctor',
  );
  String get noClinicsHint => _t(
    'لا يمكن حجز موعد مع هذا الطبيب حاليًا',
    'This doctor cannot be booked right now',
  );
  String get noSlotsTitle => _t('لا توجد أوقات متاحة', 'No available times');
  String get noSlotsHint => _t(
    'جرّب اختيار تاريخ آخر أو عيادة أخرى',
    'Try a different date or clinic',
  );
  String get couldNotLoadSlots =>
      _t('تعذر تحميل الأوقات المتاحة', 'Could not load available times');
  String get additionalNotesLabel => _t('ملاحظات إضافية', 'Additional notes');
  String get confirmBookingTitle => _t('مراجعة وتأكيد', 'Review and confirm');
  String get confirmAndBookAction => _t('تأكيد الحجز', 'Confirm booking');
  String get bookingInProgress => _t('جارٍ الحجز...', 'Booking...');
  String get bookingSuccessTitle =>
      _t('تم حجز موعدك بنجاح', 'Your appointment is booked');
  String get bookingSuccessHint =>
      _t('رقم الموعد الخاص بك:', 'Your appointment number:');
  String get viewMyAppointmentsAction =>
      _t('عرض مواعيدي', 'View my appointments');
  String get bookAnotherAppointmentAction =>
      _t('حجز موعد آخر', 'Book another appointment');
  String get slotBusyMessage => _t(
    'تم حجز هذا الوقت للتو من مستخدم آخر، الرجاء اختيار وقت مختلف',
    'This time slot was just booked by someone else — please pick a different time',
  );
  String get patientNotFoundMessage => _t(
    'تعذر إيجاد ملفك الطبي. الرجاء التواصل مع الدعم الفني',
    'We could not find your patient profile. Please contact support',
  );
  String get bookingTimeoutMessage => _t(
    'استغرق الحجز وقتًا أطول من المتوقع. حاول مرة أخرى.',
    'Booking took longer than expected. Please try again.',
  );
  String get bookingServiceUnavailableMessage => _t(
    'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم أعد المحاولة.',
    'Could not reach the service. Check your connection and try again.',
  );
  String get couldNotCreateAppointment => _t(
    'تعذر إتمام الحجز، الرجاء المحاولة مرة أخرى',
    'Could not complete the booking, please try again',
  );
  String get backAction => _t('السابق', 'Back');
  String get nextAction => _t('التالي', 'Next');

  // My Doctor / care relationships
  String get myDoctorTitle => _t('طبيبي', 'My Doctor');
  String get myDoctorSubtitle => _t(
    'تابع أطباءك المعالجين ومواعيدك والملاحظات التي شاركوها معك.',
    "Keep track of your treating doctors, your appointments with them, and notes they've shared with you.",
  );
  String get myDoctorsSectionTitle => _t('أطبائي المعالجون', 'My Doctors');
  String get upcomingWithMyDoctorsTitle =>
      _t('المواعيد القادمة مع أطبائي', 'Upcoming Appointments With My Doctors');
  String get sharedNotesSectionTitle =>
      _t('الملاحظات المشتركة', 'Shared Notes');
  String get noActiveDoctorsTitle =>
      _t('لا يوجد أطباء معالجون حاليًا', 'No active doctors yet');
  String get noActiveDoctorsHint => _t(
    'سيظهر هنا الأطباء الذين لديك علاقة رعاية نشطة معهم.',
    'Doctors you have an active care relationship with will appear here.',
  );
  String get browseDoctorsAction => _t('تصفح الأطباء', 'Browse Doctors');
  String get doctorsLoadErrorTitle =>
      _t('تعذر تحميل أطبائك', 'Could not load your doctors');
  String get doctorsLoadErrorMessage => _t(
    'تحقق من الاتصال ثم أعد المحاولة.',
    'Check your connection and try again.',
  );
  String get noUpcomingWithMyDoctorsTitle =>
      _t('لا توجد مواعيد قادمة', 'No upcoming appointments');
  String get noUpcomingWithMyDoctorsHint => _t(
    'ستظهر هنا مواعيدك القادمة مع أطبائك المعالجين.',
    'Your upcoming appointments with your treating doctors will appear here.',
  );
  String get upcomingWithMyDoctorsErrorTitle =>
      _t('تعذر تحميل المواعيد', 'Could not load appointments');
  String get upcomingWithMyDoctorsErrorMessage => _t(
    'تحقق من الاتصال ثم أعد المحاولة.',
    'Check your connection and try again.',
  );
  String get noSharedNotesTitle =>
      _t('لا توجد ملاحظات مشتركة', 'No shared notes');
  String get noSharedNotesHint => _t(
    'الملاحظات التي يشاركها طبيبك معك ستظهر هنا.',
    'Notes your doctor shares with you will appear here.',
  );
  String get sharedNotesErrorTitle =>
      _t('تعذر تحميل الملاحظات المشتركة', 'Could not load shared notes');
  String get sharedNotesErrorMessage => _t(
    'تحقق من الاتصال ثم أعد المحاولة.',
    'Check your connection and try again.',
  );
  String get viewDoctorAction => _t('عرض الطبيب', 'View Doctor');
  String get bookAppointmentWithDoctorAction =>
      _t('حجز موعد', 'Book Appointment');
  String careSinceLabel(String date) =>
      _t('مريض منذ $date', 'Patient since $date');
  String nextVisitLabel(String date) =>
      _t('الزيارة القادمة: $date', 'Next visit: $date');
  String lastVisitLabel(String date) =>
      _t('آخر زيارة: $date', 'Last visit: $date');
  String get quickMyDoctorDescription => _t(
    'تابع أطباءك المعالجين ومواعيدك معهم.',
    'Track your treating doctors and appointments with them.',
  );

  // Notifications
  String get navNotifications => _t('الإشعارات', 'Notifications');
  String get notificationsTitle => _t('الإشعارات', 'Notifications');
  String get notificationsSubtitle =>
      _t('كل إشعاراتك في مكان واحد', 'All your notifications in one place');
  String get notificationsFilterAll => _t('الكل', 'All');
  String get notificationsFilterUnread => _t('غير مقروءة', 'Unread');
  String get notificationsMarkAllRead =>
      _t('تعليم الكل كمقروء', 'Mark all read');
  String get notificationsMarkRead => _t('تعليم كمقروء', 'Mark as read');
  String get notificationsDeleteOne => _t('حذف', 'Delete');
  String get notificationsDeleteDialogTitle =>
      _t('حذف الإشعار؟', 'Delete this notification?');
  String get notificationsDeleteDialogBody =>
      _t('لا يمكن التراجع عن هذا الإجراء.', 'This action cannot be undone.');
  String get notificationsErrorLoad =>
      _t('تعذر تحميل الإشعارات', 'Could not load your notifications');
  String get notificationsMarkReadError =>
      _t('تعذر تحديث الإشعار', 'Could not update the notification');
  String get notificationsMarkAllError =>
      _t('تعذر تحديث الإشعارات', 'Could not update notifications');
  String get notificationsDeleteError =>
      _t('تعذر حذف الإشعار', 'Could not delete the notification');
  String get notificationsEmptyTitle =>
      _t('لا توجد إشعارات', 'No notifications');
  String get notificationsEmptyHint => _t(
    'ستظهر إشعاراتك هنا عند وصولها',
    'Your notifications will show up here when they arrive',
  );
  String get notificationsEmptyUnreadTitle =>
      _t('لا توجد إشعارات غير مقروءة', 'No unread notifications');
  String get notificationsEmptyUnreadHint =>
      _t('أحسنت! لقد اطلعت على كل شيء', "Nice — you're all caught up");
  String get quickNotificationsDescription =>
      _t('عرض كل إشعاراتك', 'View all your notifications');
  String notificationsUnreadCountDescription(int count) => _t(
    '$count إشعار غير مقروء',
    '$count unread notification${count == 1 ? '' : 's'}',
  );
  String get notificationTypeAppointment => _t('موعد', 'Appointment');
  String get notificationTypeReminder => _t('تذكير', 'Reminder');
  String get notificationTypeSystem => _t('النظام', 'System');
  String get notificationTypeGeneric => _t('إشعار', 'Notification');
  String get notificationsJustNow => _t('الآن', 'now');
  String notificationsMinutesAgo(int minutes) =>
      _t('منذ $minutes د', '${minutes}m ago');
  String notificationsHoursAgo(int hours) =>
      _t('منذ $hours س', '${hours}h ago');
  String notificationsDaysAgo(int days) => _t('منذ $days يوم', '${days}d ago');

  // Profile / Settings
  String get navProfile => _t('حسابي', 'My Account');
  String get profileTitle => _t('حسابي', 'My Account');
  String get profileSubtitle => _t(
    'إدارة معلوماتك الشخصية وإعدادات حسابك',
    'Manage your personal information and account settings',
  );
  String get quickProfileDescription => _t(
    'عدّل بياناتك الشخصية وإعدادات حسابك.',
    'Edit your personal details and account settings.',
  );
  String get profileLoadError =>
      _t('تعذر تحميل بيانات حسابك', 'Could not load your account data');
  String profileMemberSince(String date) =>
      _t('عضو منذ $date', 'Member since $date');

  String get changePhotoAction => _t('تغيير الصورة', 'Change photo');
  String get avatarHint =>
      _t('JPG أو PNG — حتى 2 ميجابايت', 'JPG or PNG — up to 2MB');
  String get avatarErrorInvalidType => _t(
    'صيغة الصورة غير مدعومة. استخدم JPG أو PNG.',
    'Unsupported image format. Use JPG or PNG.',
  );
  String get avatarErrorTooLarge => _t(
    'حجم الصورة كبير جدًا. الحد الأقصى 2 ميجابايت.',
    'The image is too large. Maximum size is 2MB.',
  );
  String get avatarErrorGeneric => _t(
    'تعذر رفع الصورة. تأكد أن حجمها أقل من 2 ميجابايت.',
    'Could not upload the photo. Make sure it is under 2MB.',
  );

  String get profileSectionInfo =>
      _t('المعلومات الشخصية', 'Personal Information');
  String get addressLabel => _t('العنوان', 'Address');
  String get addressPlaceholder =>
      _t('الحي، الشارع...', 'Neighborhood, street...');
  String get cityLabel => _t('المدينة', 'City');
  String get cityPlaceholder => _t('نابلس', 'Nablus');
  String get genderLabel => _t('الجنس', 'Gender');
  String get genderOtherLabel => _t('غير ذلك', 'Other');
  String get saveChangesAction => _t('حفظ التغييرات', 'Save changes');
  String get cancelChangesAction => _t('إلغاء', 'Cancel');
  String get profileSaveSuccess =>
      _t('تم حفظ التغييرات بنجاح', 'Changes saved successfully');
  String get profileSaveError => _t(
    'تعذر حفظ التغييرات، حاول مرة أخرى',
    'Could not save changes, please try again',
  );
  String get profileSaveTimeout => _t(
    'استغرق الحفظ وقتًا أطول من المتوقع. حاول مرة أخرى.',
    'Saving took longer than expected. Please try again.',
  );
  String get profileSaveServiceUnavailable => _t(
    'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم أعد المحاولة.',
    'Could not reach the service. Check your connection and try again.',
  );

  String get profileSectionLanguage => _t('لغة الواجهة', 'Interface Language');
  String get profileLanguageDesc => _t(
    'تُطبَّق فوراً وتُحفظ لحسابك',
    'Applied immediately and saved to your account',
  );
  String get profileLanguageArOption => _t('العربية', 'العربية');
  String get profileLanguageEnOption => _t('English', 'English');
  String get profileLanguageSyncError => _t(
    'تم تغيير اللغة، لكن تعذر حفظها في حسابك.',
    'Language changed, but could not be saved to your account.',
  );

  String get profileSectionTheme => _t('المظهر', 'Appearance');
  String get profileThemeDesc =>
      _t('يُحفظ على هذا الجهاز فقط', 'Saved on this device only');
  String get themeSystemOption => _t('حسب النظام', 'System');
  String get themeLightOption => _t('فاتح', 'Light');
  String get themeDarkOption => _t('داكن', 'Dark');

  String get profileSectionPassword =>
      _t('تغيير كلمة المرور', 'Change Password');
  String get profilePasswordDesc => _t(
    'سيتم تسجيل خروجك من كل الأجهزة بعد تغيير كلمة المرور، وستحتاج لتسجيل الدخول من جديد.',
    'You will be signed out of all devices after changing your password, and will need to log in again.',
  );
  String get currentPasswordLabel =>
      _t('كلمة المرور الحالية', 'Current password');
  String get changePasswordAction => _t('تغيير كلمة المرور', 'Change password');
  String get passwordChangedMessage => _t(
    'تم تغيير كلمة المرور بنجاح. سيتم تحويلك لتسجيل الدخول من جديد...',
    'Password changed successfully. Redirecting you to log in again...',
  );
  String get wrongCurrentPasswordError =>
      _t('كلمة المرور الحالية غير صحيحة', 'Current password is incorrect');
  String get weakNewPasswordError => _t(
    'كلمة المرور الجديدة لا تفي بمتطلبات الأمان',
    'The new password does not meet the security requirements',
  );

  // Feedback
  String get feedbackTitle => _t('شاركنا رأيك', 'Share Your Feedback');
  String get feedbackSubtitle => _t(
    'رأيك يساعدنا على تحسين المنصة لجميع المستخدمين.',
    'Your feedback helps us improve MedOrbit for everyone.',
  );
  String get overallRatingLabel =>
      _t('تقييمك العام للتجربة', 'Your overall experience');
  String get overallRatingHint => _t(
    'اختر عدد النجوم الذي يعبّر عن تجربتك.',
    'Choose the number of stars that reflects your experience.',
  );
  String get serviceRatingsTitle => _t('تقييم الخدمات', 'Service ratings');
  String get serviceRatingsHint => _t(
    'يمكنك تقييم كل جانب بشكل اختياري.',
    'You can optionally rate each part of the experience.',
  );
  String get categoryChatbot =>
      _t('دقة المساعد الذكي', 'AI assistant accuracy');
  String get categoryClinics => _t('سهولة إيجاد العيادات', 'Finding clinics');
  String get categoryBooking => _t('سهولة حجز المواعيد', 'Appointment booking');
  String get categoryDesign => _t('تصميم المنصة', 'Platform design');
  String get recommendQuestion =>
      _t('هل تنصح باستخدام MedOrbit؟', 'Would you recommend MedOrbit?');
  String get recommendHint => _t(
    'هذا الاختيار اختياري، ويمكن الضغط عليه مرة أخرى لإلغائه.',
    'This is optional. Tap the selected choice again to clear it.',
  );
  String get yes => _t('نعم', 'Yes');
  String get no => _t('لا', 'No');
  String get commentLabel =>
      _t('تعليق إضافي (اختياري)', 'Additional comments (optional)');
  String get commentHint => _t(
    'أخبرنا بمزيد من التفاصيل عن تجربتك...',
    'Tell us more about your experience...',
  );
  String get commentHelper => _t('بحد أقصى 500 حرف.', 'Up to 500 characters.');
  String get feedbackSubmissionTitle =>
      _t('إرسال الملاحظات', 'Submit feedback');
  String get feedbackSubmissionHint => _t(
    'سيتم إرسال تقييمك باستخدام حسابك الحالي.',
    'Your feedback will be submitted using your current account.',
  );
  String get submitButton => _t('إرسال الملاحظات', 'Send feedback');
  String get submittingFeedback =>
      _t('جارٍ إرسال الملاحظات...', 'Submitting feedback...');
  String get feedbackSuccessTitle =>
      _t('شكرًا لملاحظاتك!', 'Thank you for your feedback!');
  String get feedbackSuccessHint => _t(
    'تم إرسال ملاحظاتك بنجاح.',
    'Your feedback has been submitted successfully.',
  );
  String get errorRatingRequired =>
      _t('يرجى اختيار التقييم العام', 'Please select an overall rating');
  String get feedbackErrorTitle =>
      _t('تعذر إرسال الملاحظات', 'Failed to submit feedback');
  String get feedbackErrorHint => _t(
    'بقيت إجاباتك محفوظة. تحقق من الاتصال ثم أعد المحاولة.',
    'Your answers are still here. Check your connection and try again.',
  );
  String get retryFeedbackButton => _t('إعادة الإرسال', 'Try again');
  String ratingValue(int value) => value == 0
      ? _t('لم يتم اختيار تقييم', 'Not rated')
      : _t('التقييم $value من 5', 'Rated $value out of 5');
  String selectStarRating(int value) =>
      _t('اختر $value من 5 نجوم', 'Select $value out of 5 stars');
  String get startOverButton => _t('البدء من جديد', 'Start Over');

  // Virtual Doctor
  String get virtualDoctorTitle => _t('الطبيب الافتراضي', 'Virtual Doctor');
  String get virtualDoctorTagline => _t(
    'تحدّث بشكل طبيعي — الطبيب يستمع ويجيب.',
    'Speak naturally — the doctor listens and replies.',
  );
  String get vdWelcomeTitle => _t('استشارة صوتية', 'Voice consultation');
  String get vdWelcomeBody => _t(
    'اضغط على زر الميكروفون في كل دور، تحدّث بوضوح، ثم أوقف التسجيل لإرسال إجابتك.',
    'For each turn, tap the microphone, speak clearly, then stop recording to send your answer.',
  );
  String get vdPrivacyTitle => _t('تذكير بالخصوصية', 'Privacy reminder');
  String get vdPrivacyHint => _t(
    'شارك فقط المعلومات الصحية التي تشعر بالارتياح لمناقشتها.',
    'Only share health information you are comfortable discussing.',
  );
  String get vdQuietTitle => _t('اختر مكانًا هادئًا', 'Find a quiet place');
  String get vdQuietHint => _t(
    'يساعد تقليل الضوضاء على تحويل كلامك إلى نص بدقة أكبر.',
    'Less background noise helps produce a clearer transcription.',
  );
  String get vdMicrophoneTitle => _t('إذن الميكروفون', 'Microphone permission');
  String get vdMicrophoneHint => _t(
    'سيطلب التطبيق الوصول إلى الميكروفون عند بدء الاستشارة لتسجيل إجاباتك.',
    'The app will request microphone access when the consultation starts so it can record your answers.',
  );
  String get vdSafetyTitle => _t('مهم قبل البدء', 'Before you begin');
  String get vdSafetyHint => _t(
    'هذه الاستشارة للإرشاد العام ولا تغني عن الرعاية الطبية. في الحالات الطارئة، اتصل بخدمات الطوارئ فورًا.',
    'This consultation offers general guidance and does not replace medical care. In an emergency, contact emergency services immediately.',
  );
  String get startConsultation => _t('ابدأ الاستشارة', 'Start Consultation');
  String get endConsultation => _t('إنهاء الاستشارة', 'End Consultation');
  String get vdConversationTitle => _t('المحادثة', 'Conversation');
  String get vdConversationHint => _t(
    'تظهر أسئلتك وإجابات الطبيب هنا.',
    'Your answers and the doctor’s responses appear here.',
  );
  String get vdNoMessages => _t(
    'تبدأ المحادثة بعد الاتصال.',
    'The conversation begins after connecting.',
  );
  String get vdConsultationStatus =>
      _t('حالة الاستشارة', 'Consultation status');
  String get vdElapsedTime => _t('المدة المنقضية', 'Elapsed time');
  String get vdConsultationProgress =>
      _t('مرحلة الاستشارة', 'Consultation phase');
  String get vdPhaseIntake => _t('جمع المعلومات', 'Patient intake');
  String get vdPhaseGreeting => _t('الشكوى الرئيسية', 'Chief complaint');
  String get vdPhaseInterviewing => _t('المقابلة الطبية', 'Clinical interview');
  String get vdPhaseComplete => _t('مكتملة', 'Complete');
  String vdPhaseLabel(String phase) => switch (phase) {
    'intake' => vdPhaseIntake,
    'greeting' => vdPhaseGreeting,
    'interviewing' => vdPhaseInterviewing,
    'complete' => vdPhaseComplete,
    _ => phase,
  };
  String get vdPatientInfoTitle => _t('بيانات المريض', 'Patient information');
  String get vdPatientName => _t('الاسم', 'Name');
  String get vdPatientAge => _t('العمر', 'Age');
  String get vdChiefComplaint => _t('الشكوى الرئيسية', 'Chief complaint');
  String get vdSummaryTitle => _t('ملخص الاستشارة', 'Consultation summary');
  String get vdUrgencyTitle => _t('درجة الاستعجال', 'Urgency level');
  String get vdUrgencyEmergency => _t('طارئة', 'Emergency');
  String get vdUrgencyUrgent => _t('عاجلة', 'Urgent');
  String get vdUrgencyRoutine => _t('اعتيادية', 'Routine');
  String get vdUrgencyUnknown => _t('غير معروفة', 'Unknown');
  String get vdTtsUnavailable => _t(
    'تعذّر تشغيل صوت الطبيب. ستستمر الاستشارة بالنص المكتوب.',
    'The doctor’s voice is unavailable. The consultation will continue in text.',
  );
  String get vdGeneratingReport =>
      _t('جارٍ إنشاء التقرير...', 'Generating report...');
  String get vdReportTitle => _t('تقرير الاستشارة', 'Consultation report');
  String get vdReportHint => _t(
    'يمكنك إنشاء ملف التقرير أو فتح الملف المحفوظ لهذه الاستشارة.',
    'Generate the report file or open the saved file for this consultation.',
  );
  String get vdRetryConsultation => _t('إعادة المحاولة', 'Try again');
  String get vdSessionErrorTitle =>
      _t('تعذّر بدء الاستشارة', 'Could not start consultation');
  String get vdDismissError => _t('إخفاء الخطأ', 'Dismiss error');
  String vdVoiceState(String state) =>
      _t('حالة الطبيب الصوتية: $state', 'Voice doctor status: $state');
  String vdElapsedValue(String value) =>
      _t('المدة المنقضية $value', 'Elapsed time $value');
  String get vdStateIdle => _t('جاهز', 'Ready');
  String get vdStateConnecting => _t('جارٍ الاتصال...', 'Connecting...');
  String get vdStateListening =>
      _t('اضغط على الميكروفون للتحدث', 'Tap the mic to speak');
  String get vdStateRecording => _t(
    'أستمع إليك... اضغط عند الانتهاء',
    "Listening... tap when you're done",
  );
  String get vdStateTranscribing =>
      _t('جارٍ تحويل الكلام...', 'Transcribing...');
  String get vdStateThinking =>
      _t('الطبيب يفكر...', 'The doctor is thinking...');
  String get vdStateSpeaking =>
      _t('الطبيب يتحدث...', 'The doctor is speaking...');
  String get vdStateComplete => _t('انتهت الاستشارة', 'Consultation complete');
  String get vdTapToSpeak => _t('اضغط للتحدث', 'Tap to speak');
  String get vdTapToStop => _t('اضغط للإيقاف', 'Tap to stop');
  String get vdSkipSpeech => _t('تخطي', 'Skip');
  String get vdYou => _t('أنت', 'You');
  String get vdDoctor => _t('الطبيب', 'Doctor');
  String get vdThinkingHint => _t(
    'قد يستغرق التحليل النهائي حتى دقيقة.',
    'The final analysis can take up to a minute.',
  );
  String get vdEmergencyTitle => _t('حالة طارئة', 'Emergency');
  String get vdDownloadReport =>
      _t('تحميل التقرير (PDF)', 'Download Report (PDF)');
  String get vdOpenReport => _t('فتح التقرير', 'Open Report');
  String get vdReportSaved => _t('تم حفظ التقرير', 'Report saved');
  String get vdReportUnavailable => _t(
    'خدمة التقارير غير متاحة مؤقتًا. الملخص أعلاه ما زال صالحًا.',
    'The report service is temporarily unavailable. The summary above still stands.',
  );
  String get vdRecommendedSpecialty =>
      _t('التخصص الموصى به', 'Recommended Specialty');
  String get vdMicDenied => _t(
    'لم يتم السماح بالوصول إلى الميكروفون',
    'Microphone permission denied',
  );
  String get vdMicDeniedHint => _t(
    'الاستشارة الصوتية تحتاج إلى الميكروفون. يمكنك السماح بذلك من إعدادات التطبيق.',
    'The voice consultation needs the microphone. You can allow it in app settings.',
  );
  String get vdOpenSettings => _t('فتح الإعدادات', 'Open Settings');
  String get vdErrNoSpeech => _t(
    'لم أسمع شيئًا. حاول مرة أخرى.',
    "I didn't catch that. Please try again.",
  );
  String get vdErrSttTimeout => _t(
    'استغرق التحويل وقتًا طويلاً. أعد المحاولة.',
    'Transcription timed out. Please try again.',
  );
  String get vdErrConnect => _t(
    'تعذر الاتصال بخدمة الطبيب الافتراضي.',
    'Could not reach the Virtual Doctor service.',
  );
  String get vdErrAiTimeout => _t(
    'استغرقت استجابة الطبيب وقتًا أطول من المتوقع. حاول مرة أخرى.',
    'The doctor’s response took longer than expected. Please try again.',
  );
  String get vdErrSessionExpired => _t(
    'انتهت جلسة الاستشارة. أنهِ الجلسة وابدأ استشارة جديدة.',
    'This consultation session has expired. End it and start a new consultation.',
  );
  String get vdErrMicUnavailable => _t(
    'تعذر تشغيل الميكروفون على هذا الجهاز.',
    'The microphone could not be started on this device.',
  );
  String get vdErrGeneric =>
      _t('حدث خطأ. حاول مرة أخرى.', 'Something went wrong. Please try again.');

  // Voice entitlement failures. Distinct from the transport/session codes
  // above: these are the backend enforcing the free-cooldown, quota, or
  // subscription rule, never a network or microphone fault, so "check your
  // connection" copy must never leak onto them.
  String get vdCooldownTitle => _t(
    'الاستشارة الصوتية غير متاحة مؤقتًا',
    'Voice consultation unavailable for now',
  );
  String get vdErrVoiceCooldown => _t(
    'استشارتك الصوتية المجانية القادمة غير متاحة بعد.',
    'Your next free voice consultation is not available yet.',
  );
  String get vdCooldownUntilPrefix =>
      _t('يمكنك المحاولة مرة أخرى بعد', 'You can try again after');
  String get vdSessionActiveTitle =>
      _t('استشارة أخرى نشطة', 'Another consultation active');
  String get vdErrVoiceSessionActive => _t(
    'لديك استشارة أخرى قيد التنفيذ بالفعل.',
    'You already have another consultation in progress.',
  );
  String get vdQuotaTitle =>
      _t('تم استهلاك استشاراتك المجانية', 'Free consultations used');
  String get vdErrFreeQuotaExhausted => _t(
    'استخدمت استشاراتك المجانية لهذه الفترة.',
    'You have used your free consultations for this period.',
  );
  String get vdSubscriptionRequiredTitle =>
      _t('يلزم اشتراك', 'Subscription required');
  String get vdErrSubscriptionRequired => _t(
    'هذه الميزة تتطلب اشتراك Pro.',
    'This feature requires a Pro subscription.',
  );
  String get vdSubscriptionInactiveTitle =>
      _t('الاشتراك غير نشط', 'Subscription inactive');
  String get vdErrSubscriptionInactive => _t(
    'اشتراكك غير نشط حاليًا.',
    'Your subscription is not currently active.',
  );
  String get vdErrEntitlementUnavailable => _t(
    'تعذّر التحقق من صلاحيتك حاليًا. حاول مرة أخرى.',
    'Could not verify your access right now. Please try again.',
  );

  /// Title to pair with [vdError] for the fatal-error screen. Falls back to
  /// [vdSessionErrorTitle] for every code that isn't an entitlement denial.
  String vdErrorTitle(String code) {
    return switch (code) {
      'voice_cooldown' => vdCooldownTitle,
      'voice_session_active' => vdSessionActiveTitle,
      'free_quota_exhausted' => vdQuotaTitle,
      'subscription_required' => vdSubscriptionRequiredTitle,
      'subscription_inactive' => vdSubscriptionInactiveTitle,
      _ => vdSessionErrorTitle,
    };
  }

  /// Maps a controller error code to display text.
  ///
  /// Unrecognized codes fall back to [vdErrGeneric] rather than being rendered
  /// verbatim: the controller encodes failures as short codes, so anything
  /// unmatched here is an internal string (or a raw server message) that has no
  /// business on a patient's screen.
  String vdError(String code) {
    final exact = switch (code) {
      'mic_denied' => vdMicDenied,
      'no_speech' => vdErrNoSpeech,
      'stt_timeout' => vdErrSttTimeout,
      'connect_failed' => vdErrConnect,
      'ai_unavailable' => aiServiceUnavailable,
      'ai_timeout' => vdErrAiTimeout,
      'ai_unreachable' => vdErrConnect,
      'session_expired' || 'session_unavailable' => vdErrSessionExpired,
      'voice_cooldown' => vdErrVoiceCooldown,
      'voice_session_active' => vdErrVoiceSessionActive,
      'free_quota_exhausted' => vdErrFreeQuotaExhausted,
      'subscription_required' => vdErrSubscriptionRequired,
      'subscription_inactive' => vdErrSubscriptionInactive,
      'entitlement_unavailable' => vdErrEntitlementUnavailable,
      'rate_limited' => chatRateLimited,
      'session_starting' => _t(
        'لا تزال الاستشارة قيد البدء. انتظر قليلًا ثم حاول الاستئناف.',
        'Your consultation is still starting. Wait a moment, then resume.',
      ),
      'end_failed' => voiceEndFailed,
      'ai_failed' ||
      'stt_failed' ||
      'engine_failed' ||
      'record_failed' ||
      'report_failed' => vdErrGeneric,
      _ => null,
    };
    if (exact != null) return exact;
    final normalized = code.toLowerCase();
    if (normalized.contains('session') &&
        (normalized.contains('expired') || normalized.contains('not found'))) {
      return vdErrSessionExpired;
    }
    if (normalized.contains('timeout') || normalized.contains('timed out')) {
      return vdErrAiTimeout;
    }
    if (normalized.contains('microphone unavailable')) {
      return vdErrMicUnavailable;
    }
    if (normalized.contains('connection') ||
        normalized.contains('network') ||
        normalized.contains('socket')) {
      return vdErrConnect;
    }
    return vdErrGeneric;
  }

  // Symptom Checker
  String get symptomCheckerTitle => _t('فحص الأعراض', 'Symptom Checker');
  String get symptomCheckerSubtitle => _t(
    'صف أعراضك لتحصل على اقتراح أولي للتخصص المناسب.',
    'Describe your symptoms to get an initial specialty suggestion.',
  );
  String get quickSymptomCheckerDescription => _t(
    'أداة سريعة للمساعدة في فهم أعراضك.',
    'A quick tool to help make sense of your symptoms.',
  );
  String get symptomCheckerDisclaimer => _t(
    'هذه الأداة للمساعدة المعلوماتية فقط ولا تغني عن استشارة الطبيب أو الطوارئ.',
    'This tool is for informational support only and does not replace medical advice or emergency care.',
  );
  String get symptomInputLabel => _t('أعراضك', 'Your symptoms');
  String get symptomInputHint => _t(
    'اكتب عرضًا واحدًا في كل سطر، مثال: صداع',
    'Type one symptom per line, e.g. headache',
  );
  String get symptomInputHelper => _t(
    'يمكنك الفصل بين الأعراض بسطر جديد أو بفاصلة.',
    'Separate symptoms with a new line or a comma.',
  );
  String get symptomCheckerSubmit => _t('فحص الأعراض', 'Check symptoms');
  String get symptomCheckerLoadingText =>
      _t('جارِ تحليل الأعراض...', 'Analyzing your symptoms...');
  String get symptomCheckerErrorMinSymptoms =>
      _t('يرجى إضافة عرض واحد على الأقل', 'Please add at least one symptom');
  String get symptomCheckerLoadError =>
      _t('تعذّر فحص الأعراض', 'Could not check symptoms');
  String get symptomCheckerTimeoutError => _t(
    'استغرق التحليل وقتًا أطول من المتوقع. حاول مرة أخرى.',
    'The analysis took longer than expected. Please try again.',
  );
  String get symptomCheckerServiceUnavailableError => _t(
    'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم أعد المحاولة.',
    'Could not reach the service. Check your connection and try again.',
  );
  String get symptomCheckerGenericError => _t(
    'حدث خطأ غير متوقع. حاول مرة أخرى.',
    'Something went wrong. Please try again.',
  );
  String get symptomEmergencyTitle =>
      _t('حالة طارئة محتملة', 'Possible emergency');
  String get symptomEmergencyMessage => _t(
    'توجّه فوراً إلى أقرب غرفة طوارئ أو اتصل بالإسعاف (الهلال الأحمر الفلسطيني 101). لا تنتظر.',
    'Go to the nearest emergency room or call an ambulance (Palestine Red Crescent Society, 101) immediately. Do not wait.',
  );
  String get symptomUrgentTitle =>
      _t('يُنصح بموعد عاجل', 'Urgent appointment recommended');
  String get symptomRoutineTitle =>
      _t('يُنصح بموعد عادي', 'Routine appointment recommended');
  String get symptomRecommendedSpecialty =>
      _t('التخصص المقترح', 'Suggested specialty');
  String get symptomRecommendationsLabel => _t('التوصيات', 'Recommendations');
  String get symptomCheckAnotherAction =>
      _t('فحص أعراض أخرى', 'Check other symptoms');

  // Drug Checker
  String get drugCheckerTitle => _t('فحص تداخل الأدوية', 'Drug Checker');
  String get drugCheckerSubtitle => _t(
    'أدخل أدويتك للاطلاع على تداخلات محتملة بينها.',
    'Enter your medications to check for possible interactions between them.',
  );
  String get quickDrugCheckerDescription => _t(
    'تحقّق من التداخلات المحتملة بين أدويتك.',
    'Check for possible interactions between your medications.',
  );
  String get drugCheckerDisclaimer => _t(
    'هذه الأداة للمساعدة المعلوماتية فقط ولا تغني عن استشارة الطبيب أو الصيدلي.',
    'This tool is for informational support only and does not replace medical advice from a doctor or pharmacist.',
  );
  String get drugInputLabel => _t('أدويتك', 'Your medications');
  String get drugInputHint => _t(
    'اكتب اسم دواء واحد في كل سطر، مثال: أسبرين',
    'Type one medication per line, e.g. Aspirin',
  );
  String get drugInputHelper => _t(
    'أدخل دواءين على الأقل. يمكنك الفصل بينها بسطر جديد أو بفاصلة.',
    'Enter at least 2 medications. Separate them with a new line or a comma.',
  );
  String get drugCommonMedications => _t('أدوية شائعة', 'Common medications');
  String get drugCheckerSubmit => _t('فحص التداخلات', 'Check interactions');
  String get drugCheckerLoadingText =>
      _t('جارِ فحص التداخلات الدوائية...', 'Checking drug interactions...');
  String get drugCheckerErrorMinMeds =>
      _t('يرجى إضافة دواءين على الأقل', 'Please add at least 2 medications');
  String get drugCheckerLoadError =>
      _t('تعذّر فحص التداخلات', 'Could not check interactions');
  String get drugCheckerTimeoutError => _t(
    'استغرق الفحص وقتًا أطول من المتوقع. حاول مرة أخرى.',
    'The check took longer than expected. Please try again.',
  );
  String get drugCheckerServiceUnavailableError => _t(
    'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم أعد المحاولة.',
    'Could not reach the service. Check your connection and try again.',
  );
  String get drugCheckerGenericError => _t(
    'حدث خطأ غير متوقع. حاول مرة أخرى.',
    'Something went wrong. Please try again.',
  );
  String get drugNoInteractionsTitle =>
      _t('لم يتم العثور على تداخلات', 'No interactions found');
  String get drugSeveritySevere => _t('شديد', 'Severe');
  String get drugSeverityModerate => _t('متوسط', 'Moderate');
  String get drugSeverityMild => _t('خفيف', 'Mild');
  String get drugSeverityUnknown => _t('غير معروف', 'Unknown');
  String get drugSevereWarning => _t(
    'تداخل خطير محتمل. لا تجمع بين هذه الأدوية دون استشارة طبيبك أو الصيدلي أولاً.',
    'A serious interaction was detected. Do not combine these medications without consulting your doctor or pharmacist first.',
  );
  String get drugCheckAnotherAction =>
      _t('فحص أدوية أخرى', 'Check other medications');

  // Report Summarizer
  String get reportSummarizerTitle => _t('ملخص التقارير', 'Report Summarizer');
  String get reportSummarizerSubtitle => _t(
    'الصق نص تقريرك الطبي للحصول على ملخص سريع بالعربية والإنجليزية.',
    'Paste your medical report text to get a quick summary in Arabic and English.',
  );
  String get quickReportSummarizerDescription => _t(
    'احصل على ملخص سريع لتقريرك الطبي.',
    'Get a quick summary of your medical report.',
  );
  String get reportSummaryDisclaimer => _t(
    'هذا الملخص للاسترشاد فقط ولا يغني عن استشارة الطبيب.',
    'This summary is for guidance only and does not replace professional medical advice.',
  );
  String get reportInputLabel => _t('نص التقرير', 'Report text');
  String get reportInputHint => _t(
    'الصق أو اكتب نص التقرير الطبي هنا...',
    'Paste or type the medical report text here...',
  );
  String get summarizeReport => _t('تلخيص التقرير', 'Summarize Report');
  String get reportSummaryResult => _t('نتيجة التلخيص', 'Summary result');
  String get arabicSummary => _t('الملخص بالعربية', 'Arabic summary');
  String get englishSummary => _t('الملخص بالإنجليزية', 'English summary');
  String get extractedTextPreview =>
      _t('معاينة النص المستخرج', 'Extracted text preview');
  String get reportSummaryEmptyError => _t(
    'يرجى إدخال نص تقرير كافٍ للتلخيص (20 حرفًا على الأقل).',
    'Please enter enough report text to summarize (at least 20 characters).',
  );
  String get reportSummarizerLoadError =>
      _t('تعذّر تلخيص التقرير', 'Could not summarize the report');
  String get reportSummarizerTimeoutError => _t(
    'استغرق التلخيص وقتًا أطول من المتوقع. حاول مرة أخرى.',
    'The summary took longer than expected. Please try again.',
  );
  String get reportSummarizerServiceUnavailableError => _t(
    'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم أعد المحاولة.',
    'Could not reach the service. Check your connection and try again.',
  );
  String get reportSummaryGenericError => _t(
    'حدث خطأ غير متوقع. حاول مرة أخرى.',
    'Something went wrong. Please try again.',
  );
  String get reportSummarizeAnotherAction =>
      _t('تلخيص تقرير آخر', 'Summarize another report');
  String get pasteOrUploadReport => _t(
    'الصق نص التقرير أدناه، أو ارفع تقريرًا بصيغة PDF أو صورة بدلاً من ذلك.',
    'Paste the report text below, or upload a PDF/image report instead.',
  );
  String get uploadReportFile =>
      _t('رفع تقرير PDF أو صورة', 'Upload PDF/Image Report');
  String selectedReportFile(String fileName) =>
      _t('الملف المحدد: $fileName', 'Selected file: $fileName');
  String get removeSelectedFile => _t('إزالة', 'Remove');
  String get supportedReportFiles => _t(
    'الصيغ المدعومة: PDF، PNG، JPG، JPEG (حتى 10 ميغابايت).',
    'Supported formats: PDF, PNG, JPG, JPEG (up to 10 MB).',
  );
  String get unsupportedReportFile => _t(
    'صيغة الملف غير مدعومة. يرجى رفع ملف PDF أو صورة (PNG أو JPG أو JPEG).',
    'Unsupported file type. Please upload a PDF or image (PNG, JPG, JPEG).',
  );
  String get reportFileTooLarge => _t(
    'حجم الملف كبير جدًا. الحد الأقصى هو 10 ميغابايت.',
    'The file is too large. Maximum size is 10 MB.',
  );
  String get reportFilePickFailed => _t(
    'تعذّر فتح أداة اختيار الملفات. حاول مرة أخرى.',
    'Could not open the file picker. Please try again.',
  );
  String get summarizeUploadedReport =>
      _t('تلخيص التقرير المرفوع', 'Summarize Uploaded Report');

  // My Reports
  String get myReportsTitle => _t('تقاريري', 'My Reports');
  String get myReportsSubtitle => _t(
    'اطّلع على ملخصات تقاريرك الطبية في مكان واحد.',
    'View your medical report summaries in one place.',
  );
  String get quickMyReportsDescription => _t(
    'استعرض تقاريرك وملخصاتها السابقة.',
    'Browse your past reports and summaries.',
  );
  String get myReportsEmptyTitle => _t('لا توجد تقارير بعد', 'No reports yet');
  String get myReportsEmptyMessage => _t(
    'ستظهر هنا ملخصات التقارير التي تنشئها عبر ميزة تلخيص التقارير.',
    'Summaries you create with Report Summarizer will show up here.',
  );
  String get myReportsLoadError =>
      _t('تعذّر تحميل التقارير', 'Could not load reports');
  String get myReportTypeSummary => _t('ملخص تقرير', 'Report Summary');
  String get myReportTypeGenerated => _t('تقرير مُنشأ', 'Generated Report');
  String get myReportTypeVirtualDoctor =>
      _t('تقرير الطبيب الافتراضي', 'Virtual Doctor Report');
  String get myReportViewDetails => _t('عرض التفاصيل', 'View details');
  String get myReportHideDetails => _t('إخفاء التفاصيل', 'Hide details');
  String get myReportDownloadAction => _t('تنزيل', 'Download');

  // Discovery — common
  String get discoveryFiltersButton => _t('التصفية', 'Filters');
  String get discoveryApplyFiltersButton =>
      _t('تطبيق التصفية', 'Apply filters');
  String get discoveryAnyOption => _t('الكل', 'Any');
  String get discoveryDetailsAction => _t('التفاصيل', 'Details');
  String get discoveryLoadMoreButton => _t('تحميل المزيد', 'Load more');
  String get discoveryNoActiveFilters =>
      _t('لا توجد عوامل تصفية نشطة', 'No active filters');
  String get discoverySearchActiveLabel => _t('البحث مفعّل', 'Search active');
  String discoveryFilterSummarySpecialty(String value) =>
      _t('التخصص: $value', 'Specialty: $value');
  String discoveryFilterSummaryRegion(String value) =>
      _t('المنطقة: $value', 'Region: $value');
  String discoveryFilterSummaryMinRating(String value) =>
      _t('تقييم $value فأكثر', 'Rating $value+');
  String get discoveryFilterSummaryFeeActive =>
      _t('عامل تصفية الرسوم مفعّل', 'Fee filter active');
  String discoveryFilterSummaryTypeValue(String label) =>
      _t('النوع: $label', 'Type: $label');
  String discoveryFilterSummaryService(String value) =>
      _t('الخدمة: $value', 'Service: $value');
  String discoveryFilterSummaryInsurance(String value) =>
      _t('التأمين: $value', 'Insurance: $value');
  String get discoveryFilterSummaryNearby => _t('قريب', 'Nearby');
  String consultationFeeValue(String fee) => _t('$fee شيكل', '$fee ILS');
  String consultationDurationValue(int minutes) =>
      _t('$minutes د', '$minutes min');
  String yearsExperienceValue(int years) => _t('$years سنة', '$years years');

  // Discovery — doctor directory
  String get doctorDirectoryScreenTitle =>
      _t('دليل الأطباء', 'Doctor directory');
  String get doctorDirectoryTitle => _t('ابحث عن طبيب', 'Find a doctor');
  String get doctorDirectorySubtitle => _t(
    'تصفّح الأطباء المدرجين من قبل المرافق الصحية في محيط نابلس.',
    'Browse doctors listed by healthcare facilities around Nablus.',
  );
  String get searchDoctorsLabel => _t('البحث عن طبيب', 'Search doctors');
  String get searchDoctorsFieldHint =>
      _t('الاسم أو التخصص', 'Name or specialty');
  String get doctorFilterSpecialtyLabel => _t('التخصص', 'Specialty');
  String get doctorSpecialtyFilterAll => _t('كل التخصصات', 'All specialties');
  String get doctorFilterRegionLabel => _t('المنطقة', 'Region');
  String get doctorFilterMinRatingLabel =>
      _t('الحد الأدنى للتقييم', 'Minimum rating');
  String get doctorFilterMinFeeLabel => _t('الحد الأدنى للرسوم', 'Minimum fee');
  String get doctorFilterMaxFeeLabel => _t('الحد الأقصى للرسوم', 'Maximum fee');
  String get doctorFilterFeeRangeError => _t(
    'يجب أن يكون الحد الأقصى أكبر من أو يساوي الحد الأدنى',
    'Maximum must be at least minimum',
  );
  String get doctorFilterSheetTitle => _t('تصفية الأطباء', 'Filter doctors');
  String doctorResultsCount(int count) =>
      _t('$count نتيجة طبيب', '$count doctor result${count == 1 ? '' : 's'}');
  String get doctorLoadingDoctors =>
      _t('جارٍ تحميل الأطباء...', 'Loading doctors...');
  String get doctorEmptyTitle =>
      _t('لم يتم العثور على أطباء', 'No doctors found');
  String get doctorEmptyHint => _t(
    'جرّب إزالة عوامل التصفية أو استخدام كلمة بحث مختلفة.',
    'Try clearing filters or using a different search.',
  );
  String get doctorAcceptingPatients =>
      _t('يستقبل مرضى جدد', 'Accepting patients');
  String get doctorAvailabilityNotConfirmed =>
      _t('التوفر غير مؤكد', 'Availability not confirmed');
  String get doctorNotAcceptingPatients =>
      _t('لا يستقبل مرضى جدد', 'Not accepting patients');
  String get doctorRecommendedTitle =>
      _t('أطباء مقترحون لك', 'Recommended doctors');
  String get doctorRecommendedSubtitle =>
      _t('بناءً على نشاطك واهتماماتك', 'Based on your activity and interests');
  String get doctorRecommendedUnavailable => _t(
    'تعذر تحميل الاقتراحات المخصصة حالياً',
    'Personalized suggestions are unavailable right now',
  );
  String get doctorReasonFollowed =>
      _t('لأنك تتابع هذا الطبيب', 'Because you follow this doctor');
  String get doctorReasonSpecialty =>
      _t('بناءً على اهتمامك بهذا التخصص', 'Based on your specialty interest');
  String get doctorReasonTrending => _t('طبيب شائع', 'Popular doctor');
  String get doctorReasonRecent => _t('اكتشاف الأطباء', 'Doctor discovery');
  String get doctorFallbackName => _t('طبيب', 'Doctor');
  String get clinicFallbackName => _t('عيادة', 'Clinic');
  String get healthcareFacilityFallbackName =>
      _t('منشأة صحية', 'Healthcare facility');

  // Discovery — doctor detail
  String get doctorDetailTitle => _t('تفاصيل الطبيب', 'Doctor details');
  String get doctorDetailLoadErrorTitle =>
      _t('تعذر تحميل بيانات الطبيب', 'Could not load doctor');
  String get doctorDetailNotFoundTitle =>
      _t('الطبيب غير موجود', 'Doctor not found');
  String get doctorDetailNotFoundHint => _t(
    'قد لا يكون هذا الطبيب متاحًا بعد الآن.',
    'This doctor may no longer be available.',
  );
  String get doctorLoadingDetails =>
      _t('جارٍ تحميل بيانات الطبيب...', 'Loading doctor details...');
  String get doctorSectionEducation => _t('التعليم', 'Education');
  String get doctorSectionEducationEmpty =>
      _t('لا توجد تفاصيل تعليمية مدرجة.', 'No education details are listed.');
  String get doctorSectionCertifications => _t('الشهادات', 'Certifications');
  String get doctorSectionCertificationsEmpty =>
      _t('لا توجد شهادات مدرجة.', 'No certifications are listed.');
  String get doctorSectionProfessionalDetails =>
      _t('التفاصيل المهنية', 'Professional details');
  String get doctorSectionProfessionalDetailsEmpty => _t(
    'لا توجد تفاصيل مهنية إضافية.',
    'No additional professional details are listed.',
  );
  String doctorInfoExperience(int years) =>
      _t('الخبرة: $years سنة', 'Experience: $years years');
  String doctorInfoConsultationFee(String fee) =>
      _t('رسوم الاستشارة: $fee شيكل', 'Consultation fee: $fee ILS');
  String doctorInfoConsultationDuration(int minutes) => _t(
    'مدة الاستشارة: $minutes دقيقة',
    'Consultation duration: $minutes min',
  );
  String doctorInfoRating(String rating) =>
      _t('التقييم: $rating', 'Rating: $rating');
  String doctorInfoRatingWithCount(String rating, int count) =>
      _t('التقييم: $rating ($count تقييم)', 'Rating: $rating ($count ratings)');
  String doctorInfoMedicalLicense(String value) =>
      _t('رقم الترخيص الطبي: $value', 'Medical license: $value');
  String get doctorSectionAssociatedClinics =>
      _t('العيادات المرتبطة', 'Associated clinics');
  String get doctorSectionAssociatedClinicsEmpty =>
      _t('لا توجد عيادات مرتبطة مدرجة.', 'No associated clinics are listed.');
  String get doctorSectionReviews => _t('التقييمات', 'Reviews');
  String get doctorSectionReviewsEmpty =>
      _t('لا توجد تقييمات مدرجة.', 'No reviews are listed.');
  String get doctorReviewNoComment =>
      _t('لا يوجد تعليق مكتوب', 'No written comment');
  String get doctorReviewAnonymous => _t('مريض', 'Patient');
  String get doctorInfoSubSpecialty => _t('تخصص فرعي', 'Sub-specialty');
  String get doctorInfoExpertise => _t('مجالات الخبرة', 'Areas of expertise');
  String get doctorInfoInterests =>
      _t('الاهتمامات المهنية', 'Professional interests');
  String get doctorInfoLanguages => _t('اللغات', 'Languages');
  String get doctorBookingUnavailableNotAccepting => _t(
    'هذا الطبيب لا يستقبل مواعيد جديدة حاليًا.',
    'This doctor is not accepting new appointments right now.',
  );
  String get doctorBookingUnavailableUnknown => _t(
    'حالة استقبال المواعيد غير مؤكدة لهذا الطبيب. تواصل مع العيادة للتأكيد.',
    "This doctor's availability is not confirmed. Contact the clinic to confirm.",
  );
  String get doctorAvailabilityTitle => _t('الأوقات المتاحة', 'Availability');
  String get doctorChooseDateAction => _t('اختر التاريخ', 'Choose date');
  String get doctorAvailabilityLoadError =>
      _t('تعذر تحميل الأوقات المتاحة', 'Could not load availability');
  String get doctorAvailabilityChooseDateHint => _t(
    'اختر تاريخًا لعرض الأوقات المتاحة.',
    'Choose a date to view available times.',
  );
  String get doctorAvailabilityNoneForDate => _t(
    'لا توجد أوقات متاحة لهذا التاريخ.',
    'No times are available for this date.',
  );

  // Discovery — clinic discovery
  String get clinicDiscoveryTitle =>
      _t('ابحث عن رعاية صحية قريبة', 'Find healthcare nearby');
  String get clinicDiscoverySubtitle => _t(
    'ابحث عن عيادات ومستشفيات وصيدليات ومختبرات موثّقة ومجتمعية في محيط نابلس.',
    'Search verified and community-listed clinics, hospitals, pharmacies, and labs around Nablus.',
  );
  String get searchClinicsLabel => _t('البحث عن عيادة', 'Search clinics');
  String get searchClinicsFieldHint =>
      _t('عيادة أو خدمة أو منطقة', 'Clinic, service, region');
  String get discoveryViewModeList => _t('قائمة', 'List');
  String get discoveryViewModeMap => _t('خريطة', 'Map');
  String get nearbySearchTitle => _t('بحث قريب', 'Nearby search');
  String get nearbySearchSubtitleInactive => _t(
    'استخدم GPS أو نقطة على الخريطة أو حيًا تقريبيًا في نابلس.',
    'Use GPS, a map point, or an approximate Nablus-area district.',
  );
  String nearbySearchSubtitleActive(String source, bool approximate) => _t(
    'باستخدام موقع $source${approximate ? ' · تقريبي' : ''}. الإحداثيات الدقيقة غير محفوظة.',
    'Using $source location${approximate ? ' · approximate' : ''}. Exact coordinates are not stored.',
  );
  String get locationSourceGps => _t('GPS', 'GPS');
  String get locationSourceManualMap =>
      _t('نقطة يدوية على الخريطة', 'manual map');
  String get locationSourceManualDistrict =>
      _t('حي تقريبي', 'approximate district');
  String get locationSourceNone => _t('لا شيء', 'none');
  String get clinicDiscoveryScreenTitle =>
      _t('اكتشاف العيادات', 'Clinic discovery');
  String get useGpsButton => _t('استخدام GPS', 'Use GPS');
  String get chooseLocationButton => _t('اختيار الموقع', 'Choose location');
  String get exitNearbyButton => _t('الخروج من البحث القريب', 'Exit nearby');
  String radiusKmValue(String value) => _t('$value كم', '$value km');
  String get pickMapPointHint => _t(
    'اضغط على الخريطة لاختيار نقطة بحث يدوية قريبة.',
    'Tap the map to choose a manual nearby search point.',
  );
  String clinicResultsCount(int count) =>
      _t('$count نتيجة عيادة', '$count clinic result${count == 1 ? '' : 's'}');
  String get clinicLoadingClinics =>
      _t('جارٍ تحميل العيادات...', 'Loading clinics...');
  String get clinicCouldNotLoadClinics =>
      _t('تعذر تحميل العيادات', 'Could not load clinics');
  String get clinicEmptyTitle =>
      _t('لم يتم العثور على عيادات', 'No clinics found');
  String get clinicEmptyHint => _t(
    'جرّب إزالة عوامل التصفية أو اختيار موقع قريب آخر.',
    'Try clearing filters or choosing another nearby location.',
  );
  String get clinicNoMappedResults =>
      _t('لا توجد نتائج عيادات على الخريطة.', 'No mapped clinic results.');
  String get clinicFilterSheetTitle => _t('تصفية العيادات', 'Filter clinics');
  String get clinicFilterFacilityType => _t('نوع المنشأة', 'Facility type');
  String get clinicFilterAllTypes => _t('الكل', 'All');
  String get clinicFilterAnyRegion => _t('أي منطقة', 'Any region');
  String get clinicFilterService => _t('الخدمة', 'Service');
  String get clinicFilterAnyService => _t('أي خدمة', 'Any service');
  String get clinicFilterInsurance => _t('التأمين', 'Insurance');
  String get clinicFilterAnyInsurance => _t('أي تأمين', 'Any insurance');

  // Discovery — clinic types / verification
  String clinicTypeLabelFor(String? type) =>
      switch ((type ?? '').trim().toLowerCase()) {
        'clinic' => _t('عيادة', 'Clinic'),
        'pharmacy' => _t('صيدلية', 'Pharmacy'),
        'hospital' => _t('مستشفى', 'Hospital'),
        'laboratory' => _t('مختبر', 'Laboratory'),
        'dental' => _t('أسنان', 'Dental'),
        'radiology' => _t('أشعة', 'Radiology'),
        'emergency' => _t('طوارئ', 'Emergency'),
        _ => _t('منشأة', 'Facility'),
      };
  String get clinicVerifiedLabel => _t('موثّقة', 'Verified');
  String get clinicPendingVerificationLabel =>
      _t('قيد التحقق', 'Pending verification');
  String get clinicUnverifiedLabel =>
      _t('غير موثّقة / غير معروفة', 'Unverified / unknown');

  // Discovery — clinic detail
  String get clinicDetailTitle => _t('تفاصيل العيادة', 'Clinic details');
  String get clinicDetailLoadErrorTitle =>
      _t('تعذر تحميل بيانات العيادة', 'Could not load clinic');
  String get clinicDetailNotFoundTitle =>
      _t('العيادة غير موجودة', 'Clinic not found');
  String get clinicDetailNotFoundHint => _t(
    'قد لا تكون هذه العيادة متاحة بعد الآن.',
    'This clinic may no longer be available.',
  );
  String get clinicLoadingDetails =>
      _t('جارٍ تحميل بيانات العيادة...', 'Loading clinic details...');
  String get clinicVerificationDisclaimer => _t(
    'قد لا تكون ساعات العمل وتفاصيل المنشأة موثّقة. تواصل مع المنشأة قبل الزيارة.',
    'Hours and facility details may not be verified. Contact the facility before visiting.',
  );
  String get clinicMapSectionTitle => _t('الخريطة', 'Map');
  String get clinicMapRoutingNote => _t(
    'التوجيه والاتجاهات غير مفعّلة في هذه المرحلة.',
    'Routing and directions are not enabled in this phase.',
  );
  String get clinicNoCoordinates => _t(
    'لا توجد إحداثيات خريطة مدرجة لهذه العيادة.',
    'No map coordinates are listed for this clinic.',
  );
  String get clinicsNoCoordinates => _t(
    'لا توجد إحداثيات خريطة مدرجة لهذه العيادات.',
    'No map coordinates are listed for these clinics.',
  );
  String get clinicContactSectionTitle =>
      _t('التواصل والموقع', 'Contact and location');
  String get clinicNoContactDetails =>
      _t('لا توجد تفاصيل تواصل مدرجة.', 'No contact details are listed.');
  String get clinicActionsDisabledNote => _t(
    'إجراءات الهاتف والموقع الإلكتروني غير مفعّلة في هذه المرحلة.',
    'Phone and website actions are not enabled in this phase.',
  );
  String get clinicRegionLabel => _t('المنطقة', 'Region');
  String get clinicPhoneLabel => _t('الهاتف', 'Phone');
  String get clinicWebsiteLabel => _t('الموقع الإلكتروني', 'Website');
  String get clinicServicesTitle => _t('الخدمات', 'Services');
  String get clinicInsuranceTitle =>
      _t('التأمين المقبول', 'Insurance accepted');
  String get clinicNoneListed => _t('لا يوجد شيء مدرج.', 'None listed.');
  String get clinicHoursTitle => _t('ساعات العمل المدرجة', 'Listed hours');
  String get clinicHoursSubtitle => _t(
    'ساعات العمل مقدَّمة من العيادة وقد تتغيّر. تواصل مع العيادة للتأكد قبل الزيارة.',
    'Hours are provided by the clinic and may change. Contact the clinic to confirm before visiting.',
  );
  String get clinicHoursClosed => _t('مغلق', 'Closed');
  String get clinicNoHoursListed =>
      _t('لا توجد ساعات عمل مدرجة.', 'No operating hours are listed.');
  String get clinicDoctorsSectionTitle =>
      _t('الأطباء في هذه المنشأة', 'Doctors at this facility');
  String get clinicNoDoctorsListed => _t(
    'لا يوجد أطباء مدرجون لهذه المنشأة.',
    'No doctors are listed for this facility.',
  );
  String clinicDoctorRatingLabel(String rating) =>
      _t('التقييم $rating', 'Rating $rating');
  String weekdayLabel(String key) => switch (key.trim().toLowerCase()) {
    'monday' => _t('الاثنين', 'Monday'),
    'tuesday' => _t('الثلاثاء', 'Tuesday'),
    'wednesday' => _t('الأربعاء', 'Wednesday'),
    'thursday' => _t('الخميس', 'Thursday'),
    'friday' => _t('الجمعة', 'Friday'),
    'saturday' => _t('السبت', 'Saturday'),
    'sunday' => _t('الأحد', 'Sunday'),
    _ => key,
  };

  // Discovery — map
  String get mapFitMarkersTooltip => _t('احتواء جميع العلامات', 'Fit markers');
  String get mapRecenterTooltip =>
      _t('إعادة التمركز إلى موقعك', 'Recenter to your location');
  String get mapUserLocationMarkerLabel =>
      _t('علامة موقعك', 'User location marker');
  String mapPlaceMarkerLabel(String label) =>
      _t('علامة $label', '$label marker');
  String get mapDoctorMarkerLabel => _t('علامة طبيب', 'Doctor marker');
  String get mapUnknownMarkerLabel => _t('علامة موقع', 'Place marker');
  String get mapFoundationTitle => _t('أساس الخريطة', 'Map foundation');
  String get locationStateSectionTitle => _t('حالة الموقع', 'Location state');
  String get noLocationSelected =>
      _t('لم يتم تحديد موقع', 'No location selected');
  String get locationPrecisionApproximate => _t('تقريبي', 'Approximate');
  String get locationPrecisionExact => _t('دقيق', 'Exact');
  String locationStatusSourceLine(String status, String source) => _t(
    'الحالة: $status · المصدر: $source',
    'Status: $status · Source: $source',
  );
  String get selectManualMapPointHint => _t(
    'اضغط على الخريطة لتحديد نقطة يدويًا.',
    'Tap the map to select a manual point.',
  );
  String get pickOnMapButton => _t('اختيار من الخريطة', 'Pick on map');
  String get moreOptionsButton => _t('المزيد من الخيارات', 'More options');
  String get clearLocationButton => _t('مسح', 'Clear');

  // Discovery — location picker sheet
  String get chooseLocationTitle => _t('اختر الموقع', 'Choose location');
  String get chooseLocationSubtitle => _t(
    'استخدم GPS، اختر نقطة، أو اختر حيًا تقريبيًا في نابلس.',
    'Use GPS, select a point, or choose an approximate Nablus-area district.',
  );
  String get useCurrentLocationButton =>
      _t('استخدام الموقع الحالي', 'Use current location');
  String get selectPointOnMapButton =>
      _t('اختيار نقطة على الخريطة', 'Select point on map');
  String get approximateDistrictTitle =>
      _t('حي تقريبي', 'Approximate district');
  String get districtApproximateSuffix => _t('تقريبي', 'approximate');
  String get locationPrivacyNote => _t(
    'يُستخدم الموقع لعرض النتائج القريبة. لا يحفظ التطبيق الموقع الدقيق. قد تصل مزودات الخرائط أو التوجيه الخارجية إلى الموقع لاحقًا عند استخدام تلك الإجراءات.',
    'Location is used for nearby results. Exact location is not persisted by the mobile app. External map or routing providers may receive location later when those actions are used.',
  );
  String get appSettingsButton => _t('إعدادات التطبيق', 'App settings');
  String get locationSettingsButton =>
      _t('إعدادات الموقع', 'Location settings');

  // Discovery — location error states (must stay distinct per state)
  String get locationServiceDisabledMessage => _t(
    'خدمات الموقع متوقفة. فعّلها أو اختر موقعًا يدويًا.',
    'Location services are off. Turn them on or choose a manual location.',
  );
  String get locationDeniedMessage => _t(
    'تم رفض إذن الموقع. يمكنك إعادة المحاولة أو اختيار موقع يدوي.',
    'Location permission was denied. You can retry or choose a manual location.',
  );
  String get locationDeniedForeverMessage => _t(
    'تم حظر إذن الموقع. افتح إعدادات التطبيق أو اختر موقعًا يدويًا.',
    'Location permission is blocked. Open app settings or choose a manual location.',
  );
  String get locationTimeoutMessage => _t(
    'استغرق تحديد موقعك وقتًا طويلاً. أعد المحاولة أو اختر موقعًا يدويًا.',
    'Finding your location took too long. Try again or choose a manual location.',
  );
  String get locationUnavailableMessage => _t(
    'تعذر تحديد موقعك. أعد المحاولة أو اختر موقعًا يدويًا.',
    'Your location could not be determined. Try again or choose a manual location.',
  );
  String get locationUnexpectedMessage => _t(
    'حدث خطأ أثناء تحديد موقعك. أعد المحاولة أو اختر موقعًا يدويًا.',
    'Something went wrong while finding your location. Try again or choose a manual location.',
  );

  /// Maps a [LocationFailureCode] name (e.g. `serviceDisabled`, `denied`,
  /// `deniedForever`, `timeout`, `unavailable`, `unexpected`) to a distinct,
  /// user-facing message. Each failure state keeps its own wording so a
  /// denied permission is never confused with a timed-out GPS fix.
  String locationErrorForCode(String? code) => switch (code) {
    'serviceDisabled' => locationServiceDisabledMessage,
    'denied' => locationDeniedMessage,
    'deniedForever' => locationDeniedForeverMessage,
    'timeout' => locationTimeoutMessage,
    'unavailable' => locationUnavailableMessage,
    _ => locationUnexpectedMessage,
  };

  // ─── Doctor Application ────────────────────────────────────────────────
  String get doctorApplicationTitle =>
      _t('طلب الانضمام كطبيب', 'Doctor application');
  String get doctorApplicationQuickActionLabel =>
      _t('طلب الانضمام كطبيب', 'Apply to become a doctor');
  String get doctorApplicationQuickActionDescription => _t(
    'يمكن للمرضى الموثّقين تقديم مؤهلاتهم لمراجعتها من قبل الإدارة.',
    'Verified patients can submit their credentials for admin review.',
  );
  String get doctorApplicationIntroTitle =>
      _t('انضم إلى فريق الأطباء في MedOrbit', 'Join MedOrbit as a doctor');
  String get doctorApplicationIntroBody => _t(
    'أرسل مؤهلاتك المهنية ليراجعها فريق الإدارة. بعد الموافقة يتحول حسابك إلى حساب طبيب.',
    'Submit your professional credentials for the admin team to review. Once approved, your account becomes a doctor account.',
  );
  String get doctorApplicationLoading =>
      _t('جارٍ تحميل حالة الطلب...', 'Loading your application status…');
  String get doctorApplicationLoadErrorTitle =>
      _t('تعذّر تحميل طلب الانضمام', 'Could not load your application');
  String get doctorApplicationPatientOnlyTitle =>
      _t('متاح لحسابات المرضى فقط', 'Available to patient accounts only');
  String get doctorApplicationPatientOnlyBody => _t(
    'صفحة طلب الانضمام كطبيب متاحة لحسابات المرضى الموثّقة فقط.',
    'The doctor application is available only to verified patient accounts.',
  );

  // Form
  String get doctorApplicationFormTitle =>
      _t('طلب الانضمام', 'Application details');
  String get doctorApplicationNewFormTitle =>
      _t('تقديم طلب جديد', 'Submit a new application');
  String get doctorApplicationFormIntro => _t(
    'الحقول المميّزة مطلوبة. باقي الحقول اختيارية وتساعد المراجعين على تقييم طلبك.',
    'Required fields are marked. The rest are optional and help reviewers assess your application.',
  );
  String get doctorApplicationOptional => _t('اختياري', 'Optional');
  String get doctorApplicationSpecialtyLabel => _t('التخصص', 'Specialty');
  String get doctorApplicationSpecialtySelect =>
      _t('اختر التخصص', 'Select a specialty');
  String get doctorApplicationSpecialtyRequired =>
      _t('اختر التخصص', 'Select a specialty');
  String get doctorApplicationSpecialtyEmpty => _t(
    'لا تتوفر قائمة تخصصات حالياً. حاول لاحقاً.',
    'No specialties are available right now. Please try again later.',
  );
  String get doctorApplicationLicenseLabel =>
      _t('رقم الترخيص الطبي', 'Medical license number');
  String get doctorApplicationLicenseHint =>
      _t('كما هو مدوّن في ترخيصك', 'As written on your license');
  String get doctorApplicationLicenseRequired =>
      _t('أدخل رقم الترخيص الطبي', 'Enter your medical license number');
  String get doctorApplicationSubSpecialtyLabel =>
      _t('التخصص الفرعي', 'Sub-specialty');
  String get doctorApplicationExperienceLabel =>
      _t('سنوات الخبرة', 'Years of experience');
  String get doctorApplicationExperienceInvalid =>
      _t('أدخل رقماً صحيحاً', 'Enter a whole number');
  String get doctorApplicationExperienceRange =>
      _t('أدخل قيمة بين 0 و 80', 'Enter a value between 0 and 80');
  String get doctorApplicationEducationLabel => _t('التعليم', 'Education');
  String get doctorApplicationCertificationsLabel =>
      _t('الشهادات', 'Certifications');
  String get doctorApplicationOnePerLineHint =>
      _t('أدخل عنصراً واحداً في كل سطر', 'Enter one item per line');
  String get doctorApplicationBioLabel => _t('نبذة مهنية', 'Professional bio');
  String get doctorApplicationPrivacyNote => _t(
    'لا تضع كلمات مرور أو بيانات مرضى أو مستندات حساسة في هذا النموذج.',
    'Do not put passwords, patient data, or sensitive documents in this form.',
  );
  String get doctorApplicationSubmit => _t('إرسال الطلب', 'Submit application');
  String get doctorApplicationSubmitting =>
      _t('جارٍ الإرسال...', 'Submitting…');
  String get doctorApplicationSubmitSuccess => _t(
    'تم إرسال طلبك للمراجعة.',
    'Your application has been submitted for review.',
  );

  // Status
  String get doctorApplicationStatusHeading =>
      _t('حالة الطلب', 'Application status');
  String get doctorApplicationStatusPending =>
      _t('قيد المراجعة', 'Under review');
  String get doctorApplicationStatusApproved => _t('تمت الموافقة', 'Approved');
  String get doctorApplicationStatusRejected =>
      _t('بحاجة إلى تعديل', 'Needs changes');
  String get doctorApplicationStatusWithdrawn => _t('تم السحب', 'Withdrawn');
  String get doctorApplicationStatusUnknown =>
      _t('حالة غير معروفة', 'Status unavailable');
  String get doctorApplicationPendingBody => _t(
    'سيراجع فريق الإدارة طلبك. يمكنك سحبه ما دام قيد المراجعة.',
    'The admin team will review your application. You can withdraw it while it is still under review.',
  );
  String get doctorApplicationApprovedBody => _t(
    'تمت الموافقة على طلبك. سجّل الخروج ثم الدخول من جديد لتفعيل حساب الطبيب.',
    'Your application was approved. Sign out and sign in again to activate your doctor account.',
  );
  String get doctorApplicationRejectedBody => _t(
    'راجع سبب التعديل المطلوب، ثم يمكنك تقديم طلب جديد.',
    'Review the requested changes below, then you can submit a new application.',
  );
  String get doctorApplicationWithdrawnBody => _t(
    'تم سحب طلبك. يمكنك تقديم طلب جديد في أي وقت.',
    'Your application was withdrawn. You can submit a new application any time.',
  );
  String get doctorApplicationUnknownBody => _t(
    'تعذّر عرض حالة هذا الطلب. حدّث الصفحة أو حاول لاحقاً.',
    'This application status could not be shown. Refresh or try again later.',
  );
  String get doctorApplicationSubmittedOn =>
      _t('تاريخ التقديم', 'Submitted on');
  String get doctorApplicationReviewedOn => _t('تاريخ المراجعة', 'Reviewed on');
  String get doctorApplicationRejectionReason => _t('سبب التعديل', 'Reason');
  String doctorApplicationYearsValue(int years) =>
      _t('$years سنة', '$years years');
  String get doctorApplicationSignInAgain =>
      _t('تسجيل الدخول من جديد', 'Sign in again');

  // Withdraw
  String get doctorApplicationWithdraw =>
      _t('سحب الطلب', 'Withdraw application');
  String get doctorApplicationWithdrawTitle =>
      _t('سحب الطلب الحالي؟', 'Withdraw this application?');
  String get doctorApplicationWithdrawBody => _t(
    'سيتم سحب طلبك المعلّق. سيبقى ضمن السجل، ويمكنك تقديم طلب جديد لاحقاً. لن يتم حذف أي شيء.',
    'Your pending application will be withdrawn. It stays in your history, and you can submit a new application later. Nothing is deleted.',
  );
  String get doctorApplicationWithdrawConfirm => _t('سحب الطلب', 'Withdraw');
  String get doctorApplicationWithdrawSuccess =>
      _t('تم سحب طلبك.', 'Your application has been withdrawn.');

  // History
  String get doctorApplicationHistoryTitle =>
      _t('سجل الطلبات', 'Application history');

  /// Safe localized copy for a Doctor Application backend/transport error
  /// code. Never renders a raw backend message. Verified `/doctor-applications`
  /// codes: VALIDATION_ERROR, FORBIDDEN, UNAUTHORIZED, DUPLICATE_ENTRY,
  /// INVALID_FORMAT, INVALID_REFERENCE, NOT_FOUND, INVALID_TARGET,
  /// INTERNAL_ERROR, RATE_LIMITED; transport codes from [ApiException].
  String doctorApplicationError(String? code) => switch (code) {
    'UNAUTHORIZED' => _t(
      'انتهت جلستك. سجّل الدخول من جديد ثم حاول مجدداً.',
      'Your session has expired. Sign in again and try once more.',
    ),
    'FORBIDDEN' => _t(
      'حسابك غير مؤهل لتقديم طلب انضمام كطبيب.',
      'Your account is not eligible to submit a doctor application.',
    ),
    'VALIDATION_ERROR' || 'INVALID_FORMAT' || 'INVALID_REFERENCE' => _t(
      'تحقّق من الحقول المدخلة ثم حاول مرة أخرى.',
      'Check the details you entered and try again.',
    ),
    'DUPLICATE_ENTRY' => _t(
      'لديك طلب قيد المراجعة بالفعل.',
      'You already have an application under review.',
    ),
    'NOT_FOUND' || 'INVALID_TARGET' => _t(
      'لم يعد هذا الطلب متاحاً لهذا الإجراء.',
      'This application is no longer available for that action.',
    ),
    'RATE_LIMITED' => _t(
      'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.',
      'Too many attempts. Wait a little while and try again.',
    ),
    'CONNECT_TIMEOUT' ||
    'SEND_TIMEOUT' ||
    'RECEIVE_TIMEOUT' ||
    'SERVICE_UNAVAILABLE' => _t(
      'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم حاول مرة أخرى.',
      'Could not reach the service. Check your connection and try again.',
    ),
    _ => _t(
      'حدث خطأ ما. حاول مرة أخرى.',
      'Something went wrong. Please try again.',
    ),
  };

  // ========================================================================
  // BILLING / AI ENTITLEMENT
  // Additive section: keep separate from Admin and existing feature strings.
  // ========================================================================
  String get billingTitle => _t('الخطة والفوترة', 'Plan & Billing');
  String get billingSubtitle => _t(
    'راجع خطتك وحدود خدمات الذكاء الاصطناعي وإدارة اشتراكك.',
    'Review your plan, AI access, and subscription.',
  );
  String get billingProfileDescription => _t(
    'الخطة الحالية والترقية وسجل الفوترة',
    'Current plan, upgrades, and billing history',
  );
  String get billingCurrentPlan => _t('الخطة الحالية', 'Current plan');
  String get billingFreePlan => _t('مجانية', 'Free');
  String get billingProPlan => _t('Pro', 'Pro');
  String get billingProBadge => _t('مشترك Pro', 'Pro member');
  String get billingFreeBadge => _t('الخطة المجانية', 'Free plan');
  String get billingPlansTitle => _t('الخطط المتاحة', 'Available plans');
  String get billingPlansSubtitle => _t(
    'الأسعار والعملات وفترات الفوترة مقدمة من الخادم.',
    'Prices, currencies, and billing periods come from the server.',
  );
  String get billingMonthly => _t('شهريًا', 'Monthly');
  String get billingAnnual => _t('سنويًا', 'Annual');
  String get billingIntervalMonth => _t('كل شهر', 'per month');
  String get billingIntervalYear => _t('كل سنة', 'per year');
  String billingInterval(String value, int count) {
    if (value == 'month') {
      return count == 1
          ? billingIntervalMonth
          : _t('كل $count أشهر', 'every $count months');
    }
    if (value == 'year') {
      return count == 1
          ? billingIntervalYear
          : _t('كل $count سنوات', 'every $count years');
    }
    return _t('فترة الفوترة من الخادم', 'Server billing interval');
  }

  String get billingUpgrade => _t('الترقية إلى Pro', 'Upgrade to Pro');
  String get billingCurrentPlanAction => _t('خطتك الحالية', 'Current plan');
  String get billingCheckoutUnavailable => _t(
    'الترقية غير متاحة حاليًا. لن تتأثر مزايا خطتك المجانية.',
    'Upgrades are currently unavailable. Your free access is unaffected.',
  );
  String get billingOpeningCheckout =>
      _t('جارٍ فتح الدفع الآمن...', 'Opening secure checkout...');
  String get billingHostedCheckoutHint => _t(
    'سيُفتح الدفع لدى مزود خارجي. لن يصبح حسابك Pro إلا بعد تأكيد الخادم للدفع.',
    'Checkout opens with the provider. Pro activates only after server confirmation.',
  );
  String get billingCheckoutLaunchFailed => _t(
    'تعذّر فتح صفحة الدفع الآمنة.',
    'Could not open the secure checkout page.',
  );
  String get billingCheckoutReturnHint => _t(
    'عد إلى التطبيق بعد إكمال الدفع لتحديث حالة اشتراكك.',
    'Return to the app after checkout to refresh your subscription.',
  );
  String get billingRefresh =>
      _t('تحديث حالة الفوترة', 'Refresh billing status');
  String get billingLoadErrorTitle =>
      _t('تعذّر تحميل الفوترة', 'Could not load billing');
  String get billingLoadErrorMessage => _t(
    'لم نتمكن من قراءة حالة خطتك من الخادم. لا نفترض أنك على الخطة المجانية.',
    'We could not read your plan state from the server. We will not assume Free.',
  );
  String get billingUsageTitle =>
      _t('استخدام خدمات الذكاء الاصطناعي', 'AI access');
  String billingChatRemaining(int remaining, int limit) => _t(
    '$remaining من $limit رسالة مجانية متبقية',
    '$remaining of $limit free messages remaining',
  );
  String get billingChatUnlimited =>
      _t('محادثة طبية غير محدودة', 'Unlimited medical chat');
  String get billingChatUnavailable =>
      _t('المحادثة غير متاحة الآن', 'Chat is unavailable now');
  String get billingVoiceUnlimited =>
      _t('الطبيب الصوتي متاح مع Pro', 'Voice Doctor included with Pro');
  String get billingVoiceAvailable =>
      _t('استشارة مجانية متاحة', 'Free consultation available');
  String get billingVoiceActive => _t(
    'لديك استشارة نشطة يمكن استئنافها',
    'An active consultation can be resumed',
  );
  String get billingVoiceCooldown => _t(
    'الاستشارة المجانية في فترة انتظار',
    'Free consultation is on cooldown',
  );
  String get billingResetsAt => _t('يتجدد الحد في', 'Allowance resets');
  String get billingNextFreeAt =>
      _t('الاستشارة المجانية التالية', 'Next free consultation');
  String get billingUnlimited => _t('غير محدود', 'Unlimited');

  String get subscriptionTitle => _t('إدارة الاشتراك', 'Manage subscription');
  String get subscriptionNoActive =>
      _t('لا يوجد اشتراك نشط', 'No active subscription');
  String get subscriptionStatus => _t('الحالة', 'Status');
  String get subscriptionPeriod => _t('فترة الاشتراك', 'Subscription period');
  String get subscriptionRenewsAt => _t('موعد التجديد', 'Renews on');
  String get subscriptionEndsAt => _t('ينتهي في', 'Ends on');
  String get subscriptionGraceEndsAt =>
      _t('تنتهي المهلة في', 'Grace period ends');
  String get subscriptionActive => _t('نشط', 'Active');
  String get subscriptionPastDue => _t('مشكلة في الدفع', 'Payment problem');
  String get subscriptionIncomplete =>
      _t('الدفع غير مكتمل', 'Payment incomplete');
  String get subscriptionCanceling =>
      _t('سينتهي بنهاية الفترة', 'Ending at period end');
  String get subscriptionCanceled => _t('ملغى', 'Canceled');
  String get subscriptionExpired => _t('منتهي', 'Expired');
  String get subscriptionUnknown => _t('غير معروف', 'Unknown');
  String subscriptionStatusLabel(String? status, bool cancelAtPeriodEnd) {
    if (status == 'active' && cancelAtPeriodEnd) return subscriptionCanceling;
    return switch (status) {
      'active' => subscriptionActive,
      'past_due' => subscriptionPastDue,
      'incomplete' => subscriptionIncomplete,
      'canceled' => subscriptionCanceled,
      'expired' => subscriptionExpired,
      _ => status == null ? subscriptionNoActive : subscriptionUnknown,
    };
  }

  String get subscriptionPastDueHint => _t(
    'قد تستمر مزايا Pro مؤقتًا خلال المهلة التي حددها الخادم.',
    'Pro may remain available during the server-provided grace period.',
  );
  String get subscriptionCancel => _t('إيقاف التجديد', 'Stop renewal');
  String get subscriptionCancelTitle =>
      _t('إيقاف التجديد التلقائي؟', 'Stop automatic renewal?');
  String get subscriptionCancelBody => _t(
    'سيظل اشتراك Pro متاحًا حتى نهاية الفترة الحالية. لن يتم الإلغاء فورًا.',
    'Pro remains available through the current period. Cancellation is not immediate.',
  );
  String get subscriptionResume => _t('استئناف التجديد', 'Resume renewal');
  String get subscriptionResumeTitle =>
      _t('استئناف التجديد؟', 'Resume automatic renewal?');
  String get subscriptionResumeBody => _t(
    'سيعود الاشتراك للتجدد وفق الخطة الحالية.',
    'The subscription will renew on the current plan.',
  );
  String get subscriptionChangePlan =>
      _t('تغيير خطة التجديد', 'Change renewal plan');
  String subscriptionChangeTitle(String plan) =>
      _t('التغيير إلى $plan؟', 'Change to $plan?');
  String subscriptionChangeBody(String plan) => _t(
    'سيطبق الخادم خطة $plan عند موعد التجديد التالي.',
    'The server will apply $plan at the next renewal.',
  );
  String get subscriptionPendingPlan =>
      _t('التغيير المجدول', 'Scheduled change');
  String subscriptionPendingPlanHint(String plan, String date) =>
      _t('سيتم التغيير إلى $plan في $date.', 'Changes to $plan on $date.');
  String get subscriptionActionSuccess =>
      _t('تم تحديث الاشتراك.', 'Subscription updated.');
  String get confirm => _t('تأكيد', 'Confirm');

  String get billingHistoryTitle => _t('سجل الفوترة', 'Billing history');
  String get billingHistorySubtitle => _t(
    'الأحداث التي عالجها الخادم لحسابك.',
    'Server-processed events for your account.',
  );
  String get billingHistoryEmpty =>
      _t('لا توجد أحداث فوترة بعد.', 'No billing events yet.');
  String billingHistoryEvent(String type) => switch (type) {
    'checkout.completed' => _t('اكتمل الدفع', 'Checkout completed'),
    'subscription.activated' => _t(
      'تم تفعيل الاشتراك',
      'Subscription activated',
    ),
    'subscription.renewed' => _t('تم تجديد الاشتراك', 'Subscription renewed'),
    'subscription.updated' => _t('تم تحديث الاشتراك', 'Subscription updated'),
    'subscription.cancel_at_period_end' => _t(
      'تم تحديث التجديد',
      'Renewal preference updated',
    ),
    'subscription.canceled' => _t('انتهى الاشتراك', 'Subscription ended'),
    'payment.failed' => _t('تعذر الدفع', 'Payment failed'),
    'payment.recovered' => _t('تمت استعادة الدفع', 'Payment recovered'),
    _ => _t('حدث فوترة', 'Billing event'),
  };

  String get sandboxBillingTitle => _t('الدفع التجريبي', 'Sandbox checkout');
  String get sandboxBillingBanner => _t(
    'محاكاة للتطوير فقط — لا تتم معالجة أي دفعة حقيقية.',
    'Development simulation only — no real payment is processed.',
  );
  String get sandboxNoCard => _t(
    'لن يطلب التطبيق أي رقم بطاقة أو رمز أمان ولن يخزنه.',
    'The app never asks for or stores card numbers or security codes.',
  );
  String get sandboxSimulateSuccess =>
      _t('محاكاة دفع ناجح', 'Simulate successful payment');
  String get sandboxSimulateFailure =>
      _t('محاكاة فشل الدفع', 'Simulate payment failure');
  String get sandboxSimulateCancel =>
      _t('إلغاء العملية التجريبية', 'Cancel simulated checkout');
  String get sandboxCheckoutClosed => _t(
    'تم إغلاق جلسة الدفع أو انتهت صلاحيتها.',
    'This checkout is closed or expired.',
  );
  String get sandboxLifecycleTitle =>
      _t('محاكاة دورة الاشتراك', 'Simulate subscription lifecycle');
  String get sandboxRenewal => _t('تجديد ناجح', 'Successful renewal');
  String get sandboxRenewalFailure => _t('فشل التجديد', 'Renewal failure');
  String get sandboxPaymentRecovered =>
      _t('استعادة الدفع', 'Payment recovered');
  String get sandboxSubscriptionEnded =>
      _t('انتهاء الاشتراك', 'Subscription ended');
  String get sandboxDisabled => _t(
    'الدفع التجريبي غير مفعّل على الخادم.',
    'Sandbox billing is not enabled by the server.',
  );

  String get entitlementUpgradeAction => _t('عرض خطط Pro', 'View Pro plans');
  String get chatQuotaTitle =>
      _t('حد الرسائل المجانية', 'Free message allowance');
  String get chatQuotaExhaustedBody => _t(
    'يمكنك قراءة محادثاتك السابقة. للرسائل الجديدة، انتظر التجديد أو اختر Pro.',
    'You can still read prior conversations. For new messages, wait for reset or choose Pro.',
  );
  String get chatQuotaPro => _t('محادثة Pro غير محدودة', 'Unlimited Pro chat');
  String get chatRateLimited => _t(
    'طلبات كثيرة خلال وقت قصير. انتظر قليلًا ثم حاول مجددًا.',
    'Too many requests in a short time. Wait a moment and try again.',
  );
  String get voiceEntitlementPro =>
      _t('وصول Pro للطبيب الصوتي', 'Pro Voice Doctor access');
  String get voiceEntitlementEligible =>
      _t('استشارتك المجانية متاحة', 'Your free consultation is available');
  String get voiceEntitlementResume =>
      _t('استئناف الاستشارة النشطة', 'Resume active consultation');
  String get voiceEntitlementCooldown => _t(
    'الاستشارة المجانية غير متاحة بعد',
    'Free consultation is not available yet',
  );
  String get voiceEnding =>
      _t('جارٍ إنهاء الاستشارة...', 'Ending consultation...');
  String get voiceEndFailed => _t(
    'تعذر إنهاء الاستشارة على الخادم. يمكنك المحاولة مجددًا.',
    'The server could not end the consultation. You can try again.',
  );
  String get voiceResumed =>
      _t('تم استئناف الاستشارة النشطة', 'Active consultation resumed');
  String get voiceNextFree =>
      _t('الاستشارة المجانية التالية', 'Next free consultation');
  String voiceRecordingEnds(int seconds) =>
      _t('ينتهي التسجيل خلال $seconds ث', 'Recording ends in ${seconds}s');

  String billingError(String? code) => switch (code) {
    'VALIDATION_ERROR' => _t(
      'الطلب غير صالح. حدّث الصفحة وحاول مجددًا.',
      'The request was invalid. Refresh and try again.',
    ),
    'UNAUTHORIZED' => _t(
      'انتهت جلستك. سجّل الدخول مجددًا.',
      'Your session expired. Sign in again.',
    ),
    'FORBIDDEN' => _t(
      'لا يملك هذا الحساب صلاحية تنفيذ الإجراء.',
      'This account cannot perform that action.',
    ),
    'RATE_LIMITED' => chatRateLimited,
    'FREE_QUOTA_EXHAUSTED' => chatQuotaExhaustedBody,
    'DUPLICATE_IN_FLIGHT' => chatErrDuplicateMessage,
    'VOICE_COOLDOWN' => voiceEntitlementCooldown,
    'VOICE_SESSION_ACTIVE' => voiceEntitlementResume,
    'SUBSCRIPTION_REQUIRED' => chatErrSubscriptionRequired,
    'SUBSCRIPTION_INACTIVE' => chatErrSubscriptionInactive,
    'ENTITLEMENT_UNAVAILABLE' => _t(
      'تعذر التحقق من حالة الاستحقاق الآن. حاول مجددًا.',
      'Entitlement status is unavailable. Try again.',
    ),
    'CHECKOUT_NOT_FOUND' => _t(
      'لم يتم العثور على جلسة الدفع.',
      'Checkout session was not found.',
    ),
    'CHECKOUT_NOT_OPEN' => sandboxCheckoutClosed,
    'SUBSCRIPTION_NOT_FOUND' => subscriptionNoActive,
    'SUBSCRIPTION_ALREADY_LIVE' => _t(
      'يوجد اشتراك قائم لهذا الحساب بالفعل.',
      'This account already has a live subscription.',
    ),
    'PLAN_CHANGE_INVALID' => _t(
      'لا يمكن جدولة هذا التغيير للخطة.',
      'This plan change cannot be scheduled.',
    ),
    'SANDBOX_DISABLED' => sandboxDisabled,
    'INVALID_RESPONSE' => _t(
      'أرسل الخادم استجابة غير متوقعة.',
      'The server returned an unexpected response.',
    ),
    'CONNECT_TIMEOUT' ||
    'SEND_TIMEOUT' ||
    'RECEIVE_TIMEOUT' ||
    'SERVICE_UNAVAILABLE' => _t(
      'تعذر الوصول إلى خدمة الفوترة. تحقق من اتصالك.',
      'Could not reach billing. Check your connection.',
    ),
    _ => errorGeneric,
  };

  // ===== DOCTOR WORKSPACE / CLINICAL OPERATIONS =====
  // Additive section kept isolated for parallel mobile workstreams.
  String get doctorWorkspace => _t('مساحة عمل الطبيب', 'Doctor workspace');
  String get doctorWorkspaceSubtitle => _t(
    'أدر جدولك ومرضاك ومحتواك المهني بأمان.',
    'Manage your schedule, patients, and professional content securely.',
  );
  String get professionalProfile => _t('الملف المهني', 'Professional profile');
  String get doctorProfessionalProfileSubtitle => _t(
    'حدّث بياناتك المهنية الظاهرة للمرضى.',
    'Update the professional information patients can see.',
  );
  String get professionalHeadline =>
      _t('العنوان المهني', 'Professional headline');
  String get professionalBiography =>
      _t('النبذة المهنية', 'Professional biography');
  String get subSpecialty => _t('التخصص الدقيق', 'Sub-specialty');
  String get yearsOfExperience => _t('سنوات الخبرة', 'Years of experience');
  String get consultationFee => _t('رسوم الاستشارة', 'Consultation fee');
  String get city => _t('المدينة', 'City');
  String get areasOfExpertise => _t(
    'مجالات الخبرة (افصل بينها بفاصلة)',
    'Areas of expertise (comma-separated)',
  );
  String get professionalInterests => _t(
    'الاهتمامات المهنية (افصل بينها بفاصلة)',
    'Professional interests (comma-separated)',
  );
  String get languages =>
      _t('اللغات (افصل بينها بفاصلة)', 'Languages (comma-separated)');
  String get educationLines =>
      _t('التعليم (عنصر في كل سطر)', 'Education (one per line)');
  String get certificationLines =>
      _t('الشهادات (عنصر في كل سطر)', 'Certifications (one per line)');
  String get acceptingPatients => _t('يستقبل مرضى', 'Accepting patients');
  String get verifiedCredentialsReadOnly => _t(
    'التخصص والترخيص الموثقان للقراءة فقط.',
    'Verified specialty and license are read-only.',
  );
  String minutesValue(int value) => _t('$value دقيقة', '$value min');
  String bookingDaysValue(int value) =>
      _t('$value يومًا للحجز', '$value booking days');
  String get schedule => _t('الجدول والتوفر', 'Schedule & availability');
  String get doctorScheduleSubtitle => _t(
    'نظّم أوقات التوفر وإعدادات الحجز.',
    'Manage availability and booking settings.',
  );
  String get doctorAppointments => _t('مواعيد الطبيب', 'Doctor appointments');
  String get doctorAppointmentsSubtitle => _t(
    'راجع المواعيد وأكّدها وأكملها.',
    'Review, confirm, and complete appointments.',
  );
  String get myPatients => _t('مرضاي', 'My patients');
  String get doctorPatientsSubtitle => _t(
    'افتح ملفات المرضى المرتبطين بك سريريًا.',
    'Open clinically connected patient files.',
  );
  String get doctorPosts => _t('منشوراتي', 'My posts');
  String get doctorPostsSubtitle => _t(
    'أنشئ المسودات وأدر المنشورات المنشورة.',
    'Create drafts and manage published posts.',
  );
  String get doctorRecords => _t('السجلات الطبية', 'Medical records');
  String get doctorRecordsSubtitle => _t(
    'أنشئ السجلات السريرية المرتبطة بالمواعيد.',
    'Create appointment-linked clinical records.',
  );
  String get doctorEligibilityUnavailable => _t(
    'مساحة عمل الطبيب غير متاحة لهذا الحساب.',
    'The doctor workspace is not available for this account.',
  );
  String get doctorApprovalRequired => _t(
    'يجب اعتماد ملف الطبيب قبل استخدام مساحة العمل.',
    'Your doctor profile must be approved before using this workspace.',
  );
  String get save => _t('حفظ', 'Save');
  String get delete => _t('حذف', 'Delete');
  String get edit => _t('تعديل', 'Edit');
  String get create => _t('إنشاء', 'Create');
  String get complete => _t('إكمال', 'Complete');
  String get refresh => _t('تحديث', 'Refresh');
  String get searchPatients => _t('ابحث عن مريض', 'Search patients');
  String get noPatients => _t(
    'لا يوجد مرضى مرتبطون بك حاليًا.',
    'You have no active patient relationships.',
  );
  String get noAppointments => _t(
    'لا توجد مواعيد في جدولك.',
    'There are no appointments in your schedule.',
  );
  String get noAvailability =>
      _t('لم تتم إضافة أوقات توفر بعد.', 'No availability has been added yet.');
  String get noPosts =>
      _t('لم تنشئ أي منشورات بعد.', 'You have not created any posts yet.');
  String get noRecords =>
      _t('لا توجد سجلات طبية متاحة.', 'No medical records are available.');
  String get addAvailability => _t('إضافة وقت توفر', 'Add availability');
  String get weeklyAvailability => _t('التوفر الأسبوعي', 'Weekly availability');
  String get dateOverrides => _t('استثناءات التواريخ', 'Date overrides');
  String get clinic => _t('العيادة', 'Clinic');
  String get telemedicine => _t('استشارة عن بُعد', 'Telemedicine');
  String get inPerson => _t('في العيادة', 'In person');
  String get startTime => _t('وقت البدء', 'Start time');
  String get endTime => _t('وقت الانتهاء', 'End time');
  String get specificDate => _t('تاريخ محدد', 'Specific date');
  String get weekday => _t('يوم الأسبوع', 'Weekday');
  String get slotDuration => _t('مدة الموعد', 'Slot duration');
  String get availabilityType => _t('نوع التوفر', 'Availability type');
  String get available => _t('متاح', 'Available');
  String get blocked => _t('محظور', 'Blocked');
  String get dayOff => _t('إجازة', 'Day off');
  String get patientFile => _t('ملف المريض', 'Patient file');
  String get patientInformation => _t('بيانات المريض', 'Patient information');
  String get sessionNotes => _t('ملاحظات الجلسات', 'Session notes');
  String get addSessionNote => _t('إضافة ملاحظة جلسة', 'Add session note');
  String get visibleToPatient => _t('مرئية للمريض', 'Visible to patient');
  String get draft => _t('مسودة', 'Draft');
  String get publish => _t('نشر', 'Publish');
  String get publishNoteWarning => _t(
    'سيتمكن المريض من قراءة هذه الملاحظة. هل تريد المتابعة؟',
    'The patient will be able to read this note. Continue?',
  );
  String get endCareRelationship =>
      _t('إنهاء علاقة الرعاية', 'End care relationship');
  String get endRelationshipWarning => _t(
    'سيفقد هذا المريض الارتباط النشط بك. لن تُحذف السجلات أو المواعيد السابقة.',
    'This patient will no longer have an active care relationship with you. Existing records and appointments are not deleted.',
  );
  String get reason => _t('السبب', 'Reason');
  String get diagnosis => _t('التشخيص', 'Diagnosis');
  String get chiefComplaint => _t('الشكوى الرئيسية', 'Chief complaint');
  String get clinicalNotes => _t('ملاحظات سريرية', 'Clinical notes');
  String get privateDoctorNotes =>
      _t('ملاحظات خاصة بالطبيب', 'Private doctor notes');
  String get treatmentPlan => _t('خطة العلاج', 'Treatment plan');
  String get recordType => _t('نوع السجل', 'Record type');
  String get createPrescription => _t('إنشاء وصفة طبية', 'Create prescription');
  String get prescriptionHistory => _t('سجل الوصفات', 'Prescription history');
  String get appointment => _t('الموعد', 'Appointment');
  String get medicationNameArabic =>
      _t('اسم الدواء بالعربية', 'Medication name in Arabic');
  String get medicationNameEnglish =>
      _t('اسم الدواء بالإنجليزية', 'Medication name in English');
  String get dosage => _t('الجرعة', 'Dosage');
  String get frequency => _t('التكرار', 'Frequency');
  String get duration => _t('المدة', 'Duration');
  String get quantity => _t('الكمية', 'Quantity');
  String get instructions => _t('التعليمات', 'Instructions');
  String get validUntil =>
      _t('صالح حتى (سنة-شهر-يوم)', 'Valid until (YYYY-MM-DD)');
  String get safetyWarning => _t(
    'تم حفظ الوصفة، وأبلغ فحص السلامة الاستشاري عن تحذير. راجعها سريريًا.',
    'The prescription was saved and the advisory safety check reported a warning. Review it clinically.',
  );
  String get safetyUnavailable => _t(
    'تم حفظ الوصفة، لكن فحص السلامة الاستشاري غير متاح. راجعها سريريًا.',
    'The prescription was saved, but the advisory safety check is unavailable. Review it clinically.',
  );
  String get postTitle => _t('عنوان المنشور', 'Post title');
  String get postBody => _t('محتوى المنشور', 'Post body');
  String get category => _t('الفئة', 'Category');
  String get published => _t('منشور', 'Published');
  String get moderation => _t('المراجعة', 'Moderation');
  String get deleteConfirmation => _t(
    'لا يمكن التراجع عن هذا الإجراء من التطبيق. هل تريد المتابعة؟',
    'This action cannot be undone in the app. Continue?',
  );
  String get doctorRequiredField =>
      _t('هذا الحقل مطلوب.', 'This field is required.');
  String get invalidValue =>
      _t('تحقق من القيمة المدخلة.', 'Check the value you entered.');
  String get operationSucceeded => _t('تم حفظ التغييرات.', 'Changes saved.');
  String doctorPostCategory(String value) => switch (value) {
    'health_tip' => _t('نصيحة صحية', 'Health tip'),
    'announcement' => _t('إعلان', 'Announcement'),
    'clinic_news' => _t('أخبار العيادة', 'Clinic news'),
    'article' => _t('مقال', 'Article'),
    _ => value,
  };
  String doctorRecordType(String value) => switch (value) {
    'consultation' => _t('استشارة', 'Consultation'),
    'follow_up' => _t('متابعة', 'Follow-up'),
    'diagnosis' => _t('تشخيص', 'Diagnosis'),
    'treatment' => _t('علاج', 'Treatment'),
    'other' => _t('أخرى', 'Other'),
    _ => _t('غير معروف', 'Unknown'),
  };
  String doctorStatus(String value) => switch (value) {
    'scheduled' => _t('مجدول', 'Scheduled'),
    'confirmed' => _t('مؤكد', 'Confirmed'),
    'in_progress' => _t('جارٍ', 'In progress'),
    'completed' => _t('مكتمل', 'Completed'),
    'cancelled' => _t('ملغي', 'Cancelled'),
    'no_show' => _t('لم يحضر', 'No show'),
    'draft' => _t('مسودة', 'Draft'),
    'published' => _t('منشور', 'Published'),
    'active' => _t('نشط', 'Active'),
    'approved' => _t('معتمد', 'Approved'),
    'pending' => _t('قيد المراجعة', 'Pending'),
    'rejected' => _t('مرفوض', 'Rejected'),
    'hidden' => _t('مخفي', 'Hidden'),
    _ => _t('غير معروف', 'Unknown'),
  };
  String doctorError(String? code) => switch (code) {
    'UNAUTHORIZED' => _t(
      'انتهت جلستك. سجّل الدخول من جديد.',
      'Your session has expired. Sign in again.',
    ),
    'FORBIDDEN' => _t(
      'لا يملك هذا الحساب صلاحية تنفيذ هذا الإجراء.',
      'This account is not allowed to perform this action.',
    ),
    'NOT_FOUND' => _t(
      'لم يعد العنصر متاحًا أو لا يمكنك الوصول إليه.',
      'This item is no longer available or accessible.',
    ),
    'DOCTOR_NOT_APPROVED' => doctorApprovalRequired,
    'VALIDATION_ERROR' ||
    'INVALID_FORMAT' ||
    'PROTECTED_FIELD' ||
    'INVALID_WEEKDAY' ||
    'INVALID_TIME_RANGE' ||
    'PLAN_CHANGE_INVALID' => _t(
      'تحقق من البيانات المدخلة ثم حاول مرة أخرى.',
      'Check the entered details and try again.',
    ),
    'AVAILABILITY_OVERLAP' => _t(
      'يتداخل هذا الوقت مع فترة توفر أخرى.',
      'This time overlaps another availability period.',
    ),
    'BOOKED_APPOINTMENT_CONFLICT' => _t(
      'لا يمكن تغيير هذا الوقت لوجود موعد محجوز.',
      'This availability cannot be changed because it conflicts with a booked appointment.',
    ),
    'CLINIC_REQUIRED' || 'CLINIC_NOT_ASSIGNED' => _t(
      'اختر عيادة مرتبطة بملفك لهذا الموعد.',
      'Choose a clinic assigned to your profile for this slot.',
    ),
    'PAST_DATE' || 'DATE_OUTSIDE_HORIZON' => _t(
      'اختر تاريخًا صالحًا ضمن نطاق الحجز الذي حدده الخادم.',
      'Choose a valid date within the server booking horizon.',
    ),
    'CONTENT_MODERATED' => _t(
      'لا يمكن نشر هذا المحتوى بسبب حالة المراجعة.',
      'This content cannot be published because of its moderation status.',
    ),
    'RATE_LIMITED' || 'DUPLICATE_IN_FLIGHT' => _t(
      'الطلب قيد المعالجة أو توجد محاولات كثيرة. انتظر قليلًا.',
      'The request is already processing or there are too many attempts. Wait a moment.',
    ),
    'CONNECT_TIMEOUT' ||
    'SEND_TIMEOUT' ||
    'RECEIVE_TIMEOUT' ||
    'SERVICE_UNAVAILABLE' => _t(
      'تعذر الوصول إلى الخدمة. تحقق من اتصالك وحاول مرة أخرى.',
      'Could not reach the service. Check your connection and try again.',
    ),
    'INVALID_RESPONSE' => _t(
      'وصل رد غير مكتمل من الخدمة. حاول مرة أخرى.',
      'The service returned an incomplete response. Try again.',
    ),
    _ => errorGeneric,
  };

  // ═══════════════════════════════════════════════════════════════════════
  // ADMINISTRATION (admin / super_admin)
  //
  // Every string used by `lib/features/admin/**`. Kept in one delimited
  // block at the end of the table so the administration workstream never
  // reorders or reformats the strings above it.
  // ═══════════════════════════════════════════════════════════════════════

  // ── Shared admin chrome ────────────────────────────────────────────────
  String get roleSuperAdmin => _t('مسؤول أعلى', 'Super administrator');
  String get adminToolsTitle => _t('أدوات الإدارة', 'Administration tools');
  String get adminToolsSubtitle => _t(
    'إدارة الحسابات والطلبات والمحتوى.',
    'Manage accounts, requests, and content.',
  );
  String get adminRestrictedTitle =>
      _t('هذه المساحة للمسؤولين', 'Administrators only');
  String get adminRestrictedBody => _t(
    'حسابك لا يملك صلاحية الوصول إلى هذه الصفحة.',
    'Your account does not have access to this page.',
  );
  String get adminSuperAdminOnlyTitle =>
      _t('للمسؤول الأعلى فقط', 'Super administrators only');
  String get adminSuperAdminOnlyBody => _t(
    'إدارة دعوات المشرفين متاحة لحساب المسؤول الأعلى فقط.',
    'Managing administrator invitations is restricted to the super administrator account.',
  );
  String get adminLoadErrorTitle =>
      _t('تعذر تحميل البيانات', 'Could not load this data');
  String get adminActionFailedTitle =>
      _t('تعذر إتمام الإجراء', 'The action could not be completed');
  String get adminRefreshTooltip => _t('تحديث', 'Refresh');
  String get adminFiltersTitle => _t('عوامل التصفية', 'Filters');
  String get adminFiltersTooltip => _t('فتح عوامل التصفية', 'Open filters');
  String get adminFilterAll => _t('الكل', 'All');
  String get adminClearFilters => _t('مسح التصفية', 'Clear filters');
  String get adminApplyFilters => _t('تطبيق', 'Apply');
  String get adminNoResultsTitle => _t('لا توجد نتائج', 'No results');
  String get adminNoResultsHint => _t(
    'جرّب تعديل عوامل التصفية أو كلمة البحث.',
    'Try adjusting the filters or your search term.',
  );
  String get adminLoadingMore => _t('جارٍ تحميل المزيد…', 'Loading more…');
  String get adminEndOfList => _t('نهاية القائمة', 'End of list');
  String adminShowingCount(int count) =>
      _t('$count عنصراً معروضاً', '$count shown');
  String get adminCopy => _t('نسخ', 'Copy');
  String get adminCopied => _t('تم النسخ', 'Copied');
  String get adminDetailsTitle => _t('التفاصيل', 'Details');

  // ── Admin hub tools ────────────────────────────────────────────────────
  String get adminToolUsers => _t('إدارة المستخدمين', 'User management');
  String get adminToolUsersDescription => _t(
    'ابحث في الحسابات وفعّلها أو أوقفها.',
    'Search accounts and activate or deactivate them.',
  );
  String get adminToolApplications =>
      _t('طلبات الأطباء', 'Doctor applications');
  String get adminToolApplicationsDescription => _t(
    'راجع طلبات الانضمام واعتمدها أو ارفضها.',
    'Review join requests and approve or reject them.',
  );
  String get adminToolContact => _t('رسائل التواصل', 'Contact messages');
  String get adminToolContactDescription => _t(
    'راجع رسائل الدعم وحدّث حالتها.',
    'Review support messages and keep their status current.',
  );
  String get adminToolModeration => _t('مراجعة المحتوى', 'Content moderation');
  String get adminToolModerationDescription => _t(
    'اعتمد أو أخفِ منشورات الأطباء والتعليقات.',
    'Approve or hide doctor posts and comments.',
  );
  String get adminToolInvitations => _t('دعوات المشرفين', 'Admin invitations');
  String get adminToolInvitationsDescription => _t(
    'ادعُ حسابات موثقة لتصبح مشرفين.',
    'Invite verified accounts to become administrators.',
  );
  String get adminToolAnalytics => _t('التحليلات', 'Analytics');
  String get adminToolAnalyticsDescription => _t(
    'اتجاهات المنصة وتوزيع الاستخدام.',
    'Platform trends and usage distribution.',
  );
  String get adminToolAuditLogs => _t('سجل التدقيق', 'Audit log');
  String get adminToolAuditLogsDescription => _t(
    'سجل للقراءة فقط بالإجراءات الإدارية.',
    'A read-only record of administrative actions.',
  );
  String get adminStatsAppointmentsCompleted =>
      _t('مواعيد مكتملة', 'Completed appointments');
  String get adminStatsAppointmentsScheduled =>
      _t('مواعيد مجدولة', 'Scheduled appointments');
  String get adminStatsAppointmentsCancelled =>
      _t('مواعيد ملغاة', 'Cancelled appointments');

  // ── Analytics ──────────────────────────────────────────────────────────
  String get adminAnalyticsTitle => _t('التحليلات', 'Analytics');
  String get adminAnalyticsSubtitle => _t(
    'ملخص تشغيلي مجمّع للمنصة. لا يتضمن بيانات مريض فردية.',
    'Aggregate operational summary. No individual patient data is included.',
  );
  String get adminAnalyticsAppointmentsOverTime =>
      _t('المواعيد عبر الوقت', 'Appointments over time');
  String get adminAnalyticsUsersByRole =>
      _t('المستخدمون حسب الدور', 'Users by role');
  String get adminAnalyticsTopSpecialties =>
      _t('أكثر التخصصات طلباً', 'Top specialties');
  String get adminAnalyticsConversationsPerWeek =>
      _t('محادثات المساعد أسبوعياً', 'AI conversations per week');
  String get adminAnalyticsTriageLevels =>
      _t('مستويات الأولوية', 'Triage levels');
  String get adminAnalyticsClinicTypes => _t('أنواع المنشآت', 'Facility types');
  String get adminAnalyticsAwaitingData =>
      _t('لا توجد بيانات كافية بعد.', 'Not enough data yet.');
  String get adminAnalyticsSectionUnavailable => _t(
    'هذا القسم غير متاح حالياً.',
    'This section is unavailable right now.',
  );
  String get adminAnalyticsAllUnavailableTitle =>
      _t('التحليلات غير متاحة', 'Analytics unavailable');
  String get adminAnalyticsAllUnavailableHint => _t(
    'تعذر حساب أي قسم من التحليلات. حاول التحديث لاحقاً.',
    'None of the analytics sections could be computed. Try refreshing later.',
  );
  String get adminAnalyticsWeeklyTrendHint => _t(
    'آخر ١٢ أسبوعاً، أسبوع لكل عمود.',
    'The last 12 weeks, one bar per week.',
  );
  String adminAnalyticsTotalLabel(int total) =>
      _t('الإجمالي: $total', 'Total: $total');
  String adminAnalyticsShare(String label, int count, String percent) =>
      _t('$label: $count ($percent٪)', '$label: $count ($percent%)');
  String adminAnalyticsWeekOf(String date) =>
      _t('أسبوع $date', 'Week of $date');

  /// Facility type labels, matching `CLINIC_TYPE_LABEL_KEYS` in
  /// `frontend/src/js/analytics.js`. An unmapped value renders as-is.
  String adminClinicTypeLabel(String type) => switch (type) {
    'clinic' => _t('عيادة', 'Clinic'),
    'hospital' => _t('مستشفى', 'Hospital'),
    'pharmacy' => _t('صيدلية', 'Pharmacy'),
    'medical_center' => _t('مركز طبي', 'Medical center'),
    'laboratory' => _t('مختبر', 'Laboratory'),
    'radiology' => _t('أشعة', 'Radiology'),
    'dental' => _t('أسنان', 'Dental'),
    'emergency' => _t('طوارئ', 'Emergency'),
    'optical' => _t('بصريات', 'Optical'),
    'vaccination_center' => _t('مركز تطعيم', 'Vaccination center'),
    _ => type,
  };

  /// Triage labels, matching `TRIAGE_LABEL_KEYS` in `analytics.js`.
  String adminTriageLabel(String level) => switch (level) {
    'emergency' => _t('طارئ', 'Emergency'),
    'urgent' => _t('عاجل', 'Urgent'),
    'routine' => _t('روتيني', 'Routine'),
    _ => level,
  };

  /// Role labels for both the analytics breakdown and the user list.
  String adminRoleLabel(String role) => switch (role) {
    'patient' => rolePatient,
    'doctor' => roleDoctor,
    'admin' => roleAdmin,
    'super_admin' => roleSuperAdmin,
    _ => role,
  };

  // ── User management ────────────────────────────────────────────────────
  String get adminUsersTitle => _t('إدارة المستخدمين', 'User management');
  String get adminUsersSubtitle =>
      _t('إدارة حسابات المنصة.', 'Manage platform accounts.');
  String get adminUsersSearchLabel => _t('ابحث عن المستخدمين', 'Search users');
  String get adminUsersSearchHint =>
      _t('الاسم أو البريد الإلكتروني', 'Name or email address');
  String get adminUsersRoleFilterLabel => _t('الدور', 'Role');
  String get adminUsersStatusFilterLabel => _t('الحالة', 'Status');
  String get adminUsersStatusActive => _t('نشط', 'Active');
  String get adminUsersStatusInactive => _t('موقوف', 'Inactive');
  String get adminUsersVerified => _t('بريد موثق', 'Email verified');
  String get adminUsersUnverified => _t('بريد غير موثق', 'Email not verified');
  String get adminUsersDeactivate => _t('إيقاف', 'Deactivate');
  String get adminUsersReactivate => _t('إعادة تفعيل', 'Reactivate');
  String get adminUsersCurrentAccount => _t('حسابك', 'Your account');
  String get adminUsersProtectedAccount => _t('حساب محمي', 'Protected account');
  String get adminUsersProtectedHint => _t(
    'لا يمكن تعديل حسابات المسؤولين من هنا.',
    'Administrator accounts cannot be changed from here.',
  );
  String get adminUsersSelfHint => _t(
    'لا يمكن للمسؤول تعديل حالة حسابه.',
    'Administrators cannot change their own account state.',
  );
  String adminUsersConfirmDeactivateTitle(String name) =>
      _t('إيقاف $name؟', 'Deactivate $name?');
  String get adminUsersConfirmDeactivateBody => _t(
    'سيتم إنهاء جميع جلسات هذا الحساب فوراً ولن يتمكن من تسجيل الدخول حتى إعادة تفعيله.',
    'Every session for this account ends immediately, and the account cannot sign in again until it is reactivated.',
  );
  String adminUsersConfirmReactivateTitle(String name) =>
      _t('إعادة تفعيل $name؟', 'Reactivate $name?');
  String get adminUsersConfirmReactivateBody => _t(
    'سيتمكن هذا الحساب من تسجيل الدخول مجدداً. سيُطلب منه تسجيل دخول جديد.',
    'This account will be able to sign in again. It will need to sign in fresh.',
  );
  String get adminUsersDeactivateSuccess =>
      _t('تم إيقاف الحساب.', 'The account was deactivated.');
  String get adminUsersReactivateSuccess =>
      _t('تمت إعادة تفعيل الحساب.', 'The account was reactivated.');
  String get adminUsersEmptyTitle =>
      _t('لا توجد حسابات', 'No accounts to show');
  String get adminUsersEmptyHint => _t(
    'لا توجد حسابات مطابقة لعوامل التصفية الحالية.',
    'No accounts match the current filters.',
  );
  String get adminUsersRoleChangeNote => _t(
    'تغيير الأدوار معطّل في الخادم؛ استخدم دعوة مشرف لترقية حساب.',
    'Role changes are disabled on the server. Use an admin invitation to promote an account.',
  );

  // ── Doctor application review ──────────────────────────────────────────
  String get adminApplicationsTitle =>
      _t('مراجعة طلبات الأطباء', 'Doctor application review');
  String get adminApplicationsSubtitle => _t(
    'راجع طلبات الانضمام واتخذ قراراً.',
    'Review join requests and record a decision.',
  );
  String get adminApplicationsStatusPending => _t('قيد المراجعة', 'Pending');
  String get adminApplicationsStatusApproved => _t('مقبول', 'Approved');
  String get adminApplicationsStatusRejected => _t('مرفوض', 'Rejected');
  String get adminApplicationsStatusWithdrawn => _t('مسحوب', 'Withdrawn');
  String get adminApplicationsEmptyTitle =>
      _t('لا توجد طلبات', 'No applications');
  String get adminApplicationsEmptyHint => _t(
    'لا توجد طلبات بهذه الحالة حالياً.',
    'There are no applications in this state right now.',
  );
  String get adminApplicationsLimitNote => _t(
    'يعرض الخادم أحدث ١٠٠ طلب.',
    'The server returns the 100 most recent applications.',
  );
  String get adminApplicationDetailTitle => _t('تفاصيل الطلب', 'Application');
  String get adminApplicationApplicantSection =>
      _t('بيانات مقدّم الطلب', 'Applicant');
  String get adminApplicationProfessionalSection =>
      _t('البيانات المهنية', 'Professional details');
  String get adminApplicationSpecialty => _t('التخصص', 'Specialty');
  String get adminApplicationLicense => _t('رقم الترخيص', 'Medical license');
  String get adminApplicationSubSpecialty =>
      _t('التخصص الدقيق', 'Sub-specialty');
  String get adminApplicationExperience => _t('سنوات الخبرة', 'Experience');
  String get adminApplicationEducation => _t('التعليم', 'Education');
  String get adminApplicationCertifications => _t('الشهادات', 'Certifications');
  String get adminApplicationBio => _t('نبذة مهنية', 'Professional bio');
  String get adminApplicationSubmittedAt => _t('تاريخ التقديم', 'Submitted');
  String get adminApplicationReviewedAt => _t('تاريخ المراجعة', 'Reviewed');
  String get adminApplicationRejectionReason =>
      _t('سبب الرفض', 'Rejection reason');
  String get adminApplicationApprove => _t('اعتماد', 'Approve');
  String get adminApplicationReject => _t('رفض', 'Reject');
  String get adminApplicationApproveTitle =>
      _t('اعتماد هذا الطلب؟', 'Approve this application?');
  String get adminApplicationApproveBody => _t(
    'سيتحول الحساب إلى حساب طبيب ويُطلب منه تسجيل دخول جديد. لا يمكن التراجع عن هذا الإجراء من التطبيق.',
    'The account becomes a doctor account and will be asked to sign in again. This cannot be undone from the app.',
  );
  String get adminApplicationRejectTitle =>
      _t('رفض هذا الطلب؟', 'Reject this application?');
  String get adminApplicationRejectBody => _t(
    'سيُبلَّغ مقدّم الطلب بالرفض مع السبب الذي تكتبه.',
    'The applicant is notified of the rejection together with the reason you write.',
  );
  String get adminApplicationRejectReasonLabel =>
      _t('سبب الرفض', 'Rejection reason');
  String get adminApplicationRejectReasonHint =>
      _t('اشرح سبب الرفض للمتقدّم', 'Explain the decision to the applicant');
  String get adminApplicationRejectReasonRequired =>
      _t('سبب الرفض مطلوب.', 'A rejection reason is required.');
  String get adminApplicationApprovedSuccess =>
      _t('تم اعتماد الطلب.', 'The application was approved.');
  String get adminApplicationRejectedSuccess =>
      _t('تم رفض الطلب.', 'The application was rejected.');
  String get adminApplicationDecidedNote => _t(
    'تمت مراجعة هذا الطلب بالفعل.',
    'This application has already been reviewed.',
  );
  String adminApplicationYears(int years) => _t('$years سنة', '$years years');

  // ── Admin invitations (super_admin) ────────────────────────────────────
  String get adminInvitationsTitle => _t('دعوات المشرفين', 'Admin invitations');
  String get adminInvitationsSubtitle => _t(
    'ادعُ حسابات موثقة وأدر الدعوات المعلقة.',
    'Invite verified accounts and manage pending invitations.',
  );
  String get adminInvitationEmailLabel =>
      _t('البريد الإلكتروني للحساب', 'Account email');
  String get adminInvitationSend => _t('إرسال الدعوة', 'Send invitation');
  String get adminInvitationPendingSection =>
      _t('الدعوات المعلقة', 'Pending invitations');
  String get adminInvitationHistorySection =>
      _t('دعوات سابقة', 'Past invitations');
  String get adminInvitationStatusPending => _t('معلقة', 'Pending');
  String get adminInvitationStatusAccepted => _t('مقبولة', 'Accepted');
  String get adminInvitationStatusRevoked => _t('ملغاة', 'Revoked');
  String get adminInvitationStatusExpired => _t('منتهية', 'Expired');
  String get adminInvitationRevoke => _t('إلغاء الدعوة', 'Revoke');
  String adminInvitationRevokeTitle(String email) =>
      _t('إلغاء دعوة $email؟', 'Revoke the invitation for $email?');
  String get adminInvitationRevokeBody => _t(
    'لن يعود الرابط صالحاً. يمكنك إرسال دعوة جديدة لاحقاً.',
    'The link stops working. You can send a new invitation later.',
  );
  String get adminInvitationRevokedSuccess =>
      _t('تم إلغاء الدعوة.', 'The invitation was revoked.');
  String get adminInvitationCreatedSent => _t(
    'تم إنشاء الدعوة وإرسال البريد. يظهر رابط احتياطي أدناه.',
    'Invitation created and emailed. A backup link is shown below.',
  );
  String get adminInvitationCreatedManual => _t(
    'تم إنشاء الدعوة، لكن يلزم تسليم الرابط يدوياً.',
    'Invitation created, but the link needs manual delivery.',
  );
  String get adminInvitationLinkTitle =>
      _t('رابط القبول لمرة واحدة', 'One-time acceptance link');
  String get adminInvitationLinkHint => _t(
    'أرسل هذا الرابط إلى البريد المدعو فقط. يظهر مرة واحدة ولن يمكن استرجاعه لاحقاً.',
    'Send this link only to the invited email address. It is shown once and cannot be retrieved later.',
  );
  String get adminInvitationLinkHide => _t('إخفاء الرابط', 'Hide link');
  String get adminInvitationExpiresOn => _t('تنتهي في', 'Expires');
  String get adminInvitationCreatedOn => _t('أُنشئت في', 'Created');
  String get adminInvitationsEmptyTitle =>
      _t('لا توجد دعوات', 'No invitations');
  String get adminInvitationsEmptyHint => _t(
    'لم يتم إنشاء أي دعوة مشرف بعد.',
    'No administrator invitation has been created yet.',
  );

  // ── Invitation acceptance (the invited account) ────────────────────────
  String get adminInvitationAcceptTitle =>
      _t('قبول دعوة الإشراف', 'Accept admin invitation');
  String get adminInvitationAcceptSubtitle => _t(
    'الصق رابط الدعوة أو الرمز الذي وصلك، ثم أكّد القبول من هذا الحساب.',
    'Paste the invitation link or code you received, then confirm from this account.',
  );
  String get adminInvitationAcceptEntryHint => _t(
    'إن وصلتك دعوة لتصبح مشرفاً، الصق رابطها هنا لقبولها.',
    'If you were invited to become an administrator, paste the invitation link here to accept it.',
  );
  String get adminInvitationAcceptTokenLabel =>
      _t('رابط الدعوة أو الرمز', 'Invitation link or code');
  String get adminInvitationAcceptTokenHint =>
      _t('الصق الرابط كاملاً', 'Paste the full link');
  String get adminInvitationAcceptTokenHelper => _t(
    'يجب أن تكون مسجلاً الدخول بالحساب الذي وُجهت إليه الدعوة.',
    'You must be signed in as the account the invitation was addressed to.',
  );
  String get adminInvitationAcceptTokenRequired =>
      _t('أدخل رابط الدعوة أو الرمز.', 'Enter the invitation link or code.');
  String get adminInvitationAcceptSubmit =>
      _t('قبول الدعوة', 'Accept invitation');
  String get adminInvitationAcceptSuccessTitle =>
      _t('تم قبول الدعوة', 'Invitation accepted');
  String get adminInvitationAcceptSuccessBody => _t(
    'أصبح حسابك حساب مشرف. سجّل الخروج ثم الدخول من جديد لتفعيل الصلاحيات.',
    'Your account is now an administrator account. Sign out and sign in again to activate the new permissions.',
  );
  String get adminInvitationAcceptSignOut =>
      _t('تسجيل الخروج الآن', 'Sign out now');
  String get adminInvitationAcceptAlreadyAdminTitle =>
      _t('حسابك مشرف بالفعل', 'This account is already an administrator');
  String get adminInvitationAcceptAlreadyAdminBody => _t(
    'لا حاجة لقبول دعوة على هذا الحساب.',
    'There is no invitation to accept on this account.',
  );

  // ── Contact inbox ──────────────────────────────────────────────────────
  String get adminContactTitle => _t('رسائل التواصل', 'Contact messages');
  String get adminContactSubtitle => _t(
    'راجع طلبات الدعم الجديدة وحافظ على تحديث حالتها.',
    'Review new support requests and keep their status current.',
  );
  String get adminContactStatusNew => _t('جديدة', 'New');
  String get adminContactStatusRead => _t('مقروءة', 'Read');
  String get adminContactStatusResolved => _t('محلولة', 'Resolved');
  String get adminContactEmptyTitle => _t('لا توجد رسائل', 'No messages');
  String get adminContactEmptyHint =>
      _t('لا توجد رسائل بهذه الحالة.', 'There are no messages in this state.');
  String get adminContactSender => _t('المرسل', 'From');
  String get adminContactReceived => _t('وصلت في', 'Received');
  String get adminContactMessageLabel => _t('نص الرسالة', 'Message');
  String get adminContactSenderVerified =>
      _t('حساب مسجّل', 'Signed-in account');
  String get adminContactResolve => _t('وضع علامة كمحلولة', 'Mark resolved');
  String get adminContactResolveTitle =>
      _t('وضع علامة كمحلولة؟', 'Mark this message resolved?');
  String get adminContactResolveBody => _t(
    'ستنتقل الرسالة إلى الحالة "محلولة" وتُسجَّل باسمك.',
    'The message moves to the resolved state and is recorded against your account.',
  );
  String get adminContactResolvedSuccess => _t(
    'تم وضع علامة على الرسالة كمحلولة.',
    'The message was marked resolved.',
  );
  String get adminContactAutoReadNote => _t(
    'تُوضع علامة "مقروءة" تلقائياً عند فتح رسالة جديدة.',
    'Opening a new message marks it as read automatically.',
  );

  // ── Content moderation ─────────────────────────────────────────────────
  String get adminModerationTitle => _t('مراجعة المحتوى', 'Content moderation');
  String get adminModerationSubtitle => _t(
    'اعتمد أو ارفض أو أخفِ منشورات الأطباء وتعليقات المستخدمين.',
    'Approve, reject, or hide doctor posts and user comments.',
  );
  String get adminModerationPostsTab => _t('المنشورات', 'Posts');
  String get adminModerationCommentsTab => _t('التعليقات', 'Comments');
  String get adminModerationStatusPending => _t('قيد المراجعة', 'Pending');
  String get adminModerationStatusApproved => _t('معتمد', 'Approved');
  String get adminModerationStatusRejected => _t('مرفوض', 'Rejected');
  String get adminModerationStatusHidden => _t('مخفي', 'Hidden');
  String get adminModerationApprove => _t('اعتماد', 'Approve');
  String get adminModerationReject => _t('رفض', 'Reject');
  String get adminModerationHide => _t('إخفاء', 'Hide');
  String get adminModerationApproveTitle =>
      _t('اعتماد هذا المحتوى؟', 'Approve this content?');
  String get adminModerationApproveBody => _t(
    'سيصبح المحتوى مرئياً للمستخدمين في الخلاصة.',
    'The content becomes visible to users in the feed.',
  );
  String get adminModerationRejectTitle =>
      _t('رفض هذا المحتوى؟', 'Reject this content?');
  String get adminModerationRejectBody => _t(
    'سيُخفى المحتوى عن الخلاصة ويُسجَّل كمرفوض.',
    'The content is removed from the feed and recorded as rejected.',
  );
  String get adminModerationHideTitle =>
      _t('إخفاء هذا المحتوى؟', 'Hide this content?');
  String get adminModerationHideBody => _t(
    'سيُخفى المحتوى عن الخلاصة ويمكن اعتماده لاحقاً.',
    'The content is hidden from the feed and can be approved again later.',
  );
  String get adminModerationSuccess =>
      _t('تم تطبيق قرار المراجعة.', 'The moderation decision was applied.');
  String get adminModerationPostsEmptyTitle =>
      _t('لا توجد منشورات', 'No posts');
  String get adminModerationCommentsEmptyTitle =>
      _t('لا توجد تعليقات', 'No comments');
  String get adminModerationEmptyHint =>
      _t('لا يوجد محتوى بهذه الحالة.', 'There is no content in this state.');
  String get adminModerationUntitled => _t('بدون عنوان', 'Untitled');
  String get adminModerationPublishState => _t('حالة النشر', 'Publish state');
  String get adminModerationLimitNote => _t(
    'يعرض الخادم أحدث ١٠٠ عنصر.',
    'The server returns the 100 most recent items.',
  );

  // ── Audit log (read only) ──────────────────────────────────────────────
  String get adminAuditTitle => _t('سجل التدقيق', 'Audit log');
  String get adminAuditSubtitle => _t(
    'سجل للقراءة فقط بالإجراءات الإدارية. لا يمكن تعديله أو حذفه.',
    'A read-only record of administrative actions. It cannot be edited or deleted.',
  );
  String get adminAuditRangeDay => _t('٢٤ ساعة', '24 hours');
  String get adminAuditRangeWeek => _t('٧ أيام', '7 days');
  String get adminAuditRangeMonth => _t('٣٠ يوماً', '30 days');
  String get adminAuditRangeLabel => _t('الفترة', 'Time range');
  String get adminAuditEntityLabel => _t('نوع السجل', 'Entity type');
  String get adminAuditEmptyTitle => _t('لا توجد أحداث', 'No events');
  String get adminAuditEmptyHint => _t(
    'لا توجد إجراءات مسجّلة ضمن هذه الفترة.',
    'No actions were recorded in this range.',
  );
  String get adminAuditActor => _t('المنفّذ', 'Performed by');
  String get adminAuditEntity => _t('السجل', 'Entity');
  String get adminAuditWhen => _t('التوقيت', 'When');
  String get adminAuditIpAddress => _t('عنوان IP', 'IP address');
  String get adminAuditUserAgent => _t('العميل', 'Client');
  String get adminAuditPayloadNote => _t(
    'لا يعرض التطبيق محتوى الحقول القديمة/الجديدة لأنها قد تتضمن بيانات شخصية أو مهنية.',
    'Before/after field values are not shown in the app: they can contain personal or professional detail.',
  );
  String get adminAuditSystemActor => _t('النظام', 'System');
  String get adminAuditAction => _t('الإجراء', 'Action');
  String adminAuditTruncatedNote(int limit) => _t(
    'يعرض أحدث $limit حدثاً فقط. ضيّق الفترة أو نوع السجل لرؤية المزيد.',
    'Showing only the $limit most recent events. Narrow the range or entity type to see more.',
  );

  /// Safe localized copy for an administration backend/transport error code.
  ///
  /// Never renders a backend message: the administration endpoints quote
  /// account emails, invitation state, and moderation targets in theirs.
  /// Codes verified against `admin.routes.js`, `admin-invitation.routes.js`,
  /// `doctor-application.routes.js`, `contact.routes.js`, `social.routes.js`,
  /// `audit-log.routes.js`, `middleware/errorHandler.js`, and the transport
  /// codes on [ApiException].
  String adminError(String? code) => switch (code) {
    'UNAUTHORIZED' || 'TOKEN_EXPIRED' => _t(
      'انتهت جلستك. سجّل الدخول من جديد ثم حاول مجدداً.',
      'Your session has expired. Sign in again and try once more.',
    ),
    'FORBIDDEN' => _t(
      'حسابك لا يملك صلاحية تنفيذ هذا الإجراء.',
      'Your account is not allowed to perform this action.',
    ),
    'NOT_FOUND' => _t(
      'لم يعد هذا العنصر متاحاً. حدّث القائمة.',
      'This item is no longer available. Refresh the list.',
    ),
    'VALIDATION_ERROR' || 'INVALID_FORMAT' || 'INVALID_REFERENCE' => _t(
      'تحقّق من البيانات المدخلة ثم حاول مرة أخرى.',
      'Check the details you entered and try again.',
    ),
    'DUPLICATE_ENTRY' => _t(
      'هذا العنصر موجود بالفعل.',
      'This item already exists.',
    ),
    'INVALID_TARGET' => _t(
      'هذا الحساب غير مؤهل لهذا الإجراء.',
      'This account is not eligible for that action.',
    ),
    'INVITATION_EXISTS' => _t(
      'توجد دعوة نشطة لهذا البريد بالفعل.',
      'An active invitation already exists for this email.',
    ),
    'INVITATION_UNAVAILABLE' => _t(
      'لم تعد هذه الدعوة متاحة.',
      'This invitation is no longer available.',
    ),
    'INVITATION_EXPIRED' => _t(
      'انتهت صلاحية هذه الدعوة. اطلب دعوة جديدة.',
      'This invitation has expired. Ask for a new one.',
    ),
    'INVALID_INVITATION' => _t(
      'رابط أو رمز الدعوة غير صحيح.',
      'That invitation link or code is not valid.',
    ),
    'INVITATION_ACCOUNT_MISMATCH' => _t(
      'هذه الدعوة موجهة لحساب آخر. سجّل الدخول بالحساب المدعو.',
      'This invitation belongs to a different account. Sign in as the invited account.',
    ),
    'RATE_LIMITED' || 'CONTACT_RATE_LIMITED' => _t(
      'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.',
      'Too many attempts. Wait a little while and try again.',
    ),
    'INVALID_RESPONSE' => _t(
      'وصل رد غير مكتمل من الخادم. أعد المحاولة.',
      'The server sent an incomplete response. Please try again.',
    ),
    'CONNECT_TIMEOUT' ||
    'SEND_TIMEOUT' ||
    'RECEIVE_TIMEOUT' ||
    'SERVICE_UNAVAILABLE' ||
    'CERTIFICATE_ERROR' => _t(
      'تعذّر الوصول إلى الخدمة. تحقّق من اتصالك ثم حاول مرة أخرى.',
      'Could not reach the service. Check your connection and try again.',
    ),
    _ => _t(
      'حدث خطأ ما. حاول مرة أخرى.',
      'Something went wrong. Please try again.',
    ),
  };

  // ================================================================
  // DIRECT MESSAGING / CARE MESSAGES
  // ================================================================
  String get messagesTitle => _t('رسائل الرعاية', 'Care Messages');
  String get messagesSubtitle => _t(
    'محادثات نصية خاصة وآمنة بين المرضى والأطباء داخل MedOrbit',
    'Private, secure text conversations between patients and doctors in MedOrbit',
  );
  String get messagesNew => _t('رسالة جديدة', 'New message');
  String get messagesMessageDoctor => _t('مراسلة الطبيب', 'Message doctor');
  String get messagesNewTitle =>
      _t('بدء محادثة نصية', 'Start a text conversation');
  String get messagesThreadTitle => _t('المحادثة', 'Conversation');
  String get messagesRoleDoctor => _t('طبيب', 'Doctor');
  String get messagesRolePatient => _t('مريض', 'Patient');
  String get messagesVerifiedDoctor => _t('طبيب معتمد', 'Approved doctor');
  String get messagesPatientOpenToRequests =>
      _t('مريض يقبل طلبات المراسلة', 'Patient open to message requests');
  String get messagesUnknownUser => _t('مستخدم MedOrbit', 'MedOrbit user');
  String get messagesYou => _t('أنت', 'You');
  String get messagesCounterpart => _t('الطرف الآخر', 'Other person');
  String get messagesInboxEmptyTitle =>
      _t('لا توجد محادثات بعد', 'No conversations yet');
  String get messagesInboxEmptyHint => _t(
    'ابدأ من زر رسالة جديدة للعثور على مستلم مؤهل.',
    'Use New message to find an eligible recipient.',
  );
  String get messagesStartPreview =>
      _t('ابدأ المحادثة', 'Start the conversation');
  String get messagesRequestPendingPreview =>
      _t('طلب مراسلة بانتظار الرد', 'Message request awaiting response');
  String get messagesInboxLoadError =>
      _t('تعذر تحميل المحادثات', 'Could not load conversations');
  String get messagesThreadLoadError =>
      _t('تعذر تحميل الرسائل', 'Could not load messages');
  String get messagesSearchError =>
      _t('تعذر البحث عن المستلمين', 'Could not search recipients');
  String get messagesTextOnlyNotice => _t(
    'هذه الخدمة للمراسلة النصية فقط، ولا تمنح بحد ذاتها صلاحية الوصول إلى السجلات الطبية.',
    'This service is for text messaging only. It does not itself grant access to medical records.',
  );
  String messagesUnreadCount(int count) => _t(
    '$count رسالة غير مقروءة',
    '$count unread message${count == 1 ? '' : 's'}',
  );
  String get messagesPatientRecipientHint => _t(
    'ابحث عن طبيب معتمد بالاسم أو التخصص.',
    'Find an approved doctor by name or specialty.',
  );
  String get messagesDoctorRecipientHint => _t(
    'ابحث عن طبيب معتمد أو مريض اختار استقبال طلبات الأطباء.',
    'Find an approved doctor or a patient who opted in to doctor requests.',
  );
  String get messagesRecipientSearchLabel =>
      _t('بحث عن مستلم', 'Find a recipient');
  String get messagesRecipientSearchHint =>
      _t('الاسم أو التخصص أو المدينة', 'Name, specialty, or city');
  String get messagesSearch => _t('بحث', 'Search');
  String get messagesSearching => _t('جارٍ البحث...', 'Searching...');
  String get messagesNoEligibleRecipients =>
      _t('لا توجد نتائج مؤهلة', 'No eligible recipients');
  String get messagesNoEligibleRecipientsHint => _t(
    'غيّر عبارة البحث أو حاول لاحقًا. تظهر للأطباء فقط ملفات المرضى الذين اختاروا استقبال الطلبات.',
    'Try another search. Doctors only see patients who opted in to requests.',
  );
  String get messagesStartingConversation =>
      _t('جارٍ فتح المحادثة...', 'Opening conversation...');
  String get messagesRequestSent =>
      _t('تم إرسال طلب مراسلة آمن.', 'A secure message request was sent.');
  String get messagesThreadEmptyTitle =>
      _t('لا توجد رسائل بعد', 'No messages yet');
  String get messagesThreadEmptyHint =>
      _t('ابدأ بتحية واضحة.', 'Start with a clear greeting.');
  String get messagesPendingEmptyTitle =>
      _t('الطلب بانتظار الرد', 'Request awaiting response');
  String get messagesPendingComposerDisabled => _t(
    'تُفتح الرسائل بعد قبول المريض للطلب.',
    'Messaging unlocks after the patient accepts the request.',
  );
  String get messagesHistoryLabel => _t('سجل الرسائل', 'Message history');
  String get messagesLoadOlder => _t('تحميل رسائل أقدم', 'Load older messages');
  String get messagesJumpToLatest =>
      _t('الانتقال إلى أحدث رسالة', 'Jump to latest message');
  String get messagesComposerHint =>
      _t('اكتب رسالة نصية...', 'Write a text message...');
  String get messagesSend => _t('إرسال', 'Send');
  String get messagesSending => _t('جارٍ الإرسال...', 'Sending...');
  String get messagesSendFailed => _t('تعذر الإرسال', 'Send failed');
  String get messagesDismiss => _t('إخفاء', 'Dismiss');
  String get messagesIncomingRequestTitle =>
      _t('طلب مراسلة من طبيب معتمد', 'Message request from an approved doctor');
  String get messagesOutgoingRequestTitle =>
      _t('طلب المراسلة بانتظار المريض', 'Message request awaiting the patient');
  String get messagesRequestTextOnlyWarning => _t(
    'قبول الطلب يفتح المراسلة النصية فقط ولا يمنح أي صلاحية طبية أو وصول إلى السجلات.',
    'Accepting opens text messaging only. It grants no clinical access or medical-record permission.',
  );
  String get messagesOutgoingRequestHint => _t(
    'لن تتمكن من إرسال رسالة حتى يقبل المريض الطلب.',
    'You cannot send until the patient accepts the request.',
  );
  String get messagesAccept => _t('قبول', 'Accept');
  String get messagesDecline => _t('رفض', 'Decline');
  String get messagesRequestAccepted =>
      _t('تم قبول طلب المراسلة.', 'Message request accepted.');
  String get messagesDeclineTitle =>
      _t('رفض طلب المراسلة؟', 'Decline this message request?');
  String get messagesDeclineBody => _t(
    'سيُغلق الطلب ولن يتمكن الطبيب من إرسال رسائل في هذه المحادثة.',
    'The request will close and the doctor will not be able to send messages in this conversation.',
  );
  String get messagesConnecting => _t('جارٍ الاتصال...', 'Connecting...');
  String get messagesConnected => _t('متصل', 'Connected');
  String get messagesReconnecting =>
      _t('جارٍ إعادة الاتصال...', 'Reconnecting...');
  String get messagesLiveUnavailable => _t(
    'التحديث المباشر غير متاح. سنواصل مزامنة الرسائل بأمان.',
    'Live updates are unavailable. Messages will continue to sync safely.',
  );
  String get messagesNotificationType => _t('رسائل الرعاية', 'Care message');
  String get messagesOpenConversation =>
      _t('فتح المحادثة', 'Open conversation');
  String get messagesPrivacyTitle =>
      _t('السماح بطلبات مراسلة الأطباء', 'Allow doctor message requests');
  String get messagesPrivacyHelp => _t(
    'عند التفعيل، يمكن للأطباء المعتمدين العثور على ملفك وبدء طلب مراسلة جديد. لا تتأثر المحادثات المقبولة الحالية عند الإيقاف.',
    'When enabled, approved doctors can find your profile and start a new message request. Existing accepted conversations are unaffected when disabled.',
  );

  String messagingError(String? code) => switch (code) {
    'UNAUTHORIZED' => _t(
      'انتهت جلستك. سجّل الدخول من جديد ثم حاول مرة أخرى.',
      'Your session has expired. Sign in again and retry.',
    ),
    'FORBIDDEN' || 'MESSAGING_FORBIDDEN' => _t(
      'لا يملك هذا الحساب صلاحية تنفيذ إجراء المراسلة المطلوب.',
      'This account cannot perform the requested messaging action.',
    ),
    'NOT_FOUND' => _t(
      'لم تعد المحادثة أو جهة الاتصال متاحة.',
      'This conversation or recipient is no longer available.',
    ),
    'REQUEST_NOT_PENDING' => _t(
      'تمت معالجة طلب المراسلة بالفعل. حدّث المحادثة لرؤية حالته الحالية.',
      'This request was already handled. Refresh to see its current status.',
    ),
    'MESSAGE_REQUEST_COOLDOWN' => _t(
      'لا يمكن إرسال طلب جديد إلى هذا المريض حاليًا. حاول لاحقًا.',
      'A new request cannot be sent to this patient yet. Try again later.',
    ),
    'MESSAGE_REQUEST_RATE_LIMITED' || 'RATE_LIMITED' => _t(
      'تم إجراء محاولات كثيرة. انتظر قليلًا ثم حاول مرة أخرى.',
      'Too many attempts. Wait a little while and try again.',
    ),
    'VALIDATION_ERROR' || 'INVALID_FORMAT' => _t(
      'تحقق من البيانات المدخلة ثم حاول مرة أخرى.',
      'Check the entered information and try again.',
    ),
    'CONNECT_TIMEOUT' ||
    'SEND_TIMEOUT' ||
    'RECEIVE_TIMEOUT' ||
    'SERVICE_UNAVAILABLE' => _t(
      'تعذر الوصول إلى الخدمة. تحقق من اتصالك ثم حاول مرة أخرى.',
      'Could not reach the service. Check your connection and try again.',
    ),
    'INVALID_RESPONSE' || 'EMPTY_RESPONSE' => _t(
      'وصل رد غير مكتمل من الخدمة. حاول مرة أخرى.',
      'The service returned an incomplete response. Please retry.',
    ),
    _ => _t(
      'تعذر إكمال الإجراء. حاول مرة أخرى.',
      'The action could not be completed. Please try again.',
    ),
  };
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(localeControllerProvider);
  return AppStrings(locale.languageCode == 'ar');
});

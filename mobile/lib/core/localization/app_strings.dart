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
  String get resetLinkSentTitle => _t('تحقق من بريدك الإلكتروني', 'Check your email');
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

  String? verificationError(String? code, String? fallback) => switch (code) {
    'INVALID_VERIFICATION_TOKEN' => invalidVerificationCode,
    'VERIFICATION_TOKEN_EXPIRED' => expiredVerificationCode,
    'VERIFICATION_TOKEN_USED' => usedVerificationCode,
    'RATE_LIMITED' => verificationRateLimited,
    'VALIDATION_ERROR' => verificationValidationError,
    null => fallback,
    _ => fallback ?? errorGeneric,
  };

  // Bottom nav
  String get navHome => _t('الرئيسية', 'Home');
  String get navRecords => _t('السجلات', 'Records');
  String get navPrescriptions => _t('الوصفات', 'Prescriptions');
  String get navAppointments => _t('المواعيد', 'Appointments');
  String get navFeedback => _t('آراؤكم', 'Feedback');

  // Home
  String get welcomeBack => _t('مرحبًا بعودتك', 'Welcome back');
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
    'لا تتضمن حسابات الإدارة بيانات صحية أو أدوات طبية. استخدم لوحة الويب لإدارة الطلبات والمستخدمين وإعدادات النظام.',
    'Administration accounts do not include health data or medical tools. Use the web dashboard to manage applications, users, and system settings.',
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
  String get doctorInfoSubSpecialty =>
      _t('تخصص فرعي', 'Sub-specialty');
  String get doctorInfoExpertise =>
      _t('مجالات الخبرة', 'Areas of expertise');
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
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(localeControllerProvider);
  return AppStrings(locale.languageCode == 'ar');
});

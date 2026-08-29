import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_page_frame.dart';
import '../widgets/otp_code_input.dart';

class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({super.key, this.initialToken, this.initialEmail});

  final String? initialToken;
  final String? initialEmail;

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _otpKey = GlobalKey<OtpCodeInputState>();
  final _emailController = TextEditingController();

  Timer? _resendTimer;
  String _code = '';
  String _initialCode = '';
  String? _localError;
  int _resendSeconds = 0;
  bool _verified = false;
  bool _verifyInFlight = false;
  bool _resendInFlight = false;
  bool _resent = false;
  bool _checkingLink = false;

  /// True once THIS screen has made a verify or resend attempt. A shared
  /// [AuthState] error is only rendered while this is set, so an error left
  /// behind by Login / Register / Forgot / Reset can never be shown here.
  bool _attempted = false;

  String get _normalizedEmail => _emailController.text.trim().toLowerCase();
  bool get _hasRegistrationEmail => (widget.initialEmail ?? '').trim().isNotEmpty;

  String? _validateEmail(String? value, AppStrings strings) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return strings.emailRequired;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return strings.invalidEmail;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _emailController.text = (widget.initialEmail ?? '').trim().toLowerCase();
    final initialToken = (widget.initialToken ?? '').trim();

    if (_hasRegistrationEmail) _startResendCountdown();
    if (RegExp(r'^\d{6}$').hasMatch(initialToken)) {
      _initialCode = initialToken;
      _code = initialToken;
      _scheduleStaleErrorClear();
    } else if (initialToken.isNotEmpty) {
      // A real verification link — auto-verify exactly once, mirroring the web
      // verify-email page. verifyEmail() clears any prior auth error itself.
      WidgetsBinding.instance.addPostFrameCallback((_) => _verifyLink(initialToken));
    } else {
      _scheduleStaleErrorClear();
    }
  }

  /// Drops an error left on the shared [AuthState] by Login / Register / Forgot
  /// Password / Reset Password so it can never flash as this screen's own
  /// error. Deferred to after the first frame — mutating a Riverpod provider
  /// synchronously inside initState throws "Tried to modify a provider while
  /// the widget tree was building".
  void _scheduleStaleErrorClear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(authControllerProvider).errorMessage != null) {
        ref.read(authControllerProvider.notifier).clearError();
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    if (mounted) {
      setState(() => _resendSeconds = 60);
    } else {
      _resendSeconds = 60;
    }
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  String _maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2 || parts.first.isEmpty) return email;
    final local = parts.first;
    final hiddenCount = local.length <= 2 ? 1 : (local.length - 2 > 5 ? 5 : local.length - 2);
    final maskedLocal = local.length == 1
        ? '${local[0]}***'
        : '${local[0]}${List.filled(hiddenCount, '*').join()}${local[local.length - 1]}';
    final domainParts = parts.last.split('.');
    final domainName = domainParts.first;
    final maskedDomain = domainName.isEmpty ? '***' : '${domainName[0]}***';
    final suffix = domainParts.length > 1 ? '.${domainParts.skip(1).join('.')}' : '';
    return '$maskedLocal@$maskedDomain$suffix';
  }

  Future<void> _verifyLink(String token) async {
    if (_verifyInFlight) return;
    setState(() {
      _checkingLink = true;
      _verifyInFlight = true;
      _attempted = true;
      _localError = null;
    });
    final success = await ref.read(authControllerProvider.notifier).verifyEmail(token: token);
    if (!mounted) return;
    setState(() {
      _checkingLink = false;
      _verifyInFlight = false;
      _verified = success;
    });
  }

  Future<void> _verifyCode([String? completedCode]) async {
    if (_verifyInFlight || ref.read(authControllerProvider).isSubmitting) return;
    final code = completedCode ?? _code;
    final strings = ref.read(appStringsProvider);

    if (code.length != 6) {
      setState(() => _localError = strings.otpIncomplete);
      return;
    }
    final emailError = _validateEmail(_normalizedEmail, strings);
    if (emailError != null) {
      setState(() => _localError = emailError);
      return;
    }
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _verifyInFlight = true;
      _attempted = true;
      _localError = null;
    });
    final success = await ref.read(authControllerProvider.notifier).verifyEmail(
          token: code,
          email: _normalizedEmail,
        );
    if (!mounted) return;

    final errorCode = ref.read(authControllerProvider).errorCode;
    setState(() {
      _verifyInFlight = false;
      _verified = success;
    });
    if (!success && (errorCode == 'INVALID_VERIFICATION_TOKEN' || errorCode == 'VERIFICATION_TOKEN_EXPIRED')) {
      _code = '';
      _otpKey.currentState?.clear(notify: false);
    }
  }

  Future<void> _resend() async {
    if (_resendSeconds > 0 || _resendInFlight || ref.read(authControllerProvider).isSubmitting) return;
    final emailError = _validateEmail(_normalizedEmail, ref.read(appStringsProvider));
    if (emailError != null) {
      setState(() => _localError = emailError);
      return;
    }
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _resendInFlight = true;
      _attempted = true;
      _resent = false;
      _localError = null;
    });
    final success = await ref.read(authControllerProvider.notifier).resendVerification(_normalizedEmail);
    if (!mounted) return;
    setState(() {
      _resendInFlight = false;
      _resent = success;
    });
    if (success) {
      _otpKey.currentState?.clear();
      _startResendCountdown();
    }
  }

  void _onCodeChanged(String value) {
    _code = value;
    if (_localError != null || _attempted || ref.read(authControllerProvider).errorMessage != null) {
      setState(() {
        _localError = null;
        _attempted = false;
      });
      ref.read(authControllerProvider.notifier).clearError();
    }
  }

  Widget _errorMessage(AuthState authState, AppStrings strings) {
    final message = _localError ??
        strings.verificationError(
          authState.errorCode,
          hadError: _attempted && authState.errorMessage != null,
        );
    if (message == null) return const SizedBox.shrink();
    return InlineMessage(message: message, tone: InlineMessageTone.error);
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final busy = authState.isSubmitting || _verifyInFlight || _resendInFlight;

    return AuthPageFrame(
      title: strings.verifyCodeTitle,
      subtitle: strings.verificationStepTwo,
      icon: Icons.mark_email_read_rounded,
      leading: BackButton(onPressed: busy ? null : () => context.go(RoutePaths.login)),
      actions: [
        IconButton(
          tooltip: strings.languageToggleTooltip,
          onPressed: busy ? null : () => ref.read(localeControllerProvider.notifier).toggle(),
          icon: const Icon(Icons.translate_rounded),
        ),
      ],
      body: _verified
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FeatureCard(
                  title: strings.verifySuccessTitle,
                  subtitle: strings.verifySuccessHint,
                  icon: Icons.check_circle_outline_rounded,
                  color: AppTheme.success,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                PrimaryButton(label: strings.backToLogin, onPressed: () => context.go(RoutePaths.login)),
              ],
            )
          : _checkingLink
              ? Semantics(
                  liveRegion: true,
                  label: strings.verifyingEmail,
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppTheme.space2xl),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              : Form(
                  key: _emailFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(title: strings.verificationStepTwo, subtitle: strings.verifyCodeSubtitle),
                      FeatureCard(
                        title: strings.codeSentTitle,
                        subtitle: _normalizedEmail.isEmpty
                            ? strings.enterEmailToVerify
                            : strings.codeSentTo('\u2066${_maskEmail(_normalizedEmail)}\u2069'),
                        icon: Icons.alternate_email_rounded,
                        color: AppTheme.secondary,
                      ),
                      const SizedBox(height: AppTheme.spaceMd),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spaceLg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!_hasRegistrationEmail) ...[
                                AppTextField(
                                  label: strings.emailLabel,
                                  hintText: strings.emailPlaceholder,
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) => _validateEmail(value, strings),
                                  autofillHints: const [AutofillHints.email],
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  textDirection: TextDirection.ltr,
                                  prefixIcon: const Icon(Icons.mail_outline_rounded, size: AppTheme.iconMd),
                                  onChanged: (_) {
                                    setState(() {
                                      _localError = null;
                                      _attempted = false;
                                    });
                                    ref.read(authControllerProvider.notifier).clearError();
                                  },
                                ),
                                const SizedBox(height: AppTheme.spaceLg),
                              ],
                              Text(strings.enterSixDigitCode, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: AppTheme.spaceMd),
                              OtpCodeInput(
                                key: _otpKey,
                                initialCode: _initialCode,
                                enabled: !busy,
                                digitLabel: strings.otpDigitLabel,
                                onChanged: _onCodeChanged,
                                onCompleted: _verifyCode,
                              ),
                              if (_localError != null ||
                                  (_attempted && authState.errorMessage != null)) ...[
                                const SizedBox(height: AppTheme.spaceMd),
                                _errorMessage(authState, strings),
                              ],
                              const SizedBox(height: AppTheme.spaceLg),
                              PrimaryButton(
                                label: strings.verifyEmailButton,
                                isLoading: _verifyInFlight || (authState.isSubmitting && !_resendInFlight),
                                onPressed: busy ? null : _verifyCode,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceLg),
                      SectionHeader(title: strings.resendVerificationTitle, subtitle: strings.resendVerificationHint),
                      TextButton.icon(
                        onPressed: busy || _resendSeconds > 0 ? null : _resend,
                        icon: _resendInFlight
                            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.refresh_rounded),
                        label: Text(
                          _resendSeconds > 0 ? strings.resendIn(_resendSeconds) : strings.resendVerificationButton,
                        ),
                      ),
                      if (_resent) ...[
                        const SizedBox(height: AppTheme.spaceSm),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            strings.resendSuccess,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppTheme.spaceLg),
                      FeatureCard(
                        title: strings.backToLogin,
                        subtitle: strings.signInSubtitle,
                        icon: Icons.login_rounded,
                        color: AppTheme.primary,
                        onTap: busy ? null : () => context.go(RoutePaths.login),
                      ),
                    ],
                  ),
                ),
    );
  }
}

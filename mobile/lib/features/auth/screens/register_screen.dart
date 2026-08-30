import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_page_frame.dart';
import '../widgets/google_sign_in_button.dart';
import '../widgets/password_strength_meter.dart';

/// Matches the existing web frontend's registration form: patients only
/// (role is fixed server-side to `patient`, same as `frontend/public/register.html`).
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameArController = TextEditingController();
  final _lastNameArController = TextEditingController();
  final _firstNameEnController = TextEditingController();
  final _lastNameEnController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String _gender = 'male';
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;
  bool _showTermsError = false;

  @override
  void dispose() {
    _firstNameArController.dispose();
    _lastNameArController.dispose();
    _firstNameEnController.dispose();
    _lastNameEnController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validatePassword(String? value, AppStrings strings) {
    if (value == null || value.isEmpty) return strings.passwordRequired;
    if (value.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(value) ||
        !RegExp(r'[a-z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value) ||
        !RegExp(r'''[!@#$%^&*()_+\-=\[\]{};':"\\|,.<>/?]''').hasMatch(value)) {
      return strings.passwordPolicyError;
    }
    return null;
  }

  String? _validateEmail(String? value, AppStrings strings) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return strings.emailRequired;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return strings.invalidEmail;
    }
    return null;
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return ref.read(appStringsProvider).requiredField(label);
    }
    return null;
  }

  Future<void> _submit() async {
    final authState = ref.read(authControllerProvider);
    if (authState.isSubmitting) return;

    final validForm = _formKey.currentState!.validate();
    setState(() => _showTermsError = !_acceptedTerms);
    if (!validForm || !_acceptedTerms) return;

    FocusManager.instance.primaryFocus?.unfocus();
    final normalizedEmail = _emailController.text.trim().toLowerCase();

    final success = await ref
        .read(authControllerProvider.notifier)
        .register(
          email: normalizedEmail,
          password: _passwordController.text,
          firstNameAr: _firstNameArController.text.trim(),
          lastNameAr: _lastNameArController.text.trim(),
          firstNameEn: _firstNameEnController.text.trim(),
          lastNameEn: _lastNameEnController.text.trim(),
          phone: _phoneController.text.trim(),
          gender: _gender,
        );

    if (!mounted) return;
    if (success) {
      TextInput.finishAutofillContext();
      context.go(
        Uri(
          path: RoutePaths.verifyCode,
          queryParameters: {'email': normalizedEmail},
        ).toString(),
      );
    }
  }

  Future<void> _submitWithGoogle() async {
    if (ref.read(authControllerProvider).isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final success = await ref
        .read(authControllerProvider.notifier)
        .loginWithGoogle();
    if (!mounted) return;
    if (success) {
      context.go(RoutePaths.home);
    }
  }

  String _friendlyError(AppStrings strings, String? code) => switch (code) {
    'VALIDATION_ERROR' => strings.registrationValidationError,
    'RATE_LIMITED' => strings.authRateLimited,
    ApiException.codeConnectTimeout ||
    ApiException.codeSendTimeout ||
    ApiException.codeReceiveTimeout ||
    ApiException.codeServiceUnavailable => strings.authConnectionError,
    'GOOGLE_SIGN_IN_FAILED' => strings.googleSignInError,
    _ => strings.authRequestError,
  };

  void _clearError() {
    if (ref.read(authControllerProvider).errorMessage != null) {
      ref.read(authControllerProvider.notifier).clearError();
    }
  }

  Widget _namePair({
    required String firstLabel,
    required String firstHint,
    required TextEditingController firstController,
    required String secondLabel,
    required String secondHint,
    required TextEditingController secondController,
    required bool isWide,
    required TextDirection textDirection,
  }) {
    final firstField = AppTextField(
      label: firstLabel,
      hintText: firstHint,
      controller: firstController,
      validator: (value) => _required(value, firstLabel),
      onChanged: (_) => _clearError(),
      prefixIcon: const Icon(
        Icons.person_outline_rounded,
        size: AppTheme.iconMd,
      ),
      textCapitalization: TextCapitalization.words,
      textDirection: textDirection,
    );
    final secondField = AppTextField(
      label: secondLabel,
      hintText: secondHint,
      controller: secondController,
      validator: (value) => _required(value, secondLabel),
      onChanged: (_) => _clearError(),
      prefixIcon: const Icon(
        Icons.person_outline_rounded,
        size: AppTheme.iconMd,
      ),
      textCapitalization: TextCapitalization.words,
      textDirection: textDirection,
    );

    if (!isWide) {
      return Column(
        children: [
          firstField,
          const SizedBox(height: AppTheme.spaceMd),
          secondField,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: firstField),
        const SizedBox(width: AppTheme.spaceMd),
        Expanded(child: secondField),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);

    return AuthPageFrame(
      title: strings.createAccountTitle,
      subtitle: strings.registrationStepOne,
      icon: Icons.person_add_alt_1_rounded,
      actions: [
        IconButton(
          tooltip: strings.languageToggleTooltip,
          onPressed: () => ref.read(localeControllerProvider.notifier).toggle(),
          icon: const Icon(Icons.translate_rounded),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: strings.personalDetailsSection,
            subtitle: strings.registerSubtitle,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide =
                          constraints.maxWidth >= 520 &&
                          !AppTheme.usesLargeText(context);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _namePair(
                            firstLabel: strings.firstNameArLabel,
                            firstHint: 'أحمد',
                            firstController: _firstNameArController,
                            secondLabel: strings.lastNameArLabel,
                            secondHint: 'محمد',
                            secondController: _lastNameArController,
                            isWide: isWide,
                            textDirection: TextDirection.rtl,
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          _namePair(
                            firstLabel: strings.firstNameEnLabel,
                            firstHint: 'Ahmed',
                            firstController: _firstNameEnController,
                            secondLabel: strings.lastNameEnLabel,
                            secondHint: 'Mohammed',
                            secondController: _lastNameEnController,
                            isWide: isWide,
                            textDirection: TextDirection.ltr,
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          SectionHeader(
                            title: strings.contactSection,
                            padding: const EdgeInsets.only(
                              bottom: AppTheme.spaceSm,
                            ),
                          ),
                          AppTextField(
                            label: strings.emailLabel,
                            hintText: strings.emailPlaceholder,
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) =>
                                _validateEmail(value, strings),
                            onChanged: (_) => _clearError(),
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            textDirection: TextDirection.ltr,
                            prefixIcon: const Icon(
                              Icons.mail_outline_rounded,
                              size: AppTheme.iconMd,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          AppTextField(
                            label: strings.phoneOptionalLabel,
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => _clearError(),
                            textDirection: TextDirection.ltr,
                            prefixIcon: const Icon(
                              Icons.phone_outlined,
                              size: AppTheme.iconMd,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          SectionHeader(
                            title: strings.securitySection,
                            padding: const EdgeInsets.only(
                              bottom: AppTheme.spaceSm,
                            ),
                          ),
                          RadioGroup<String>(
                            groupValue: _gender,
                            onChanged: (value) {
                              _clearError();
                              setState(() => _gender = value!);
                            },
                            child: isWide
                                ? Row(
                                    children: [
                                      Expanded(
                                        child: RadioListTile<String>(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(strings.maleLabel),
                                          value: 'male',
                                        ),
                                      ),
                                      Expanded(
                                        child: RadioListTile<String>(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(strings.femaleLabel),
                                          value: 'female',
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      RadioListTile<String>(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(strings.maleLabel),
                                        value: 'male',
                                      ),
                                      RadioListTile<String>(
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(strings.femaleLabel),
                                        value: 'female',
                                      ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          AppTextField(
                            label: strings.passwordLabel,
                            hintText: strings.passwordPlaceholder,
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            validator: (value) =>
                                _validatePassword(value, strings),
                            onChanged: (_) => _clearError(),
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            textDirection: TextDirection.ltr,
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: AppTheme.iconMd,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword
                                  ? strings.showPassword
                                  : strings.hidePassword,
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppTheme.spaceSm),
                          AnimatedBuilder(
                            animation: _passwordController,
                            builder: (context, _) {
                              return PasswordStrengthMeter(
                                password: _passwordController.text,
                                hintText: strings.passwordStrengthHint,
                              );
                            },
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          AppTextField(
                            label: strings.confirmPasswordLabel,
                            hintText: strings.confirmPasswordPlaceholder,
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return strings.confirmPasswordRequired;
                              }
                              if (value != _passwordController.text) {
                                return strings.passwordMismatch;
                              }
                              return null;
                            },
                            onChanged: (_) => _clearError(),
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
                            autocorrect: false,
                            enableSuggestions: false,
                            textDirection: TextDirection.ltr,
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: AppTheme.iconMd,
                            ),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirmPassword
                                  ? strings.showPassword
                                  : strings.hidePassword,
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () => setState(
                                () => _obscureConfirmPassword =
                                    !_obscureConfirmPassword,
                              ),
                            ),
                            onFieldSubmitted: (_) => _submit(),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          CheckboxListTile(
                            value: _acceptedTerms,
                            onChanged: authState.isSubmitting
                                ? null
                                : (value) {
                                    _clearError();
                                    setState(() {
                                      _acceptedTerms = value ?? false;
                                      _showTermsError = false;
                                    });
                                  },
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(
                              strings.termsAgreement,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            subtitle: _showTermsError
                                ? Text(
                                    strings.termsRequired,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                        ),
                                  )
                                : null,
                          ),
                          if (authState.errorMessage != null) ...[
                            const SizedBox(height: AppTheme.spaceMd),
                            InlineMessage(
                              message: _friendlyError(
                                strings,
                                authState.errorCode,
                              ),
                              tone: InlineMessageTone.error,
                            ),
                          ],
                          const SizedBox(height: AppTheme.spaceLg),
                          PrimaryButton(
                            label: strings.continueToVerification,
                            isLoading: authState.isSubmitting,
                            onPressed: authState.isSubmitting ? null : _submit,
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppTheme.spaceSm,
                                ),
                                child: Text(
                                  strings.orDivider,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          GoogleSignInButton(
                            label: strings.continueWithGoogle,
                            isLoading: authState.isSubmitting,
                            onPressed: authState.isSubmitting
                                ? null
                                : _submitWithGoogle,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          SectionHeader(title: strings.authHelpSection),
          FeatureCard(
            title: strings.verifyCodeTitle,
            subtitle: strings.verifyEmailHint,
            icon: Icons.verified_user_outlined,
            color: AppTheme.secondary,
            onTap: authState.isSubmitting
                ? null
                : () => context.go(RoutePaths.verifyCode),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          FeatureCard(
            title: strings.haveAccountCta,
            subtitle: strings.backToLogin,
            icon: Icons.login_rounded,
            color: AppTheme.primary,
            onTap: authState.isSubmitting
                ? null
                : () => context.go(RoutePaths.login),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_page_frame.dart';
import '../widgets/google_sign_in_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.intendedDestination});

  final String? intendedDestination;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authControllerProvider).isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final success = await ref
        .read(authControllerProvider.notifier)
        .login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    if (success) {
      TextInput.finishAutofillContext();
      context.go(widget.intendedDestination ?? RoutePaths.home);
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
      context.go(widget.intendedDestination ?? RoutePaths.home);
    }
  }

  String? _validateEmail(String? value, AppStrings strings) {
    final result = Validators.email(value);
    if (result == null) return null;
    return value == null || value.trim().isEmpty
        ? strings.emailRequired
        : strings.invalidEmail;
  }

  String? _validatePassword(String? value, AppStrings strings) {
    return value == null || value.isEmpty ? strings.passwordRequired : null;
  }

  String _friendlyError(AppStrings strings, String? code) => switch (code) {
    'INVALID_CREDENTIALS' || 'UNAUTHORIZED' => strings.invalidCredentials,
    'EMAIL_NOT_VERIFIED' => strings.emailNotVerified,
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

  void _openEmailVerification() {
    final location = Uri(
      path: RoutePaths.verifyCode,
      queryParameters: {'email': _emailController.text.trim()},
    );
    context.push(location.toString());
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);

    return AuthPageFrame(
      title: strings.welcomeTitle,
      subtitle: strings.signInSubtitle,
      icon: Icons.local_hospital_rounded,
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppTextField(
                        label: strings.emailLabel,
                        hintText: strings.emailPlaceholder,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (value) => _validateEmail(value, strings),
                        autofillHints: const [AutofillHints.email],
                        textDirection: TextDirection.ltr,
                        autocorrect: false,
                        enableSuggestions: false,
                        onChanged: (_) => _clearError(),
                        prefixIcon: const Icon(
                          Icons.mail_outline_rounded,
                          size: AppTheme.iconMd,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceMd),
                      AppTextField(
                        label: strings.passwordLabel,
                        hintText: strings.passwordPlaceholder,
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        validator: (value) => _validatePassword(value, strings),
                        autofillHints: const [AutofillHints.password],
                        autocorrect: false,
                        enableSuggestions: false,
                        textDirection: TextDirection.ltr,
                        onChanged: (_) => _clearError(),
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
                        onFieldSubmitted: (_) => _submit(),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: authState.isSubmitting
                              ? null
                              : () => context.push(RoutePaths.forgotPassword),
                          child: Text(strings.forgotPasswordTitle),
                        ),
                      ),
                      if (authState.errorMessage != null) ...[
                        const SizedBox(height: AppTheme.spaceSm),
                        InlineMessage(
                          message: _friendlyError(strings, authState.errorCode),
                          tone: InlineMessageTone.error,
                        ),
                        if (authState.errorCode == 'EMAIL_NOT_VERIFIED')
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton.icon(
                              key: const ValueKey('verify-email-action'),
                              onPressed: authState.isSubmitting
                                  ? null
                                  : _openEmailVerification,
                              icon: const Icon(Icons.mark_email_read_outlined),
                              label: Text(strings.verifyCodeTitle),
                            ),
                          ),
                      ],
                      const SizedBox(height: AppTheme.spaceMd),
                      PrimaryButton(
                        label: strings.logIn,
                        isLoading: authState.isSubmitting,
                        onPressed: authState.isSubmitting ? null : _submit,
                      ),
                      const SizedBox(height: AppTheme.spaceLg),
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
                      const SizedBox(height: AppTheme.spaceLg),
                      GoogleSignInButton(
                        label: strings.continueWithGoogle,
                        isLoading: authState.isSubmitting,
                        onPressed: authState.isSubmitting
                            ? null
                            : _submitWithGoogle,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
          TextButton.icon(
            onPressed: authState.isSubmitting
                ? null
                : () => context.push(RoutePaths.register),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(strings.noAccountCta, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

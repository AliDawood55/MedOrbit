import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../widgets/password_strength_meter.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _completed = false;
  bool _submissionAttempted = false;

  @override
  void initState() {
    super.initState();
    _tokenController.text = widget.initialToken ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(authControllerProvider).errorMessage != null) {
        ref.read(authControllerProvider.notifier).clearError();
      }
    });
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authControllerProvider).isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submissionAttempted = true);

    final success = await ref
        .read(authControllerProvider.notifier)
        .resetPassword(
          token: _tokenController.text,
          newPassword: _passwordController.text,
        );

    if (!mounted) return;
    if (success) {
      TextInput.finishAutofillContext();
      setState(() => _completed = true);
    }
  }

  String? _validateToken(String? value, AppStrings strings) {
    return value == null || value.trim().isEmpty
        ? strings.resetTokenRequired
        : null;
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

  String _friendlyError(AppStrings strings, String? code) => switch (code) {
    'INVALID_TOKEN' => strings.resetInvalidToken,
    'VALIDATION_ERROR' => strings.resetValidationError,
    'RATE_LIMITED' => strings.authRateLimited,
    ApiException.codeConnectTimeout ||
    ApiException.codeSendTimeout ||
    ApiException.codeReceiveTimeout ||
    ApiException.codeServiceUnavailable => strings.authConnectionError,
    _ => strings.authRequestError,
  };

  void _clearError() {
    if (_submissionAttempted) {
      setState(() => _submissionAttempted = false);
    }
    if (ref.read(authControllerProvider).errorMessage != null) {
      ref.read(authControllerProvider.notifier).clearError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);

    return AuthPageFrame(
      title: strings.resetPasswordTitle,
      subtitle: strings.resetPasswordSubtitle,
      icon: Icons.lock_reset_rounded,
      leading: BackButton(onPressed: () => context.go(RoutePaths.login)),
      actions: [
        IconButton(
          tooltip: strings.languageToggleTooltip,
          onPressed: () => ref.read(localeControllerProvider.notifier).toggle(),
          icon: const Icon(Icons.translate_rounded),
        ),
      ],
      body: _completed
          ? Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      color: AppTheme.success,
                      size: AppTheme.iconXl,
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    Text(
                      strings.resetPasswordSuccessTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    Text(
                      strings.resetPasswordSuccessHint,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    PrimaryButton(
                      label: strings.backToLogin,
                      onPressed: () => context.go(RoutePaths.login),
                    ),
                  ],
                ),
              ),
            )
          : Column(
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
                              label: strings.resetTokenLabel,
                              hintText: strings.resetTokenPlaceholder,
                              controller: _tokenController,
                              validator: (value) =>
                                  _validateToken(value, strings),
                              keyboardType: TextInputType.visiblePassword,
                              textInputAction: TextInputAction.next,
                              textDirection: TextDirection.ltr,
                              autocorrect: false,
                              enableSuggestions: false,
                              onChanged: (_) => _clearError(),
                              prefixIcon: const Icon(
                                Icons.pin_outlined,
                                size: AppTheme.iconMd,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spaceMd),
                            AppTextField(
                              label: strings.newPasswordLabel,
                              hintText: strings.newPasswordPlaceholder,
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
                              obscureText: _obscureConfirm,
                              autofillHints: const [AutofillHints.newPassword],
                              textInputAction: TextInputAction.done,
                              autocorrect: false,
                              enableSuggestions: false,
                              textDirection: TextDirection.ltr,
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
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                size: AppTheme.iconMd,
                              ),
                              suffixIcon: IconButton(
                                tooltip: _obscureConfirm
                                    ? strings.showPassword
                                    : strings.hidePassword,
                                icon: Icon(
                                  _obscureConfirm
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                              ),
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (_submissionAttempted &&
                                authState.errorMessage != null) ...[
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
                              label: strings.resetPasswordButton,
                              isLoading: authState.isSubmitting,
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppTheme.spaceLg),
                TextButton.icon(
                  onPressed: authState.isSubmitting
                      ? null
                      : () => context.go(RoutePaths.login),
                  icon: const Icon(Icons.login_rounded),
                  label: Text(strings.backToLogin),
                ),
              ],
            ),
    );
  }
}

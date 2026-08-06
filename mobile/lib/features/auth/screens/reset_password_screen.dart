import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
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
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _tokenController.text = widget.initialToken ?? '';
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authControllerProvider.notifier).resetPassword(
          token: _tokenController.text.trim(),
          newPassword: _passwordController.text,
        );

    if (!mounted) return;
    if (success) {
      setState(() => _completed = true);
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
          ? FeatureCard(
              title: strings.resetPasswordSuccessTitle,
              subtitle: strings.resetPasswordSuccessHint,
              icon: Icons.check_circle_outline_rounded,
              color: AppTheme.success,
              onTap: () => context.go(RoutePaths.login),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: strings.securitySection, subtitle: strings.resetPasswordSubtitle),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spaceLg),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppTextField(
                            label: strings.resetTokenLabel,
                            hintText: strings.resetTokenPlaceholder,
                            controller: _tokenController,
                            validator: (value) => Validators.required(value, fieldName: strings.resetTokenLabel),
                            textDirection: TextDirection.ltr,
                            autocorrect: false,
                            enableSuggestions: false,
                            prefixIcon: const Icon(Icons.pin_outlined, size: AppTheme.iconMd),
                          ),
                          const SizedBox(height: AppTheme.spaceMd),
                          AppTextField(
                            label: strings.newPasswordLabel,
                            hintText: strings.newPasswordPlaceholder,
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            validator: Validators.password,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            enableSuggestions: false,
                            textDirection: TextDirection.ltr,
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: AppTheme.iconMd),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? strings.showPassword : strings.hidePassword,
                              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                                return Validators.required(value, fieldName: strings.confirmPasswordLabel);
                              }
                              if (value != _passwordController.text) {
                                return strings.passwordMismatch;
                              }
                              return null;
                            },
                            prefixIcon: const Icon(Icons.lock_outline_rounded, size: AppTheme.iconMd),
                            suffixIcon: IconButton(
                              tooltip: _obscureConfirm ? strings.showPassword : strings.hidePassword,
                              icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                            onFieldSubmitted: (_) {
                              if (!authState.isSubmitting) _submit();
                            },
                          ),
                          if (authState.errorMessage != null) ...[
                            const SizedBox(height: AppTheme.spaceMd),
                            InlineMessage(message: authState.errorMessage!, tone: InlineMessageTone.error),
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
                const SizedBox(height: AppTheme.spaceLg),
                FeatureCard(
                  title: strings.backToLogin,
                  subtitle: strings.signInSubtitle,
                  icon: Icons.login_rounded,
                  color: AppTheme.primary,
                  onTap: authState.isSubmitting ? null : () => context.go(RoutePaths.login),
                ),
              ],
            ),
    );
  }
}

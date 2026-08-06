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
import '../widgets/google_sign_in_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

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
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    if (success) {
      context.go(RoutePaths.home);
    }
  }

  Future<void> _submitWithGoogle() async {
    final success = await ref.read(authControllerProvider.notifier).loginWithGoogle();
    if (!mounted) return;
    if (success) {
      context.go(RoutePaths.home);
    }
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
          SectionHeader(title: strings.securitySection, subtitle: strings.signInSubtitle),
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
                      validator: Validators.email,
                      autofillHints: const [AutofillHints.email],
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      enableSuggestions: false,
                      prefixIcon: const Icon(Icons.mail_outline_rounded, size: AppTheme.iconMd),
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    AppTextField(
                      label: strings.passwordLabel,
                      hintText: strings.passwordPlaceholder,
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      validator: Validators.password,
                      autofillHints: const [AutofillHints.password],
                      autocorrect: false,
                      enableSuggestions: false,
                      textDirection: TextDirection.ltr,
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: AppTheme.iconMd),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? strings.showPassword : strings.hidePassword,
                        icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
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
                    PrimaryButton(label: strings.logIn, isLoading: authState.isSubmitting, onPressed: _submit),
                    const SizedBox(height: AppTheme.spaceMd),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spaceSm),
                          child: Text(
                            strings.orDivider,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                        Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    GoogleSignInButton(
                      label: strings.continueWithGoogle,
                      isLoading: authState.isSubmitting,
                      onPressed: _submitWithGoogle,
                    ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceLg),
          SectionHeader(title: strings.authHelpSection),
          FeatureCard(
            title: strings.forgotPasswordTitle,
            subtitle: strings.forgotPasswordSubtitle,
            icon: Icons.lock_reset_rounded,
            color: AppTheme.accent,
            onTap: authState.isSubmitting ? null : () => context.go(RoutePaths.forgotPassword),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          FeatureCard(
            title: strings.verifyCodeTitle,
            subtitle: strings.verifyCodeSubtitle,
            icon: Icons.verified_user_outlined,
            color: AppTheme.secondary,
            onTap: authState.isSubmitting ? null : () => context.go(RoutePaths.verifyCode),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          FeatureCard(
            title: strings.createAccountTitle,
            subtitle: strings.noAccountCta,
            icon: Icons.person_add_alt_1_rounded,
            color: AppTheme.primary,
            onTap: authState.isSubmitting ? null : () => context.go(RoutePaths.register),
          ),
        ],
      ),
    );
  }
}

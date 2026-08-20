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

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authControllerProvider.notifier).forgotPassword(_emailController.text.trim());
    if (!mounted) return;
    if (success) {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);

    return AuthPageFrame(
      title: strings.forgotPasswordTitle,
      subtitle: strings.forgotPasswordSubtitle,
      icon: Icons.lock_reset_rounded,
      leading: BackButton(onPressed: () => context.go(RoutePaths.login)),
      actions: [
        IconButton(
          tooltip: strings.languageToggleTooltip,
          onPressed: () => ref.read(localeControllerProvider.notifier).toggle(),
          icon: const Icon(Icons.translate_rounded),
        ),
      ],
      body: _sent
          ? FeatureCard(
              title: strings.resetLinkSentTitle,
              subtitle: strings.resetLinkSentHint,
              icon: Icons.mark_email_read_outlined,
              color: AppTheme.success,
              onTap: () => context.go(RoutePaths.login),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(title: strings.contactSection, subtitle: strings.forgotPasswordSubtitle),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spaceLg),
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
                            validator: Validators.email,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.done,
                            textDirection: TextDirection.ltr,
                            autocorrect: false,
                            enableSuggestions: false,
                            prefixIcon: const Icon(Icons.mail_outline_rounded, size: AppTheme.iconMd),
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
                            label: strings.sendResetLinkButton,
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
                  title: strings.verifyCodeTitle,
                  subtitle: strings.verifyEmailHint,
                  icon: Icons.verified_user_outlined,
                  color: AppTheme.secondary,
                  onTap: authState.isSubmitting ? null : () => context.go(RoutePaths.verifyCode),
                ),
                const SizedBox(height: AppTheme.spaceSm),
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

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

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _sent = false;
  bool _submissionAttempted = false;

  @override
  void initState() {
    super.initState();
    // The auth controller is shared with Login and Register. A previous
    // screen's failure must not be announced on this separate recovery flow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(authControllerProvider).errorMessage != null) {
        ref.read(authControllerProvider.notifier).clearError();
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authControllerProvider).isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _submissionAttempted = true);

    final success = await ref
        .read(authControllerProvider.notifier)
        .forgotPassword(_emailController.text.trim());
    if (!mounted) return;
    if (success) {
      TextInput.finishAutofillContext();
      setState(() => _sent = true);
    }
  }

  String? _validateEmail(String? value, AppStrings strings) {
    final result = Validators.email(value);
    if (result == null) return null;
    return value == null || value.trim().isEmpty
        ? strings.emailRequired
        : strings.invalidEmail;
  }

  String _friendlyError(AppStrings strings, String? code) => switch (code) {
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
          ? Card(
              child: Padding(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.mark_email_read_outlined,
                      color: AppTheme.success,
                      size: AppTheme.iconXl,
                    ),
                    const SizedBox(height: AppTheme.spaceMd),
                    Text(
                      strings.resetLinkSentTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    Text(
                      strings.resetLinkSentHint,
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
                              label: strings.emailLabel,
                              hintText: strings.emailPlaceholder,
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) => _validateEmail(value, strings),
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.done,
                              textDirection: TextDirection.ltr,
                              autocorrect: false,
                              enableSuggestions: false,
                              prefixIcon: const Icon(
                                Icons.mail_outline_rounded,
                                size: AppTheme.iconMd,
                              ),
                              onChanged: (_) => _clearError(),
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
                              label: strings.sendResetLinkButton,
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

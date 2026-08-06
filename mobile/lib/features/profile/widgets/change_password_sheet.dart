import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../auth/widgets/password_strength_meter.dart';
import '../providers/profile_provider.dart';

class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({
    super.key,
    required this.strings,
    required this.isSubmitting,
    required this.error,
    required this.onSubmit,
  });

  final AppStrings strings;
  final bool isSubmitting;
  final PasswordChangeErrorKind? error;
  final void Function(String currentPassword, String newPassword) onSubmit;

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    widget.onSubmit(_currentController.text, _newController.text);
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return Padding(
      padding: EdgeInsets.only(
        left: AppTheme.spaceLg,
        right: AppTheme.spaceLg,
        top: AppTheme.spaceLg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppTheme.spaceLg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.profileSectionPassword,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: AppTheme.weightExtraBold,
              ),
            ),
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              strings.profilePasswordDesc,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.spaceLg),
            AppTextField(
              label: strings.currentPasswordLabel,
              controller: _currentController,
              obscureText: _obscureCurrent,
              autofillHints: const [AutofillHints.password],
              textDirection: TextDirection.ltr,
              validator: (value) => Validators.required(
                value,
                fieldName: strings.currentPasswordLabel,
              ),
              suffixIcon: IconButton(
                tooltip: _obscureCurrent
                    ? strings.showPassword
                    : strings.hidePassword,
                icon: Icon(
                  _obscureCurrent
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscureCurrent = !_obscureCurrent),
              ),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            AppTextField(
              label: strings.newPasswordLabel,
              controller: _newController,
              obscureText: _obscureNew,
              autofillHints: const [AutofillHints.newPassword],
              textDirection: TextDirection.ltr,
              validator: Validators.password,
              suffixIcon: IconButton(
                tooltip: _obscureNew
                    ? strings.showPassword
                    : strings.hidePassword,
                icon: Icon(
                  _obscureNew
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            const SizedBox(height: AppTheme.spaceSm),
            AnimatedBuilder(
              animation: _newController,
              builder: (context, _) {
                return PasswordStrengthMeter(
                  password: _newController.text,
                  hintText: strings.passwordStrengthHint,
                );
              },
            ),
            const SizedBox(height: AppTheme.spaceMd),
            AppTextField(
              label: strings.confirmPasswordLabel,
              controller: _confirmController,
              obscureText: _obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              textDirection: TextDirection.ltr,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return Validators.required(
                    value,
                    fieldName: strings.confirmPasswordLabel,
                  );
                }
                if (value != _newController.text) {
                  return strings.passwordMismatch;
                }
                return null;
              },
              suffixIcon: IconButton(
                tooltip: _obscureConfirm
                    ? strings.showPassword
                    : strings.hidePassword,
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              onFieldSubmitted: (_) {
                if (!widget.isSubmitting) _submit();
              },
            ),
            if (widget.error != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              InlineMessage(
                message: _passwordErrorMessage(strings, widget.error!),
                tone: InlineMessageTone.error,
              ),
            ],
            const SizedBox(height: AppTheme.spaceLg),
            PrimaryButton(
              label: strings.changePasswordAction,
              isLoading: widget.isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

String _passwordErrorMessage(AppStrings strings, PasswordChangeErrorKind kind) {
  return switch (kind) {
    PasswordChangeErrorKind.wrongCurrentPassword =>
      strings.wrongCurrentPasswordError,
    PasswordChangeErrorKind.weakPassword => strings.weakNewPasswordError,
    PasswordChangeErrorKind.timeout => strings.profileSaveTimeout,
    PasswordChangeErrorKind.serviceUnavailable =>
      strings.profileSaveServiceUnavailable,
    PasswordChangeErrorKind.generic => strings.profileSaveError,
  };
}

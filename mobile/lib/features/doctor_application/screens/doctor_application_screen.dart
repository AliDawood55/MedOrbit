import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/doctor_application_model.dart';
import '../providers/doctor_application_provider.dart';
import '../widgets/specialty_field.dart';

/// Whether an account with [role] may see and use the Doctor Application flow.
/// Patient-only, mirroring the web page's `canApply` gate and the backend
/// `submit` guard (`u.role !== 'patient'` → `FORBIDDEN`).
bool doctorApplicationAvailableForRole(String? role) =>
    role?.trim().toLowerCase() == 'patient';

class DoctorApplicationScreen extends ConsumerStatefulWidget {
  const DoctorApplicationScreen({super.key});

  @override
  ConsumerState<DoctorApplicationScreen> createState() => _DoctorApplicationScreenState();
}

class _DoctorApplicationScreenState extends ConsumerState<DoctorApplicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _license = TextEditingController();
  final _subSpecialty = TextEditingController();
  final _years = TextEditingController();
  final _education = TextEditingController();
  final _certifications = TextEditingController();
  final _bio = TextEditingController();

  String? _specialtyId;
  bool _submitted = false;
  bool _loadedOnce = false;

  /// The error code from THIS screen's most recent submit/withdraw attempt.
  /// Kept separate from a first-load failure so each renders its own UI.
  String? _actionError;

  @override
  void dispose() {
    _license.dispose();
    _subSpecialty.dispose();
    _years.dispose();
    _education.dispose();
    _certifications.dispose();
    _bio.dispose();
    super.dispose();
  }

  void _clearActionError() {
    if (_actionError != null) setState(() => _actionError = null);
  }

  int? _parseYears(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }

  String? _validateLicense(String? value, AppStrings strings) =>
      (value == null || value.trim().isEmpty)
          ? strings.doctorApplicationLicenseRequired
          : null;

  String? _validateYears(String? value, AppStrings strings) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return strings.doctorApplicationExperienceInvalid;
    if (parsed < 0 || parsed > 80) return strings.doctorApplicationExperienceRange;
    return null;
  }

  void _resetForm() {
    _license.clear();
    _subSpecialty.clear();
    _years.clear();
    _education.clear();
    _certifications.clear();
    _bio.clear();
    setState(() {
      _specialtyId = null;
      _submitted = false;
      _actionError = null;
    });
  }

  Future<void> _submit(AppStrings strings) async {
    _clearActionError();
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final specialtyId = _specialtyId;
    if (specialtyId == null || specialtyId.isEmpty) return;

    FocusScope.of(context).unfocus();
    final request = DoctorApplicationRequest.fromMultiline(
      specialtyId: specialtyId,
      medicalLicenseNumber: _license.text,
      subSpecialty: _subSpecialty.text,
      yearsOfExperience: _parseYears(_years.text),
      education: _education.text,
      certifications: _certifications.text,
      bio: _bio.text,
    );

    final controller = ref.read(doctorApplicationControllerProvider.notifier);
    final success = await controller.submit(request);
    if (!mounted) return;

    if (success) {
      _resetForm();
      _showSnack(strings.doctorApplicationSubmitSuccess);
    } else {
      setState(() => _actionError = ref.read(doctorApplicationControllerProvider).errorCode);
    }
  }

  Future<void> _confirmWithdraw(DoctorApplication application, AppStrings strings) async {
    if (ref.read(doctorApplicationControllerProvider).withdrawingApplicationId != null) return;
    _clearActionError();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceLg,
          vertical: AppTheme.spaceXl,
        ),
        icon: const Icon(Icons.undo_rounded, color: AppTheme.warning, size: AppTheme.iconXl),
        title: Text(strings.doctorApplicationWithdrawTitle, textAlign: TextAlign.center),
        content: Text(strings.doctorApplicationWithdrawBody, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton.icon(
            key: const ValueKey('doctor-application-withdraw-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.warning,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.undo_rounded),
            label: Text(strings.doctorApplicationWithdrawConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final success = await ref
        .read(doctorApplicationControllerProvider.notifier)
        .withdraw(application.id);
    if (!mounted) return;

    if (success) {
      _showSnack(strings.doctorApplicationWithdrawSuccess);
    } else {
      setState(() => _actionError = ref.read(doctorApplicationControllerProvider).errorCode);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final role = ref.watch(authControllerProvider).user?.role;

    if (!doctorApplicationAvailableForRole(role)) {
      return AppScaffold(
        appBar: AppBar(title: Text(strings.doctorApplicationTitle)),
        useSafeArea: true,
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              child: Card(
                child: EmptyState(
                  icon: Icons.person_off_outlined,
                  title: strings.doctorApplicationPatientOnlyTitle,
                  hint: strings.doctorApplicationPatientOnlyBody,
                  variant: EmptyStateVariant.compact,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final state = ref.watch(doctorApplicationControllerProvider);
    if (!state.isLoading && state.errorCode == null) _loadedOnce = true;

    final controller = ref.read(doctorApplicationControllerProvider.notifier);

    final Widget content;
    if (!_loadedOnce && state.isLoading) {
      content = _LoadingCard(strings: strings);
    } else if (!_loadedOnce && state.errorCode != null) {
      content = Card(
        child: ErrorRetryState(
          title: strings.doctorApplicationLoadErrorTitle,
          message: strings.doctorApplicationError(state.errorCode),
          retryLabel: strings.retry,
          onRetry: controller.load,
          variant: ErrorRetryVariant.compact,
        ),
      );
    } else {
      content = _DoctorApplicationBody(
        state: state,
        strings: strings,
        isArabic: isArabic,
        formKey: _formKey,
        specialtyId: _specialtyId,
        submitted: _submitted,
        actionError: _actionError,
        licenseController: _license,
        subSpecialtyController: _subSpecialty,
        yearsController: _years,
        educationController: _education,
        certificationsController: _certifications,
        bioController: _bio,
        validateLicense: (value) => _validateLicense(value, strings),
        validateYears: (value) => _validateYears(value, strings),
        onSpecialtyChanged: (value) {
          _clearActionError();
          setState(() => _specialtyId = value);
        },
        onFieldChanged: _clearActionError,
        onSubmit: () => _submit(strings),
        onWithdraw: (application) => _confirmWithdraw(application, strings),
        onSignInAgain: _signInAgain,
      );
    }

    return AppScaffold(
      appBar: AppBar(title: Text(strings.doctorApplicationTitle)),
      keyboardAware: true,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(child: content),
              const SizedBox(height: AppTheme.spaceXl),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInAgain() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (!mounted) return;
    context.go(RoutePaths.login);
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        label: strings.doctorApplicationLoading,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.space2xl),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppTheme.spaceLg),
                Text(
                  strings.doctorApplicationLoading,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _DoctorApplicationBody extends StatelessWidget {
  const _DoctorApplicationBody({
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.formKey,
    required this.specialtyId,
    required this.submitted,
    required this.actionError,
    required this.licenseController,
    required this.subSpecialtyController,
    required this.yearsController,
    required this.educationController,
    required this.certificationsController,
    required this.bioController,
    required this.validateLicense,
    required this.validateYears,
    required this.onSpecialtyChanged,
    required this.onFieldChanged,
    required this.onSubmit,
    required this.onWithdraw,
    required this.onSignInAgain,
  });

  final DoctorApplicationState state;
  final AppStrings strings;
  final bool isArabic;
  final GlobalKey<FormState> formKey;
  final String? specialtyId;
  final bool submitted;
  final String? actionError;
  final TextEditingController licenseController;
  final TextEditingController subSpecialtyController;
  final TextEditingController yearsController;
  final TextEditingController educationController;
  final TextEditingController certificationsController;
  final TextEditingController bioController;
  final FormFieldValidator<String> validateLicense;
  final FormFieldValidator<String> validateYears;
  final ValueChanged<String?> onSpecialtyChanged;
  final VoidCallback onFieldChanged;
  final VoidCallback onSubmit;
  final ValueChanged<DoctorApplication> onWithdraw;
  final Future<void> Function() onSignInAgain;

  DoctorApplication? get _current =>
      state.applications.isEmpty ? null : state.applications.first;

  bool get _canApply {
    final current = _current;
    return current == null ||
        current.status == DoctorApplicationStatus.rejected ||
        current.status == DoctorApplicationStatus.withdrawn;
  }

  String _specialtyName(String id) {
    for (final specialty in state.specialties) {
      if (specialty.id == id) return specialty.label(isArabic);
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final children = <Widget>[
      PageIntro(
        title: strings.doctorApplicationIntroTitle,
        subtitle: strings.doctorApplicationIntroBody,
        icon: Icons.medical_information_outlined,
        color: AppTheme.primary,
      ),
    ];

    if (current != null) {
      children
        ..add(const SizedBox(height: AppTheme.spaceLg))
        ..add(_StatusCard(
          application: current,
          strings: strings,
          isArabic: isArabic,
          withdrawing: state.withdrawingApplicationId == current.id,
          actionError: current.status == DoctorApplicationStatus.pending ? actionError : null,
          onWithdraw: () => onWithdraw(current),
          onSignInAgain: onSignInAgain,
        ));
    }

    if (_canApply) {
      children
        ..add(const SizedBox(height: AppTheme.spaceLg))
        ..add(_ApplicationFormCard(
          state: state,
          strings: strings,
          isArabic: isArabic,
          isFirstApplication: current == null,
          formKey: formKey,
          specialtyId: specialtyId,
          submitted: submitted,
          actionError: actionError,
          licenseController: licenseController,
          subSpecialtyController: subSpecialtyController,
          yearsController: yearsController,
          educationController: educationController,
          certificationsController: certificationsController,
          bioController: bioController,
          validateLicense: validateLicense,
          validateYears: validateYears,
          onSpecialtyChanged: onSpecialtyChanged,
          onFieldChanged: onFieldChanged,
          onSubmit: onSubmit,
        ));
    }

    if (state.applications.isNotEmpty) {
      children
        ..add(const SizedBox(height: AppTheme.spaceXl))
        ..add(SectionHeader(title: strings.doctorApplicationHistoryTitle))
        ..addAll([
          for (final application in state.applications)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spaceSm),
              child: _HistoryCard(
                application: application,
                strings: strings,
                isArabic: isArabic,
                specialtyName: _specialtyName(application.specialtyId),
              ),
            ),
        ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

(String, Color, IconData) _statusVisual(DoctorApplicationStatus status, AppStrings strings) {
  return switch (status) {
    DoctorApplicationStatus.pending => (
        strings.doctorApplicationStatusPending,
        AppTheme.warning,
        Icons.hourglass_top_rounded,
      ),
    DoctorApplicationStatus.approved => (
        strings.doctorApplicationStatusApproved,
        AppTheme.success,
        Icons.verified_rounded,
      ),
    DoctorApplicationStatus.rejected => (
        strings.doctorApplicationStatusRejected,
        AppTheme.danger,
        Icons.error_outline_rounded,
      ),
    DoctorApplicationStatus.withdrawn => (
        strings.doctorApplicationStatusWithdrawn,
        AppTheme.info,
        Icons.undo_rounded,
      ),
    DoctorApplicationStatus.unknown => (
        strings.doctorApplicationStatusUnknown,
        AppTheme.info,
        Icons.help_outline_rounded,
      ),
  };
}

String _formatDate(DateTime value, bool isArabic) {
  try {
    return formatDate(value, localeCode: isArabic ? 'ar' : 'en');
  } catch (_) {
    return value.toIso8601String().split('T').first;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.application,
    required this.strings,
    required this.isArabic,
    required this.withdrawing,
    required this.actionError,
    required this.onWithdraw,
    required this.onSignInAgain,
  });

  final DoctorApplication application;
  final AppStrings strings;
  final bool isArabic;
  final bool withdrawing;
  final String? actionError;
  final VoidCallback onWithdraw;
  final Future<void> Function() onSignInAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, icon) = _statusVisual(application.status, strings);
    final body = switch (application.status) {
      DoctorApplicationStatus.pending => strings.doctorApplicationPendingBody,
      DoctorApplicationStatus.approved => strings.doctorApplicationApprovedBody,
      DoctorApplicationStatus.rejected => strings.doctorApplicationRejectedBody,
      DoctorApplicationStatus.withdrawn => strings.doctorApplicationWithdrawnBody,
      DoctorApplicationStatus.unknown => strings.doctorApplicationUnknownBody,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: AppTheme.iconMd),
                const SizedBox(width: AppTheme.spaceSm),
                Expanded(
                  child: Text(
                    strings.doctorApplicationStatusHeading,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightBold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusBadge(label: label, color: color),
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppTheme.spaceSm),
            _MetaLine(
              label: strings.doctorApplicationSubmittedOn,
              value: _formatDate(application.submittedAt, isArabic),
            ),
            if (application.reviewedAt != null)
              _MetaLine(
                label: strings.doctorApplicationReviewedOn,
                value: _formatDate(application.reviewedAt!, isArabic),
              ),
            if (application.status == DoctorApplicationStatus.rejected &&
                application.rejectionReason != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              InlineMessage(
                message:
                    '${strings.doctorApplicationRejectionReason}: ${application.rejectionReason}',
                tone: InlineMessageTone.warning,
              ),
            ],
            if (actionError != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              InlineMessage(
                message: strings.doctorApplicationError(actionError),
                tone: InlineMessageTone.error,
              ),
            ],
            if (application.status == DoctorApplicationStatus.pending) ...[
              const SizedBox(height: AppTheme.spaceLg),
              PrimaryButton(
                key: const ValueKey('doctor-application-withdraw'),
                label: strings.doctorApplicationWithdraw,
                icon: Icons.undo_rounded,
                isLoading: withdrawing,
                onPressed: onWithdraw,
              ),
            ],
            if (application.status == DoctorApplicationStatus.approved) ...[
              const SizedBox(height: AppTheme.spaceLg),
              PrimaryButton(
                key: const ValueKey('doctor-application-sign-in-again'),
                label: strings.doctorApplicationSignInAgain,
                icon: Icons.login_rounded,
                onPressed: onSignInAgain,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spaceXs),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            TextSpan(
              text: value,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ApplicationFormCard extends StatelessWidget {
  const _ApplicationFormCard({
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.isFirstApplication,
    required this.formKey,
    required this.specialtyId,
    required this.submitted,
    required this.actionError,
    required this.licenseController,
    required this.subSpecialtyController,
    required this.yearsController,
    required this.educationController,
    required this.certificationsController,
    required this.bioController,
    required this.validateLicense,
    required this.validateYears,
    required this.onSpecialtyChanged,
    required this.onFieldChanged,
    required this.onSubmit,
  });

  final DoctorApplicationState state;
  final AppStrings strings;
  final bool isArabic;
  final bool isFirstApplication;
  final GlobalKey<FormState> formKey;
  final String? specialtyId;
  final bool submitted;
  final String? actionError;
  final TextEditingController licenseController;
  final TextEditingController subSpecialtyController;
  final TextEditingController yearsController;
  final TextEditingController educationController;
  final TextEditingController certificationsController;
  final TextEditingController bioController;
  final FormFieldValidator<String> validateLicense;
  final FormFieldValidator<String> validateYears;
  final ValueChanged<String?> onSpecialtyChanged;
  final VoidCallback onFieldChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final autovalidate =
        submitted ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Form(
          key: formKey,
          autovalidateMode: autovalidate,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: isFirstApplication
                    ? strings.doctorApplicationFormTitle
                    : strings.doctorApplicationNewFormTitle,
                subtitle: strings.doctorApplicationFormIntro,
              ),
              SpecialtyField(
                specialties: state.specialties,
                isArabic: isArabic,
                strings: strings,
                initialValue: specialtyId,
                autovalidateMode: autovalidate,
                onChanged: onSpecialtyChanged,
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.doctorApplicationLicenseLabel,
                hintText: strings.doctorApplicationLicenseHint,
                controller: licenseController,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 255,
                prefixIcon: const Icon(Icons.badge_outlined, size: AppTheme.iconMd),
                validator: validateLicense,
                onChanged: (_) => onFieldChanged(),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.doctorApplicationSubSpecialtyLabel,
                hintText: strings.doctorApplicationOptional,
                controller: subSpecialtyController,
                textInputAction: TextInputAction.next,
                maxLength: 255,
                prefixIcon: const Icon(Icons.workspaces_outline, size: AppTheme.iconMd),
                onChanged: (_) => onFieldChanged(),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.doctorApplicationExperienceLabel,
                hintText: strings.doctorApplicationOptional,
                controller: yearsController,
                keyboardType: const TextInputType.numberWithOptions(),
                textInputAction: TextInputAction.next,
                prefixIcon: const Icon(Icons.timelapse_outlined, size: AppTheme.iconMd),
                validator: validateYears,
                onChanged: (_) => onFieldChanged(),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.doctorApplicationEducationLabel,
                hintText: strings.doctorApplicationOnePerLineHint,
                helperText: strings.doctorApplicationOnePerLineHint,
                controller: educationController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                prefixIcon: const Icon(Icons.school_outlined, size: AppTheme.iconMd),
                onChanged: (_) => onFieldChanged(),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.doctorApplicationCertificationsLabel,
                hintText: strings.doctorApplicationOnePerLineHint,
                helperText: strings.doctorApplicationOnePerLineHint,
                controller: certificationsController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                prefixIcon: const Icon(Icons.verified_outlined, size: AppTheme.iconMd),
                onChanged: (_) => onFieldChanged(),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              AppTextField(
                label: strings.doctorApplicationBioLabel,
                hintText: strings.doctorApplicationOptional,
                controller: bioController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                prefixIcon: const Icon(Icons.notes_outlined, size: AppTheme.iconMd),
                onChanged: (_) => onFieldChanged(),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: AppTheme.iconSm,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppTheme.spaceSm),
                  Expanded(
                    child: Text(
                      strings.doctorApplicationPrivacyNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
              if (actionError != null) ...[
                const SizedBox(height: AppTheme.spaceLg),
                InlineMessage(
                  message: strings.doctorApplicationError(actionError),
                  tone: InlineMessageTone.error,
                ),
              ],
              const SizedBox(height: AppTheme.spaceLg),
              PrimaryButton(
                key: const ValueKey('doctor-application-submit'),
                label: state.isSubmitting
                    ? strings.doctorApplicationSubmitting
                    : strings.doctorApplicationSubmit,
                icon: Icons.send_rounded,
                isLoading: state.isSubmitting,
                onPressed: onSubmit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.application,
    required this.strings,
    required this.isArabic,
    required this.specialtyName,
  });

  final DoctorApplication application;
  final AppStrings strings;
  final bool isArabic;
  final String specialtyName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, _) = _statusVisual(application.status, strings);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusBadge(label: label, color: color),
                Text(
                  _formatDate(application.submittedAt, isArabic),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),
            if (specialtyName.isNotEmpty)
              _MetaLine(label: strings.doctorApplicationSpecialtyLabel, value: specialtyName),
            _MetaLine(
              label: strings.doctorApplicationLicenseLabel,
              value: application.medicalLicenseNumber,
            ),
            if (application.subSpecialty != null)
              _MetaLine(
                label: strings.doctorApplicationSubSpecialtyLabel,
                value: application.subSpecialty!,
              ),
            if (application.yearsOfExperience != null)
              _MetaLine(
                label: strings.doctorApplicationExperienceLabel,
                value: strings.doctorApplicationYearsValue(application.yearsOfExperience!),
              ),
            if (application.reviewedAt != null)
              _MetaLine(
                label: strings.doctorApplicationReviewedOn,
                value: _formatDate(application.reviewedAt!, isArabic),
              ),
            if (application.status == DoctorApplicationStatus.rejected &&
                application.rejectionReason != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              InlineMessage(
                message:
                    '${strings.doctorApplicationRejectionReason}: ${application.rejectionReason}',
                tone: InlineMessageTone.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

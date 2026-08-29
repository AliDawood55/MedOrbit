import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/localization/app_strings.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../common/utils/admin_formatting.dart';
import '../../common/widgets/admin_confirm_dialog.dart';
import '../../common/widgets/admin_detail_rows.dart';
import '../../common/widgets/admin_gate.dart';
import '../models/admin_doctor_application.dart';
import '../providers/admin_doctor_applications_provider.dart';
import '../widgets/admin_application_status.dart';

/// Full-screen review of one doctor application: applicant identity,
/// professional credentials, and — only while the application is still
/// `pending` — the approve/reject decision.
class AdminApplicationReviewScreen extends ConsumerWidget {
  const AdminApplicationReviewScreen({super.key, required this.applicationId});

  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return AdminGate(
      title: strings.adminApplicationDetailTitle,
      child: _AdminApplicationReviewView(applicationId: applicationId),
    );
  }
}

class _AdminApplicationReviewView extends ConsumerStatefulWidget {
  const _AdminApplicationReviewView({required this.applicationId});

  final String applicationId;

  @override
  ConsumerState<_AdminApplicationReviewView> createState() =>
      _AdminApplicationReviewViewState();
}

class _AdminApplicationReviewViewState
    extends ConsumerState<_AdminApplicationReviewView> {
  AdminApplicationReviewController get _controller => ref.read(
    adminApplicationReviewControllerProvider(widget.applicationId).notifier,
  );

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _approve(AppStrings strings) async {
    final confirmed = await showAdminConfirmDialog(
      context: context,
      strings: strings,
      title: strings.adminApplicationApproveTitle,
      body: strings.adminApplicationApproveBody,
      confirmLabel: strings.adminApplicationApprove,
      icon: Icons.verified_outlined,
      tone: AppTheme.success,
      confirmKey: const ValueKey('admin-application-approve-confirm'),
    );
    if (!confirmed || !mounted) return;

    final succeeded = await _controller.approve();
    if (!mounted || !succeeded) return;
    _snack(strings.adminApplicationApprovedSuccess);
  }

  Future<void> _reject(AppStrings strings) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RejectionSheet(strings: strings),
    );
    if (reason == null || !mounted) return;

    final succeeded = await _controller.reject(reason);
    if (!mounted || !succeeded) return;
    _snack(strings.adminApplicationRejectedSuccess);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final state = ref.watch(
      adminApplicationReviewControllerProvider(widget.applicationId),
    );
    final application = state.application;

    return AppScaffold(
      appBar: AppBar(title: Text(strings.adminApplicationDetailTitle)),
      useSafeArea: true,
      safeAreaTop: false,
      body: Builder(
        builder: (context) {
          if (application == null && state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (application == null) {
            return ErrorRetryState(
              title: strings.adminLoadErrorTitle,
              message: strings.adminError(state.errorCode),
              retryLabel: strings.retry,
              onRetry: _controller.load,
              retryKey: const ValueKey('admin-application-retry'),
            );
          }
          return _ReviewBody(
            application: application,
            state: state,
            strings: strings,
            isArabic: isArabic,
            onApprove: () => _approve(strings),
            onReject: () => _reject(strings),
          );
        },
      ),
    );
  }
}

class _ReviewBody extends StatelessWidget {
  const _ReviewBody({
    required this.application,
    required this.state,
    required this.strings,
    required this.isArabic,
    required this.onApprove,
    required this.onReject,
  });

  final AdminDoctorApplication application;
  final AdminApplicationReviewState state;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = adminApplicationStatusVisual(
      application,
      strings,
    );
    final bio = application.resolvedBio(isArabic: isArabic);
    final specialty = application.specialtyName(isArabic: isArabic);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
      children: [
        ResponsiveContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageIntro(
                title: application.applicant.displayName(isArabic: isArabic),
                subtitle: application.applicant.email ?? '',
                icon: Icons.badge_outlined,
                trailing: StatusBadge(label: statusLabel, color: statusColor),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              if (state.actionErrorCode != null) ...[
                InlineMessage(
                  message: strings.adminError(state.actionErrorCode),
                  tone: InlineMessageTone.error,
                ),
                const SizedBox(height: AppTheme.spaceLg),
              ],
              AdminSectionCard(
                title: strings.adminApplicationApplicantSection,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (application.applicant.email != null)
                      AdminDetailRow(
                        label: strings.emailLabel,
                        value: application.applicant.email!,
                        selectable: true,
                      ),
                    AdminDetailRow(
                      label: strings.adminApplicationSubmittedAt,
                      value: adminFormatDateTime(
                        application.submittedAt,
                        isArabic: isArabic,
                      ),
                    ),
                    if (application.reviewedAt != null)
                      AdminDetailRow(
                        label: strings.adminApplicationReviewedAt,
                        value: adminFormatDateTime(
                          application.reviewedAt!,
                          isArabic: isArabic,
                        ),
                      ),
                    if (application.rejectionReason != null)
                      AdminDetailRow(
                        label: strings.adminApplicationRejectionReason,
                        value: application.rejectionReason!,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              AdminSectionCard(
                title: strings.adminApplicationProfessionalSection,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (specialty.isNotEmpty)
                      AdminDetailRow(
                        label: strings.adminApplicationSpecialty,
                        value: specialty,
                      ),
                    AdminDetailRow(
                      label: strings.adminApplicationLicense,
                      value: application.medicalLicenseNumber,
                      selectable: true,
                    ),
                    if (application.subSpecialty != null)
                      AdminDetailRow(
                        label: strings.adminApplicationSubSpecialty,
                        value: application.subSpecialty!,
                      ),
                    if (application.yearsOfExperience != null)
                      AdminDetailRow(
                        label: strings.adminApplicationExperience,
                        value: strings.adminApplicationYears(
                          application.yearsOfExperience!,
                        ),
                      ),
                    if (application.education.isNotEmpty)
                      AdminDetailRow(
                        label: strings.adminApplicationEducation,
                        value: application.education.join('\n'),
                      ),
                    if (application.certifications.isNotEmpty)
                      AdminDetailRow(
                        label: strings.adminApplicationCertifications,
                        value: application.certifications.join('\n'),
                      ),
                    if (bio != null)
                      AdminDetailRow(
                        label: strings.adminApplicationBio,
                        value: bio,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              if (application.isPending)
                _DecisionActions(
                  strings: strings,
                  isSubmitting: state.isSubmitting,
                  onApprove: onApprove,
                  onReject: onReject,
                )
              else
                InlineMessage(
                  message: strings.adminApplicationDecidedNote,
                  tone: InlineMessageTone.info,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DecisionActions extends StatelessWidget {
  const _DecisionActions({
    required this.strings,
    required this.isSubmitting,
    required this.onApprove,
    required this.onReject,
  });

  final AppStrings strings;
  final bool isSubmitting;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('admin-application-approve'),
          onPressed: isSubmitting ? null : onApprove,
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.success,
            foregroundColor: Colors.white,
          ),
          icon: isSubmitting
              ? const SizedBox.square(
                  dimension: AppTheme.iconMd,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.verified_outlined),
          label: Text(strings.adminApplicationApprove),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        OutlinedButton.icon(
          key: const ValueKey('admin-application-reject'),
          onPressed: isSubmitting ? null : onReject,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.danger,
            side: const BorderSide(color: AppTheme.danger),
          ),
          icon: const Icon(Icons.close_rounded),
          label: Text(strings.adminApplicationReject),
        ),
      ],
    );
  }
}

/// Keyboard-safe rejection form.
///
/// The reason is required by `decide()` on the server, so it is both validated
/// here and never sent blank. The sheet doubles as the confirmation step —
/// writing the reason the applicant will receive is a more meaningful
/// confirmation than a second "are you sure" dialog on top of it.
class _RejectionSheet extends StatefulWidget {
  const _RejectionSheet({required this.strings});

  final AppStrings strings;

  @override
  State<_RejectionSheet> createState() => _RejectionSheetState();
}

class _RejectionSheetState extends State<_RejectionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppTheme.spaceLg,
          right: AppTheme.spaceLg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppTheme.spaceXl,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.adminApplicationRejectTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTheme.spaceSm),
                Text(
                  strings.adminApplicationRejectBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                AppTextField(
                  key: const ValueKey('admin-application-reject-reason'),
                  label: strings.adminApplicationRejectReasonLabel,
                  hintText: strings.adminApplicationRejectReasonHint,
                  controller: _reason,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  semanticLabel: strings.adminApplicationRejectReasonLabel,
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? strings.adminApplicationRejectReasonRequired
                      : null,
                ),
                const SizedBox(height: AppTheme.spaceLg),
                FilledButton.icon(
                  key: const ValueKey('admin-application-reject-submit'),
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  label: Text(strings.adminApplicationReject),
                ),
                const SizedBox(height: AppTheme.spaceSm),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(strings.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

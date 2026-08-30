import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/doctor_workspace_providers.dart';

class DoctorWorkspaceGate extends ConsumerWidget {
  const DoctorWorkspaceGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final role = ref
        .watch(authControllerProvider)
        .user
        ?.role
        .trim()
        .toLowerCase();
    if (role != 'doctor') {
      return _GateMessage(message: strings.doctorEligibilityUnavailable);
    }
    return ref
        .watch(doctorProfileProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          data: (profile) => profile.isApproved
              ? child
              : _GateMessage(message: strings.doctorApprovalRequired),
          error: (error, _) {
            final code = ApiException.from(error).code;
            if (code == 'NOT_FOUND' || code == 'DOCTOR_NOT_APPROVED') {
              return _GateMessage(message: strings.doctorApprovalRequired);
            }
            return ErrorRetryState(
              title: strings.doctorWorkspace,
              message: strings.doctorError(code),
              retryLabel: strings.retry,
              onRetry: () => ref.read(doctorProfileProvider.notifier).load(),
            );
          },
        );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: ResponsiveContent(
      child: Semantics(
        container: true,
        label: message,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.space2xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.health_and_safety_outlined,
                size: AppTheme.icon2xl,
              ),
              const SizedBox(height: AppTheme.spaceLg),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

void showDoctorError(BuildContext context, AppStrings strings, Object? error) {
  final code = error is ApiException
      ? error.code
      : ApiException.from(error ?? Exception()).code;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(strings.doctorError(code))));
}

String doctorErrorMessage(AppStrings strings, Object error) =>
    strings.doctorError(ApiException.from(error).code);

Future<bool> confirmDoctorAction(
  BuildContext context, {
  required String title,
  required String body,
  required AppStrings strings,
  String? confirmLabel,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel ?? strings.confirm),
          ),
        ],
      ),
    ) ??
    false;

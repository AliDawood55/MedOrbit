import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/doctor_models.dart';
import '../providers/doctor_workspace_providers.dart';
import '../widgets/doctor_workspace_gate.dart';

class DoctorAppointmentsScreen extends ConsumerWidget {
  const DoctorAppointmentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final async = ref.watch(doctorScheduleProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(s.doctorAppointments)),
      body: DoctorWorkspaceGate(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetryState(
            title: s.doctorAppointments,
            message: doctorErrorMessage(s, e),
            retryLabel: s.retry,
            onRetry: () => ref.read(doctorScheduleProvider.notifier).load(),
          ),
          data: (schedule) => RefreshIndicator(
            onRefresh: () => ref.read(doctorScheduleProvider.notifier).load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
              children: [
                ResponsiveContent(
                  child: schedule.appointments.isEmpty
                      ? EmptyState(
                          icon: Icons.event_busy_outlined,
                          title: s.noAppointments,
                        )
                      : Column(
                          children: schedule.appointments
                              .map((a) => _card(context, ref, s, a))
                              .toList(),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorAppointment a,
  ) {
    final name = s.isArabic
        ? [a.firstNameAr, a.lastNameAr].whereType<String>().join(' ')
        : [a.firstNameEn, a.lastNameEn].whereType<String>().join(' ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  name.trim().isEmpty ? a.number : name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                StatusBadge(
                  label: s.doctorStatus(a.status),
                  color: _color(a.status),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${a.date} · ${a.startTime.substring(0, 5)}–${a.endTime.substring(0, 5)} · ${a.type == 'telemedicine' ? s.telemedicine : s.inPerson}',
            ),
            if (a.reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(a.reason!),
              ),
            if (a.status == 'scheduled' ||
                a.status == 'confirmed' ||
                a.status == 'in_progress') ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (a.status == 'scheduled')
                    FilledButton(
                      onPressed: () => _act(context, ref, s, a, 'confirm'),
                      child: Text(s.confirm),
                    ),
                  if (a.status == 'confirmed' || a.status == 'in_progress')
                    FilledButton(
                      onPressed: () => _act(context, ref, s, a, 'complete'),
                      child: Text(s.complete),
                    ),
                  if (a.status == 'scheduled' || a.status == 'confirmed')
                    OutlinedButton(
                      onPressed: () => _cancel(context, ref, s, a),
                      child: Text(s.cancel),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorAppointment a,
    String action,
  ) async {
    final result = await ref
        .read(doctorScheduleProvider.notifier)
        .actOnAppointment(a.id, action);
    if (context.mounted && result.error != null) {
      showDoctorError(context, s, result.error);
    }
  }

  Future<void> _cancel(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorAppointment a,
  ) async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.cancel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.deleteConfirmation),
            TextField(
              controller: c,
              maxLength: 1000,
              decoration: InputDecoration(labelText: s.reason),
              minLines: 2,
              maxLines: 4,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    c.dispose();
    if (reason == null || !context.mounted) return;
    final result = await ref
        .read(doctorScheduleProvider.notifier)
        .actOnAppointment(a.id, 'cancel', reason: reason);
    if (context.mounted && result.error != null) {
      showDoctorError(context, s, result.error);
    }
  }

  Color _color(String status) => switch (status) {
    'completed' => AppTheme.success,
    'cancelled' || 'no_show' => AppTheme.danger,
    'confirmed' => AppTheme.info,
    _ => AppTheme.warning,
  };
}

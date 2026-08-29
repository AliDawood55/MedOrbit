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

class DoctorRecordsScreen extends ConsumerWidget {
  const DoctorRecordsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider);
    final records = ref.watch(doctorRecordsProvider);
    final profile = ref.watch(doctorProfileProvider).valueOrNull;
    return AppScaffold(
      appBar: AppBar(title: Text(s.doctorRecords)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, s, null),
        icon: const Icon(Icons.add),
        label: Text(s.create),
      ),
      body: DoctorWorkspaceGate(
        child: records.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetryState(
            title: s.doctorRecords,
            message: doctorErrorMessage(s, e),
            retryLabel: s.retry,
            onRetry: () => ref.read(doctorRecordsProvider.notifier).load(),
          ),
          data: (items) => RefreshIndicator(
            onRefresh: () => ref.read(doctorRecordsProvider.notifier).load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: AppTheme.spaceLg, bottom: 96),
              children: [
                ResponsiveContent(
                  child: items.isEmpty
                      ? EmptyState(
                          icon: Icons.medical_information_outlined,
                          title: s.noRecords,
                        )
                      : Column(
                          children: items
                              .map(
                                (r) => _card(
                                  context,
                                  ref,
                                  s,
                                  r,
                                  profile?.id == r.doctorId,
                                ),
                              )
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
    ClinicalRecord r,
    bool own,
  ) => Card(
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
                r.recordNumber,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              StatusBadge(
                label: r.isDraft ? s.draft : s.doctorStatus('published'),
                color: r.isDraft ? AppTheme.warning : AppTheme.success,
              ),
            ],
          ),
          Text(s.doctorRecordType(r.recordType)),
          if (r.diagnosis != null) ...[
            const SizedBox(height: 6),
            Text('${s.diagnosis}: ${r.diagnosis}'),
          ],
          if (r.treatmentPlan != null)
            Text('${s.treatmentPlan}: ${r.treatmentPlan}'),
          if (own) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _edit(context, ref, s, r),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(s.edit),
                ),
                OutlinedButton.icon(
                  onPressed: () => _delete(context, ref, s, r),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(s.delete),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    ClinicalRecord? record,
  ) async {
    DoctorSchedule schedule;
    try {
      schedule =
          ref.read(doctorScheduleProvider).valueOrNull ??
          await ref.read(doctorWorkspaceApiProvider).getSchedule();
    } catch (error) {
      if (context.mounted) showDoctorError(context, s, error);
      return;
    }
    if (!context.mounted) return;
    if (record == null && schedule.appointments.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.noAppointments)));
      return;
    }
    final form = GlobalKey<FormState>(),
        complaint = TextEditingController(text: record?.chiefComplaint),
        diagnosis = TextEditingController(text: record?.diagnosis),
        treatment = TextEditingController(text: record?.treatmentPlan),
        clinical = TextEditingController(text: record?.clinicalNotes),
        doctor = TextEditingController(text: record?.doctorNotes);
    String? appointmentId =
        record?.appointmentId ??
        (schedule.appointments.isEmpty ? null : schedule.appointments.first.id);
    var type = record?.recordType ?? 'consultation',
        draft = record?.isDraft ?? true;
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          scrollable: true,
          title: Text(record == null ? s.create : s.edit),
          content: Form(
            key: form,
            child: SizedBox(
              width: 520,
              child: Column(
                children: [
                  if (record == null)
                    DropdownButtonFormField<String>(
                      initialValue: appointmentId,
                      decoration: InputDecoration(labelText: s.appointment),
                      items: schedule.appointments
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text('${a.date} · ${a.number}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => appointmentId = v,
                    ),
                  if (record == null)
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: InputDecoration(labelText: s.recordType),
                      items:
                          const [
                                'consultation',
                                'follow_up',
                                'diagnosis',
                                'treatment',
                                'other',
                              ]
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(s.doctorRecordType(v)),
                                ),
                              )
                              .toList(),
                      onChanged: (v) => type = v ?? type,
                    ),
                  if (record == null)
                    TextFormField(
                      controller: complaint,
                      decoration: InputDecoration(labelText: s.chiefComplaint),
                    ),
                  TextFormField(
                    controller: diagnosis,
                    decoration: InputDecoration(labelText: s.diagnosis),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? s.doctorRequiredField
                        : null,
                  ),
                  TextFormField(
                    controller: treatment,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: s.treatmentPlan),
                  ),
                  TextFormField(
                    controller: clinical,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: s.clinicalNotes),
                  ),
                  TextFormField(
                    controller: doctor,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: s.privateDoctorNotes,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.draft),
                    value: draft,
                    onChanged: (v) => setLocal(() => draft = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState?.validate() ?? false) {
                  Navigator.pop(context, {
                    'appointment_id': appointmentId,
                    'record_type': type,
                    'chief_complaint': complaint.text,
                    'diagnosis': diagnosis.text,
                    'treatment_plan': treatment.text,
                    'clinical_notes': clinical.text,
                    'doctor_notes': doctor.text,
                    'is_draft': draft,
                  });
                }
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    for (final c in [complaint, diagnosis, treatment, clinical, doctor]) {
      c.dispose();
    }
    if (payload == null || !context.mounted) return;
    final result = await ref
        .read(doctorRecordsProvider.notifier)
        .save(
          id: record?.id,
          appointmentId: payload['appointment_id'] as String?,
          recordType: payload['record_type'] as String,
          chiefComplaint: payload['chief_complaint'] as String,
          diagnosis: payload['diagnosis'] as String,
          treatmentPlan: payload['treatment_plan'] as String,
          clinicalNotes: payload['clinical_notes'] as String,
          doctorNotes: payload['doctor_notes'] as String,
          isDraft: payload['is_draft'] as bool,
        );
    if (context.mounted && result.error != null) {
      showDoctorError(context, s, result.error);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    ClinicalRecord r,
  ) async {
    final yes = await confirmDoctorAction(
      context,
      title: s.delete,
      body: s.deleteConfirmation,
      strings: s,
    );
    if (!yes || !context.mounted) return;
    final result = await ref.read(doctorRecordsProvider.notifier).delete(r.id);
    if (context.mounted && result.error != null) {
      showDoctorError(context, s, result.error);
    }
  }
}

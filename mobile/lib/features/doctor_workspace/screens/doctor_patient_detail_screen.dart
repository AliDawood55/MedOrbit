import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

class DoctorPatientDetailScreen extends ConsumerWidget {
  const DoctorPatientDetailScreen({super.key, required this.patientId});
  final String patientId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider),
        async = ref.watch(doctorPatientProvider(patientId));
    return AppScaffold(
      appBar: AppBar(title: Text(s.patientFile)),
      body: DoctorWorkspaceGate(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetryState(
            title: s.patientFile,
            message: doctorErrorMessage(s, e),
            retryLabel: s.retry,
            onRetry: () =>
                ref.read(doctorPatientProvider(patientId).notifier).load(),
          ),
          data: (d) => RefreshIndicator(
            onRefresh: () =>
                ref.read(doctorPatientProvider(patientId).notifier).load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
              children: [
                ResponsiveContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _patientHeader(context, s, d.patient),
                      const SizedBox(height: AppTheme.spaceXl),
                      SectionHeader(title: s.doctorAppointments),
                      if (d.appointments.isEmpty)
                        EmptyState(
                          icon: Icons.event_busy_outlined,
                          title: s.noAppointments,
                        )
                      else
                        ...d.appointments.map(
                          (a) => Card(
                            child: ListTile(
                              title: Text(a.number),
                              subtitle: Text(
                                '${a.date} · ${a.startTime.substring(0, 5)}',
                              ),
                              trailing: StatusBadge(
                                label: s.doctorStatus(a.status),
                                color: AppTheme.info,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppTheme.spaceXl),
                      SectionHeader(
                        title: s.sessionNotes,
                        trailing: FilledButton.icon(
                          onPressed: () => _note(context, ref, s),
                          icon: const Icon(Icons.note_add_outlined),
                          label: Text(s.addSessionNote),
                        ),
                      ),
                      if (d.notes.isEmpty)
                        EmptyState(
                          icon: Icons.note_alt_outlined,
                          title: s.noRecords,
                        )
                      else
                        ...d.notes.map((n) => _noteCard(context, s, n)),
                      const SizedBox(height: AppTheme.spaceXl),
                      SectionHeader(
                        title: s.prescriptionHistory,
                        trailing: FilledButton.icon(
                          onPressed: d.appointments.isEmpty
                              ? null
                              : () => _prescription(context, ref, s, d),
                          icon: const Icon(Icons.medication_outlined),
                          label: Text(s.createPrescription),
                        ),
                      ),
                      if (d.prescriptions.isEmpty)
                        EmptyState(
                          icon: Icons.medication_outlined,
                          title: s.noRecords,
                        )
                      else
                        ...d.prescriptions.map(
                          (p) => Card(
                            child: ListTile(
                              title: Text(p.number),
                              subtitle: Text(
                                [
                                  p.date,
                                  p.diagnosis,
                                ].whereType<String>().join(' · '),
                              ),
                              trailing: StatusBadge(
                                label: s.doctorStatus(p.status),
                                color: AppTheme.success,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppTheme.spaceXl),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => _endRelationship(context, ref, s),
                        icon: const Icon(Icons.link_off),
                        label: Text(s.endCareRelationship),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _patientHeader(BuildContext context, AppStrings s, DoctorPatient p) {
    final name =
        (s.isArabic
                ? [p.firstNameAr, p.lastNameAr]
                : [p.firstNameEn, p.lastNameEn])
            .whereType<String>()
            .join(' ')
            .trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              name.isEmpty ? p.email : name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              [
                p.email,
                p.phone,
                p.dateOfBirth,
                p.gender,
              ].whereType<String>().join('\n'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteCard(BuildContext context, AppStrings s, ClinicalRecord n) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusBadge(
                    label: n.isDraft ? s.draft : s.doctorStatus('published'),
                    color: n.isDraft ? AppTheme.warning : AppTheme.success,
                  ),
                  if (n.visibleToPatient)
                    StatusBadge(
                      label: s.visibleToPatient,
                      color: AppTheme.info,
                    ),
                ],
              ),
              if (n.chiefComplaint != null) ...[
                const SizedBox(height: 8),
                Text('${s.chiefComplaint}: ${n.chiefComplaint}'),
              ],
              if (n.diagnosis != null) Text('${s.diagnosis}: ${n.diagnosis}'),
              if (n.clinicalNotes != null) Text(n.clinicalNotes!),
            ],
          ),
        ),
      );

  Future<void> _note(BuildContext context, WidgetRef ref, AppStrings s) async {
    final form = GlobalKey<FormState>(),
        complaint = TextEditingController(),
        diagnosis = TextEditingController(),
        notes = TextEditingController();
    var draft = true, visible = false, type = 'consultation';
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          scrollable: true,
          title: Text(s.addSessionNote),
          content: Form(
            key: form,
            child: SizedBox(
              width: 480,
              child: Column(
                children: [
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
                    onChanged: (v) => type = v ?? 'consultation',
                  ),
                  TextFormField(
                    controller: complaint,
                    maxLength: 1000,
                    decoration: InputDecoration(labelText: s.chiefComplaint),
                  ),
                  TextFormField(
                    controller: diagnosis,
                    maxLength: 3000,
                    decoration: InputDecoration(labelText: s.diagnosis),
                  ),
                  TextFormField(
                    controller: notes,
                    minLines: 3,
                    maxLines: 7,
                    maxLength: 5000,
                    decoration: InputDecoration(labelText: s.clinicalNotes),
                    validator: (v) => (v?.trim().isEmpty ?? true)
                        ? s.doctorRequiredField
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.draft),
                    value: draft,
                    onChanged: (v) => setLocal(() => draft = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.visibleToPatient),
                    value: visible,
                    onChanged: (v) => setLocal(() => visible = v),
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
                if (!(form.currentState?.validate() ?? false)) return;
                Navigator.pop(context, {
                  'record_type': type,
                  'chief_complaint': complaint.text,
                  'diagnosis': diagnosis.text,
                  'clinical_notes': notes.text,
                  'is_draft': draft,
                  'visible_to_patient': visible,
                });
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    complaint.dispose();
    diagnosis.dispose();
    notes.dispose();
    if (payload == null || !context.mounted) return;
    if (payload['visible_to_patient'] == true) {
      final yes = await confirmDoctorAction(
        context,
        title: s.visibleToPatient,
        body: s.publishNoteWarning,
        strings: s,
      );
      if (!yes || !context.mounted) return;
    }
    final result = await ref
        .read(doctorPatientProvider(patientId).notifier)
        .addNote(
          recordType: payload['record_type'] as String,
          chiefComplaint: payload['chief_complaint'] as String,
          diagnosis: payload['diagnosis'] as String,
          clinicalNotes: payload['clinical_notes'] as String,
          isDraft: payload['is_draft'] as bool,
          visibleToPatient: payload['visible_to_patient'] as bool,
        );
    if (context.mounted && result.error != null) {
      showDoctorError(context, s, result.error);
    }
  }

  Future<void> _prescription(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorPatientDetail detail,
  ) async {
    final form = GlobalKey<FormState>(),
        diagnosis = TextEditingController(),
        instructions = TextEditingController(),
        doctorNotes = TextEditingController(),
        validUntil = TextEditingController();
    var appointmentId = detail.appointments.first.id;
    final meds = <_MedicationDraft>[_MedicationDraft()];
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          scrollable: true,
          title: Text(s.createPrescription),
          content: Form(
            key: form,
            child: SizedBox(
              width: 520,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: appointmentId,
                    decoration: InputDecoration(labelText: s.appointment),
                    items: detail.appointments
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text('${a.date} · ${a.number}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => appointmentId = v ?? appointmentId,
                  ),
                  TextFormField(
                    controller: validUntil,
                    decoration: InputDecoration(labelText: s.validUntil),
                  ),
                  TextFormField(
                    controller: diagnosis,
                    decoration: InputDecoration(labelText: s.diagnosis),
                  ),
                  TextFormField(
                    controller: instructions,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: s.instructions),
                  ),
                  TextFormField(
                    controller: doctorNotes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: s.privateDoctorNotes,
                    ),
                  ),
                  const Divider(),
                  ...meds.asMap().entries.map(
                    (entry) => _medicationFields(
                      s,
                      entry.value,
                      entry.key,
                      meds.length > 1
                          ? () => setLocal(() {
                              entry.value.dispose();
                              meds.removeAt(entry.key);
                            })
                          : null,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        setLocal(() => meds.add(_MedicationDraft())),
                    icon: const Icon(Icons.add),
                    label: Text(s.create),
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
                if (!(form.currentState?.validate() ?? false)) return;
                Navigator.pop(context, {
                  'appointment_id': appointmentId,
                  'valid_until': validUntil.text.trim(),
                  'diagnosis': diagnosis.text,
                  'instructions': instructions.text,
                  'doctor_notes': doctorNotes.text,
                  'items': meds.map((m) => m.json).toList(),
                });
              },
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    diagnosis.dispose();
    instructions.dispose();
    doctorNotes.dispose();
    validUntil.dispose();
    for (final m in meds) {
      m.dispose();
    }
    if (payload == null || !context.mounted) return;
    final result = await ref
        .read(doctorPatientProvider(patientId).notifier)
        .createPrescription(
          appointmentId: payload['appointment_id'] as String,
          validUntil: payload['valid_until'] as String,
          diagnosis: payload['diagnosis'] as String,
          instructions: payload['instructions'] as String,
          doctorNotes: payload['doctor_notes'] as String,
          items: (payload['items'] as List).cast<Map<String, dynamic>>(),
        );
    if (!context.mounted) return;
    if (result.error != null) {
      showDoctorError(context, s, result.error);
      return;
    }
    final status = result.value?.safetyStatus;
    if (status == 'warning' || status == 'unavailable') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'warning' ? s.safetyWarning : s.safetyUnavailable,
          ),
          duration: const Duration(seconds: 7),
        ),
      );
    }
  }

  Widget _medicationFields(
    AppStrings s,
    _MedicationDraft m,
    int index,
    VoidCallback? remove,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: Text('${s.createPrescription} ${index + 1}')),
              if (remove != null)
                IconButton(
                  onPressed: remove,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
            ],
          ),
          TextFormField(
            controller: m.ar,
            decoration: InputDecoration(labelText: s.medicationNameArabic),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? s.doctorRequiredField : null,
          ),
          TextFormField(
            controller: m.en,
            decoration: InputDecoration(labelText: s.medicationNameEnglish),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? s.doctorRequiredField : null,
          ),
          TextFormField(
            controller: m.dosage,
            decoration: InputDecoration(labelText: s.dosage),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? s.doctorRequiredField : null,
          ),
          TextFormField(
            controller: m.frequency,
            decoration: InputDecoration(labelText: s.frequency),
            validator: (v) =>
                (v?.trim().isEmpty ?? true) ? s.doctorRequiredField : null,
          ),
          TextFormField(
            controller: m.duration,
            decoration: InputDecoration(labelText: s.duration),
          ),
          TextFormField(
            controller: m.quantity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: s.quantity),
            validator: (v) {
              final n = int.tryParse(v ?? '');
              return n == null || n <= 0 ? s.invalidValue : null;
            },
          ),
          TextFormField(
            controller: m.instructions,
            decoration: InputDecoration(labelText: s.instructions),
          ),
        ],
      ),
    ),
  );
  Future<void> _endRelationship(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
  ) async {
    final reason = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.endCareRelationship),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.endRelationshipWarning),
            TextField(
              controller: reason,
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: s.reason),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (yes != true || !context.mounted) return;
    final result = await ref
        .read(doctorPatientProvider(patientId).notifier)
        .endRelationship(text);
    if (!context.mounted) return;
    if (result.error != null) {
      showDoctorError(context, s, result.error);
    } else {
      ref.invalidate(doctorPatientsProvider);
      context.pop();
    }
  }
}

class _MedicationDraft {
  final ar = TextEditingController(),
      en = TextEditingController(),
      dosage = TextEditingController(),
      frequency = TextEditingController(),
      duration = TextEditingController(),
      quantity = TextEditingController(text: '1'),
      instructions = TextEditingController();
  Map<String, dynamic> get json => {
    'medication_name_ar': ar.text.trim(),
    'medication_name_en': en.text.trim(),
    'dosage': dosage.text.trim(),
    'frequency': frequency.text.trim(),
    'duration': duration.text.trim(),
    'quantity': int.parse(quantity.text),
    'instructions': instructions.text.trim(),
  };
  void dispose() {
    for (final c in [
      ar,
      en,
      dosage,
      frequency,
      duration,
      quantity,
      instructions,
    ]) {
      c.dispose();
    }
  }
}

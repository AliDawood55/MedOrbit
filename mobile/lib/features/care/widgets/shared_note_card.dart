import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/widgets/status_badge.dart';
import '../providers/care_provider.dart';

/// Renders one shared clinical note. Only reads the fields
/// [SharedNoteModel] exposes (`record_type`, `chief_complaint`,
/// `diagnosis`, `treatment_plan`, `clinical_notes`, `created_at`) — there is
/// no `doctor_notes` field to accidentally render.
class SharedNoteCard extends StatelessWidget {
  const SharedNoteCard({super.key, required this.entry, required this.isArabic, required this.strings});

  final SharedNoteEntry entry;
  final bool isArabic;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = entry.note;
    final doctorName = entry.doctor.displayName(isArabic);
    final date = _formatted(note.createdAt, isArabic);

    return Card(
      key: ValueKey('shared-note-${note.id}'),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceXs,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(doctorName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: AppTheme.weightBold)),
                if (date != null)
                  Text(date, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSm),
            StatusBadge(label: recordTypeLabel(note.recordType, strings), color: AppTheme.secondary),
            if (note.diagnosis != null) ..._labeledBlock(context, strings.detailDiagnosis, note.diagnosis!),
            if (note.chiefComplaint != null) ..._labeledBlock(context, strings.detailChiefComplaint, note.chiefComplaint!),
            if (note.treatmentPlan != null) ..._labeledBlock(context, strings.detailTreatmentPlan, note.treatmentPlan!),
            if (note.clinicalNotes != null) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Text(note.clinicalNotes!, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

List<Widget> _labeledBlock(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return [
    const SizedBox(height: AppTheme.spaceMd),
    Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    const SizedBox(height: AppTheme.space2xs),
    Text(value, style: theme.textTheme.bodyMedium),
  ];
}

String? _formatted(String? value, bool isArabic) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return null;
  return formatDate(parsed, localeCode: isArabic ? 'ar' : 'en');
}

/// Same `record_type` → label mapping used for the records timeline
/// (`record_detail_sheet.dart`) — both read the same
/// `medorbit.medical_records.record_type` column.
String recordTypeLabel(String? recordType, AppStrings strings) {
  return switch (recordType?.toLowerCase()) {
    'consultation' => strings.recordSubtypeConsultation,
    'lab_result' => strings.recordSubtypeLabResult,
    'diagnosis' => strings.recordSubtypeDiagnosis,
    'imaging' => strings.recordSubtypeImaging,
    'procedure' => strings.recordSubtypeProcedure,
    _ => strings.typeRecord,
  };
}

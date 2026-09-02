import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/patient_doctor_models.dart';
import '../providers/my_doctors_provider.dart';

class SharedDoctorNotesScreen extends ConsumerWidget {
  const SharedDoctorNotesScreen({
    super.key,
    required this.doctorId,
    this.doctor,
  });
  final String doctorId;
  final PatientDoctor? doctor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final notes = ref.watch(sharedDoctorNotesProvider(doctorId));
    final doctorName = doctor?.fullName(isArabic);
    return AppScaffold(
      appBar: AppBar(title: Text(strings.sharedDoctorNotesTitle)),
      body: notes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetryState(
          title: strings.sharedDoctorNotesLoadErrorTitle,
          message: strings.sharedDoctorNotesLoadErrorHint,
          retryLabel: strings.retry,
          onRetry: () => ref.invalidate(sharedDoctorNotesProvider(doctorId)),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(sharedDoctorNotesProvider(doctorId)),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageIntro(
                      title: strings.sharedDoctorNotesTitle,
                      subtitle: doctorName == null || doctorName.isEmpty
                          ? strings.sharedDoctorNotesSubtitle
                          : strings.sharedDoctorNotesFor(doctorName),
                      icon: Icons.note_alt_outlined,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    if (items.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spaceXl),
                          child: EmptyState(
                            icon: Icons.note_outlined,
                            title: strings.sharedDoctorNotesEmptyTitle,
                            hint: strings.sharedDoctorNotesEmptyHint,
                          ),
                        ),
                      )
                    else
                      for (final note in items) ...[
                        _NoteCard(
                          note: note,
                          strings: strings,
                          isArabic: isArabic,
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.strings,
    required this.isArabic,
  });
  final SharedDoctorNote note;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.recordType ?? strings.sharedDoctorNotesTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (note.createdAt case final value?) ...[
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              _formatDate(value, isArabic),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          for (final entry in [
            (strings.detailChiefComplaint, note.chiefComplaint),
            (strings.sharedNoteDiagnosis, note.diagnosis),
            (strings.sharedNoteTreatmentPlan, note.treatmentPlan),
            (strings.sharedNoteClinicalNotes, note.clinicalNotes),
          ])
            if (entry.$2 != null && entry.$2!.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Text(entry.$1, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppTheme.spaceXs),
              Text(entry.$2!),
            ],
        ],
      ),
    ),
  );
}

String _formatDate(String value, bool isArabic) {
  try {
    return formatDate(
      DateTime.parse(value),
      localeCode: isArabic ? 'ar' : 'en',
    );
  } catch (_) {
    return value;
  }
}

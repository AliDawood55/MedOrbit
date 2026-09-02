import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/patient_doctor_models.dart';
import '../providers/my_doctors_provider.dart';

class MyDoctorsScreen extends ConsumerWidget {
  const MyDoctorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final doctors = ref.watch(myDoctorsProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(strings.myDoctorsTitle)),
      body: doctors.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetryState(
          title: strings.myDoctorsLoadErrorTitle,
          message: strings.myDoctorsLoadErrorHint,
          retryLabel: strings.retry,
          onRetry: () => ref.invalidate(myDoctorsProvider),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myDoctorsProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageIntro(
                      title: strings.myDoctorsTitle,
                      subtitle: strings.myDoctorsSubtitle,
                      icon: Icons.health_and_safety_outlined,
                      color: AppTheme.secondary,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    if (items.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spaceXl),
                          child: EmptyState(
                            icon: Icons.group_outlined,
                            title: strings.myDoctorsEmptyTitle,
                            hint: strings.myDoctorsEmptyHint,
                          ),
                        ),
                      )
                    else
                      for (final doctor in items) ...[
                        _DoctorCard(
                          doctor: doctor,
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

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.doctor,
    required this.strings,
    required this.isArabic,
  });
  final PatientDoctor doctor;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final name = doctor.fullName(isArabic);
    final specialty = doctor.specialty(isArabic);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? strings.doctorLabel : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (specialty != null)
                        Text(
                          specialty,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMd),
            Text(
              _appointmentSummary(doctor, strings, isArabic),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppTheme.spaceMd),
            LayoutBuilder(
              builder: (context, constraints) {
                final viewDoctor = FilledButton.icon(
                  onPressed: () =>
                      context.push(RoutePaths.doctorDetailPath(doctor.id)),
                  icon: const Icon(Icons.person_outline_rounded),
                  label: Text(strings.viewDoctorAction),
                );
                final sharedNotes = OutlinedButton.icon(
                  onPressed: () => context.push(
                    RoutePaths.sharedDoctorNotesPath(doctor.id),
                    extra: doctor,
                  ),
                  icon: const Icon(Icons.notes_rounded),
                  label: Text(strings.sharedDoctorNotesAction),
                );

                if (constraints.maxWidth < AppTheme.compactBreakpoint) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      viewDoctor,
                      const SizedBox(height: AppTheme.spaceSm),
                      sharedNotes,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: viewDoctor),
                    const SizedBox(width: AppTheme.spaceSm),
                    Expanded(child: sharedNotes),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _appointmentSummary(
  PatientDoctor doctor,
  AppStrings strings,
  bool isArabic,
) {
  final date = doctor.hasUpcoming
      ? doctor.nextAppointmentDate
      : doctor.lastAppointmentDate;
  if (date == null) return strings.myDoctorsCareRelationship;
  try {
    final formatted = formatDate(
      parseDateOnly(date),
      localeCode: isArabic ? 'ar' : 'en',
    );
    return doctor.hasUpcoming
        ? strings.myDoctorsNextAppointment(formatted)
        : strings.myDoctorsLastAppointment(formatted);
  } catch (_) {
    return strings.myDoctorsCareRelationship;
  }
}

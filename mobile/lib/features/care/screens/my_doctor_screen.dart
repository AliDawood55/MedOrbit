import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../appointments/providers/appointments_provider.dart';
import '../../appointments/widgets/appointment_card.dart';
import '../models/my_doctor_model.dart';
import '../providers/care_provider.dart';
import '../widgets/doctor_care_card.dart';
import '../widgets/shared_note_card.dart';

class MyDoctorScreen extends ConsumerWidget {
  const MyDoctorScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    Future<void> ignoreFailure(Future<void> Function() action) async {
      try {
        await action();
      } catch (_) {
        // Each section below exposes its own retryable error state.
      }
    }

    await Future.wait([
      ignoreFailure(() async {
        final _ = await ref.refresh(myDoctorsProvider.future);
      }),
      ignoreFailure(() => ref.read(appointmentsControllerProvider.notifier).load()),
    ]);
    ref.invalidate(sharedNotesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final doctorsAsync = ref.watch(myDoctorsProvider);
    final origin = ref.watch(activeOriginProvider);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.myDoctorTitle)),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageIntro(
                      title: strings.myDoctorTitle,
                      subtitle: strings.myDoctorSubtitle,
                      icon: Icons.favorite_rounded,
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(title: strings.myDoctorsSectionTitle),
                    _DoctorsSection(
                      doctorsAsync: doctorsAsync,
                      isArabic: isArabic,
                      strings: strings,
                      origin: origin,
                      onRetry: () => ref.invalidate(myDoctorsProvider),
                    ),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(title: strings.upcomingWithMyDoctorsTitle),
                    _UpcomingSection(strings: strings, isArabic: isArabic),
                    const SizedBox(height: AppTheme.spaceXl),
                    SectionHeader(title: strings.sharedNotesSectionTitle),
                    _SharedNotesSection(strings: strings, isArabic: isArabic),
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

class _DoctorsSection extends StatelessWidget {
  const _DoctorsSection({
    required this.doctorsAsync,
    required this.isArabic,
    required this.strings,
    required this.origin,
    required this.onRetry,
  });

  final AsyncValue<List<MyDoctorModel>> doctorsAsync;
  final bool isArabic;
  final AppStrings strings;
  final String origin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return doctorsAsync.when(
      data: (doctors) {
        if (doctors.isEmpty) {
          return Card(
            child: EmptyState(
              icon: Icons.favorite_border_rounded,
              title: strings.noActiveDoctorsTitle,
              hint: strings.noActiveDoctorsHint,
              action: PrimaryButton(
                label: strings.browseDoctorsAction,
                onPressed: () => context.push(RoutePaths.doctors),
              ),
            ),
          );
        }

        return Column(
          children: doctors
              .map(
                (doctor) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
                  child: _DoctorCareCardItem(
                    doctor: doctor,
                    isArabic: isArabic,
                    strings: strings,
                    origin: origin,
                  ),
                ),
              )
              .toList(),
        );
      },
      loading: () => const _SectionLoading(),
      error: (error, stackTrace) => Card(
        child: ErrorRetryState(
          title: strings.doctorsLoadErrorTitle,
          message: strings.doctorsLoadErrorMessage,
          retryLabel: strings.retry,
          onRetry: onRetry,
          variant: ErrorRetryVariant.compact,
        ),
      ),
    );
  }
}

class _DoctorCareCardItem extends StatefulWidget {
  const _DoctorCareCardItem({
    required this.doctor,
    required this.isArabic,
    required this.strings,
    required this.origin,
  });

  final MyDoctorModel doctor;
  final bool isArabic;
  final AppStrings strings;
  final String origin;

  @override
  State<_DoctorCareCardItem> createState() => _DoctorCareCardItemState();
}

class _DoctorCareCardItemState extends State<_DoctorCareCardItem> {
  // Guards against the go_router Navigator's
  // "'!keyReservation.contains(key)'" assertion, which fires when the same
  // route is pushed twice before the first push's page has finished
  // registering — a fast double-tap on these buttons was enough to trigger
  // it. Reset once the pushed route pops back to us.
  bool _isNavigating = false;

  void _navigate(String path) {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    context.push(path).whenComplete(() {
      if (mounted) setState(() => _isNavigating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return DoctorCareCard(
      doctor: widget.doctor,
      isArabic: widget.isArabic,
      strings: widget.strings,
      avatarOrigin: widget.origin,
      onViewDoctor: () => _navigate(RoutePaths.doctorDetailPath(widget.doctor.id)),
      onBookAppointment: () =>
          _navigate(RoutePaths.appointmentBookingPath(doctorId: widget.doctor.id)),
    );
  }
}

class _UpcomingSection extends ConsumerWidget {
  const _UpcomingSection({required this.strings, required this.isArabic});

  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upcomingAsync = ref.watch(upcomingWithMyDoctorsProvider);

    return upcomingAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Card(
            child: EmptyState(
              icon: Icons.event_busy_outlined,
              title: strings.noUpcomingWithMyDoctorsTitle,
              hint: strings.noUpcomingWithMyDoctorsHint,
              variant: EmptyStateVariant.compact,
            ),
          );
        }

        return Column(
          children: entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
                  child: AppointmentCard(entry: entry, strings: strings, isArabic: isArabic),
                ),
              )
              .toList(),
        );
      },
      loading: () => const _SectionLoading(),
      error: (error, stackTrace) => Card(
        child: ErrorRetryState(
          title: strings.upcomingWithMyDoctorsErrorTitle,
          message: strings.upcomingWithMyDoctorsErrorMessage,
          retryLabel: strings.retry,
          onRetry: () {
            ref.invalidate(myDoctorsProvider);
            ref.read(appointmentsControllerProvider.notifier).load();
          },
          variant: ErrorRetryVariant.compact,
        ),
      ),
    );
  }
}

class _SharedNotesSection extends ConsumerWidget {
  const _SharedNotesSection({required this.strings, required this.isArabic});

  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(sharedNotesProvider);

    return notesAsync.when(
      data: (entries) {
        if (entries.isEmpty) {
          return Card(
            child: EmptyState(
              icon: Icons.notes_outlined,
              title: strings.noSharedNotesTitle,
              hint: strings.noSharedNotesHint,
              variant: EmptyStateVariant.compact,
            ),
          );
        }

        return Column(
          children: entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
                  child: SharedNoteCard(entry: entry, isArabic: isArabic, strings: strings),
                ),
              )
              .toList(),
        );
      },
      loading: () => const _SectionLoading(),
      error: (error, stackTrace) => Card(
        child: ErrorRetryState(
          title: strings.sharedNotesErrorTitle,
          message: strings.sharedNotesErrorMessage,
          retryLabel: strings.retry,
          onRetry: () => ref.invalidate(sharedNotesProvider),
          variant: ErrorRetryVariant.compact,
        ),
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(AppTheme.spaceLg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }
}

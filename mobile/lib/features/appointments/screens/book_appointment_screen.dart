import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../discovery/models/doctor_models.dart';
import '../../discovery/widgets/doctor_result_card.dart';
import '../providers/booking_provider.dart';
import '../widgets/booking_confirm_step.dart';
import '../widgets/booking_doctor_step.dart';
import '../widgets/booking_slot_step.dart';
import '../widgets/booking_success_sheet.dart';

/// Patient appointment booking wizard: doctor → clinic/date/slot → confirm.
///
/// [doctorId], when present (deep link from the doctor detail screen), skips
/// straight to the slot step once that doctor loads.
class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key, this.doctorId});

  final String? doctorId;

  @override
  ConsumerState<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends ConsumerState<BookAppointmentScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bookingControllerProvider.notifier).init(doctorId: widget.doctorId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingControllerProvider);
    final notifier = ref.read(bookingControllerProvider.notifier);
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';

    final result = state.result;

    return AppScaffold(
      appBar: AppBar(title: Text(strings.bookingWizardTitle)),
      useSafeArea: true,
      keyboardAware: true,
      body: result != null
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spaceLg),
                child: ResponsiveContent(
                  maxWidth: 480,
                  child: BookingSuccessSheet(
                    strings: strings,
                    appointment: result,
                    onViewAppointments: () => context.go(RoutePaths.appointments),
                    onBookAnother: notifier.startOver,
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
              children: [
                ResponsiveContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StepIndicator(step: state.step, strings: strings),
                      const SizedBox(height: AppTheme.spaceLg),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spaceLg),
                          child: _StepContent(state: state, strings: strings, isArabic: isArabic, notifier: notifier),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceLg),
                      if (state.step != BookingWizardStep.confirm) _WizardActions(state: state, strings: strings, notifier: notifier),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({required this.state, required this.strings, required this.isArabic, required this.notifier});

  final BookingState state;
  final AppStrings strings;
  final bool isArabic;
  final BookingController notifier;

  @override
  Widget build(BuildContext context) {
    switch (state.step) {
      case BookingWizardStep.doctor:
        return _DoctorStepContent(state: state, strings: strings, notifier: notifier);
      case BookingWizardStep.slot:
        final doctor = state.draft.doctor;
        if (doctor == null) return const SizedBox.shrink();
        return BookingSlotStep(
          strings: strings,
          isArabic: isArabic,
          clinics: state.draft.clinics,
          selectedClinic: state.draft.clinic,
          selectedDate: state.draft.date,
          slots: state.slots,
          selectedSlot: state.draft.slot,
          isLoadingSlots: state.isLoadingSlots,
          slotsFailed: state.slotsFailed,
          showSlotBusy: state.submitError?.kind == BookingSubmitErrorKind.slotBusy,
          onSelectClinic: notifier.selectClinic,
          onSelectDate: notifier.selectDate,
          onSelectSlot: notifier.selectSlot,
          onRetry: notifier.loadSlots,
        );
      case BookingWizardStep.confirm:
        final doctor = state.draft.doctor;
        final clinic = state.draft.clinic;
        final date = state.draft.date;
        final slot = state.draft.slot;
        if (doctor == null || clinic == null || date == null || slot == null) return const SizedBox.shrink();
        return BookingConfirmStep(
          strings: strings,
          doctor: doctor,
          clinic: clinic,
          date: date,
          slot: slot,
          reason: state.draft.reason,
          notes: state.draft.notes,
          isSubmitting: state.isSubmitting,
          submitError: state.submitError,
          onReasonChanged: notifier.setReason,
          onNotesChanged: notifier.setNotes,
          onSubmit: notifier.submit,
        );
    }
  }
}

class _DoctorStepContent extends StatelessWidget {
  const _DoctorStepContent({required this.state, required this.strings, required this.notifier});

  final BookingState state;
  final AppStrings strings;
  final BookingController notifier;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingPreselectedDoctor) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.space2xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final doctor = state.draft.doctor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.preselectFailure != null) ...[
          state.preselectFailure == PreselectDoctorFailure.notFound
              ? EmptyState(icon: Icons.person_off_outlined, title: strings.doctorNotFoundMessage, variant: EmptyStateVariant.compact)
              : ErrorRetryState(
                  title: strings.doctorLoadErrorMessage,
                  message: strings.errorGeneric,
                  retryLabel: strings.retry,
                  onRetry: () => notifier.loadInitialDoctors(),
                  variant: ErrorRetryVariant.compact,
                ),
          const SizedBox(height: AppTheme.spaceLg),
        ],
        if (doctor != null)
          _SelectedDoctorCard(
            doctor: doctor,
            isLoading: state.isLoadingDoctorDetail,
            strings: strings,
            onChange: notifier.changeDoctor,
          )
        else
          BookingDoctorStep(
            strings: strings,
            query: state.doctorQuery,
            results: state.doctorResults,
            isLoading: state.isLoadingDoctors || state.isLoadingDoctorDetail,
            hasError: state.doctorListFailed,
            onSearch: notifier.searchDoctors,
            onSelect: notifier.selectDoctor,
            onRetry: () => notifier.searchDoctors(state.doctorQuery),
          ),
      ],
    );
  }
}

class _SelectedDoctorCard extends StatelessWidget {
  const _SelectedDoctorCard({required this.doctor, required this.isLoading, required this.strings, required this.onChange});

  final Doctor doctor;
  final bool isLoading;
  final AppStrings strings;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final name = doctorDisplayName(doctor, direction);
    final specialty = doctorDisplaySpecialty(doctor, direction);

    return Row(
      children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: AppTheme.primaryTint,
          backgroundImage: doctor.extra['profile_image_url'] is String ? NetworkImage(doctor.extra['profile_image_url'] as String) : null,
          child: doctor.extra['profile_image_url'] is String
              ? null
              : Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(), style: const TextStyle(color: AppTheme.primary, fontWeight: AppTheme.weightExtraBold)),
        ),
        const SizedBox(width: AppTheme.spaceMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: AppTheme.weightExtraBold)),
              if (specialty != null) Text(specialty, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (isLoading)
          const SizedBox.square(dimension: AppTheme.iconLg, child: CircularProgressIndicator(strokeWidth: 2))
        else
          TextButton(onPressed: onChange, child: Text(strings.changeDoctorAction)),
      ],
    );
  }
}

class _WizardActions extends StatelessWidget {
  const _WizardActions({required this.state, required this.strings, required this.notifier});

  final BookingState state;
  final AppStrings strings;
  final BookingController notifier;

  @override
  Widget build(BuildContext context) {
    final canGoNext = switch (state.step) {
      BookingWizardStep.doctor => state.draft.doctor != null && !state.isLoadingDoctorDetail,
      BookingWizardStep.slot => state.draft.clinic != null && state.draft.slot != null,
      BookingWizardStep.confirm => false,
    };

    void onNext() {
      switch (state.step) {
        case BookingWizardStep.doctor:
          notifier.goToSlotStep();
        case BookingWizardStep.slot:
          notifier.goToConfirm();
        case BookingWizardStep.confirm:
          break;
      }
    }

    return Row(
      children: [
        if (state.step != BookingWizardStep.doctor)
          OutlinedButton(
            onPressed: state.step == BookingWizardStep.slot ? notifier.backToDoctorStep : notifier.backToSlotStep,
            child: Text(strings.backAction),
          )
        else
          const SizedBox.shrink(),
        const Spacer(),
        PrimaryButton(label: strings.nextAction, onPressed: canGoNext ? onNext : null),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.strings});

  final BookingWizardStep step;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (BookingWizardStep.doctor, strings.bookingStepDoctor),
      (BookingWizardStep.slot, strings.bookingStepSlot),
      (BookingWizardStep.confirm, strings.bookingStepConfirm),
    ];
    final activeIndex = steps.indexWhere((entry) => entry.$1 == step);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Container(
              width: 28,
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: AppTheme.spaceXs),
              color: i <= activeIndex ? AppTheme.success : Theme.of(context).colorScheme.outlineVariant,
            ),
          _StepCircle(index: i + 1, isActive: i == activeIndex, isDone: i < activeIndex),
        ],
      ],
    );
  }
}

class _StepCircle extends StatelessWidget {
  const _StepCircle({required this.index, required this.isActive, required this.isDone});

  final int index;
  final bool isActive;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isDone ? AppTheme.success : (isActive ? AppTheme.primary : scheme.surfaceContainerHighest);
    final foreground = isDone || isActive ? Colors.white : scheme.onSurfaceVariant;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Text('$index', style: TextStyle(color: foreground, fontWeight: AppTheme.weightExtraBold)),
    );
  }
}

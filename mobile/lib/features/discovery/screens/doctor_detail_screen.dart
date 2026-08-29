import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/doctor_models.dart';
import '../providers/discovery_provider.dart';
import '../widgets/doctor_detail_sections.dart';

class DoctorDetailScreen extends ConsumerStatefulWidget {
  const DoctorDetailScreen({super.key, required this.doctorId});
  final String doctorId;
  @override
  ConsumerState<DoctorDetailScreen> createState() => _DoctorDetailScreenState();
}

class _DoctorDetailScreenState extends ConsumerState<DoctorDetailScreen> {
  DateTime? _date;
  bool _healScheduled = false;

  Future<void> _load() async {
    await ref.read(discoveryControllerProvider.notifier).loadDoctorDetail(widget.doctorId);
  }

  Future<void> _availability() async {
    final date = _date;
    await ref.read(discoveryControllerProvider.notifier).loadDoctorAvailability(
          widget.doctorId,
          date: date?.toIso8601String().split('T').first,
        );
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(discoveryControllerProvider);

    // Depending on this screen's route status makes the screen rebuild when it
    // becomes current again (e.g. the doctor route pushed on top of it is
    // popped). Falls back to `true` when there is no enclosing ModalRoute.
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;

    // The detail/availability slices are shared across doctors. Only trust
    // them when they belong to *this* screen's doctor; otherwise self-heal by
    // reloading — but ONLY while this screen's route is actually current. A
    // Doctor Detail route sitting hidden under another one must never rebind
    // the shared `selectedDoctorId` just because a different doctor became
    // selected on top of it (that would cause ownership ping-pong between the
    // two stacked screens and duplicate network requests).
    final isThisDoctor = state.selectedDoctorId == widget.doctorId;
    if (isThisDoctor) {
      _healScheduled = false;
    } else if (!_healScheduled && routeIsCurrent) {
      _healScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // The route may have stopped being current between scheduling and now
        // (another doctor pushed on top), or ownership may already have been
        // restored. Re-check before touching the shared controller.
        final stillCurrent = ModalRoute.of(context)?.isCurrent ?? true;
        final stillMismatched =
            ref.read(discoveryControllerProvider).selectedDoctorId != widget.doctorId;
        if (!stillCurrent || !stillMismatched) {
          _healScheduled = false;
          return;
        }
        if (_date != null) setState(() => _date = null);
        _load();
      });
    }

    final detail = isThisDoctor ? state.selectedDoctorDetail : null;
    final doctor = detail?.doctor;
    final error = isThisDoctor ? state.doctorDetailError : null;
    final loading = !isThisDoctor || state.isLoadingDoctorDetail;

    final Widget content;
    if (loading && doctor == null) {
      content = _LoadingDetail(strings: strings);
    } else if (error != null) {
      content = Card(
        child: ErrorRetryState(
          title: strings.doctorDetailLoadErrorTitle,
          message: error.message,
          retryLabel: strings.retry,
          onRetry: _load,
          variant: ErrorRetryVariant.compact,
        ),
      );
    } else if (doctor == null) {
      content = Card(
        child: EmptyState(
          icon: Icons.person_off_outlined,
          title: strings.doctorDetailNotFoundTitle,
          hint: strings.doctorDetailNotFoundHint,
          variant: EmptyStateVariant.compact,
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DoctorDetailSections(
            doctor: doctor,
            clinics: detail?.clinics ?? const [],
            reviews: detail?.reviews ?? const [],
          ),
          const SizedBox(height: AppTheme.spaceLg),
          _BookingCta(strings: strings, doctor: doctor, doctorId: widget.doctorId),
          const SizedBox(height: AppTheme.spaceLg),
          _AvailabilitySection(
            strings: strings,
            date: _date,
            slots: isThisDoctor ? state.doctorAvailability : const [],
            loading: isThisDoctor && state.isLoadingDoctorAvailability,
            error: isThisDoctor ? state.doctorAvailabilityError?.message : null,
            onDate: (date) {
              setState(() => _date = date);
              _availability();
            },
            onRetry: _availability,
          ),
        ],
      );
    }

    return AppScaffold(
      appBar: AppBar(title: Text(strings.doctorDetailTitle)),
      useSafeArea: true,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [ResponsiveContent(maxWidth: 960, child: content)],
        ),
      ),
    );
  }
}

/// Booking call-to-action. Mirrors the current web doctor profile: an active
/// "Book" link only when `is_accepting_patients === true`; a disabled control
/// with a localized explanation otherwise. The three accepting-patients states
/// are kept distinct (true / false / unknown) — `false` is never shown as
/// "unknown".
class _BookingCta extends StatelessWidget {
  const _BookingCta({required this.strings, required this.doctor, required this.doctorId});
  final AppStrings strings;
  final Doctor doctor;
  final String doctorId;

  @override
  Widget build(BuildContext context) {
    if (doctor.isAcceptingPatients == true) {
      return PrimaryButton(
        label: strings.bookNewAppointment,
        onPressed: () =>
            context.push(RoutePaths.appointmentBookingPath(doctorId: doctorId)),
      );
    }
    final message = doctor.isAcceptingPatients == false
        ? strings.doctorBookingUnavailableNotAccepting
        : strings.doctorBookingUnavailableUnknown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineMessage(message: message, tone: InlineMessageTone.warning),
        const SizedBox(height: AppTheme.spaceMd),
        PrimaryButton(label: strings.bookNewAppointment, onPressed: null),
      ],
    );
  }
}

class _AvailabilitySection extends StatelessWidget {
  const _AvailabilitySection({
    required this.strings,
    required this.date,
    required this.slots,
    required this.loading,
    required this.error,
    required this.onDate,
    required this.onRetry,
  });
  final AppStrings strings;
  final DateTime? date;
  final List<DoctorAvailabilitySlot> slots;
  final bool loading;
  final String? error;
  final ValueChanged<DateTime?> onDate;
  final VoidCallback onRetry;

  String _time(String? raw) {
    final value = raw?.trim() ?? '';
    return value.length >= 5 ? value.substring(0, 5) : value;
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (loading) {
      body = const Center(child: Padding(padding: EdgeInsets.all(AppTheme.spaceMd), child: CircularProgressIndicator()));
    } else if (error != null) {
      body = ErrorRetryState(
        title: strings.doctorAvailabilityLoadError,
        message: error!,
        retryLabel: strings.retry,
        onRetry: onRetry,
        variant: ErrorRetryVariant.compact,
      );
    } else if (date == null) {
      body = Text(strings.doctorAvailabilityChooseDateHint);
    } else if (slots.isEmpty) {
      body = Text(strings.doctorAvailabilityNoneForDate);
    } else {
      body = Wrap(
        spacing: AppTheme.spaceSm,
        runSpacing: AppTheme.spaceSm,
        children: [
          for (final slot in slots)
            Chip(
              label: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  [_time(slot.startTime), _time(slot.endTime)]
                      .where((value) => value.isNotEmpty)
                      .join('–'),
                ),
              ),
            ),
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: strings.doctorAvailabilityTitle,
              trailing: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                    initialDate: date ?? DateTime.now(),
                  );
                  if (picked != null) onDate(picked);
                },
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  date == null
                      ? strings.doctorChooseDateAction
                      : date!.toLocal().toString().split(' ').first,
                ),
              ),
            ),
            body,
          ],
        ),
      ),
    );
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail({required this.strings});
  final AppStrings strings;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Row(
            children: [
              const SizedBox.square(
                dimension: AppTheme.iconLg,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(child: Text(strings.doctorLoadingDetails)),
            ],
          ),
        ),
      );
}

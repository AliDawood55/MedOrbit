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
import '../providers/discovery_provider.dart';
import '../widgets/doctor_detail_sections.dart';

class DoctorDetailScreen extends ConsumerStatefulWidget { const DoctorDetailScreen({super.key, required this.doctorId}); final String doctorId; @override ConsumerState<DoctorDetailScreen> createState() => _DoctorDetailScreenState(); }
class _DoctorDetailScreenState extends ConsumerState<DoctorDetailScreen> { DateTime? _date;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { _load(); }); }
  Future<void> _load() async { await ref.read(discoveryControllerProvider.notifier).loadDoctorDetail(widget.doctorId); }
  Future<void> _availability() async { final date = _date; await ref.read(discoveryControllerProvider.notifier).loadDoctorAvailability(widget.doctorId, date: date?.toIso8601String().split('T').first); }
  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(discoveryControllerProvider);
    final detail = state.selectedDoctorDetail;
    final doctor = detail?.doctor;
    final content = state.isLoadingDoctorDetail && doctor == null
        ? _LoadingDetail(strings: strings)
        : state.doctorDetailError != null
            ? Card(child: ErrorRetryState(title: strings.doctorDetailLoadErrorTitle, message: state.doctorDetailError!.message, retryLabel: strings.retry, onRetry: _load, variant: ErrorRetryVariant.compact))
            : doctor == null
                ? Card(child: EmptyState(icon: Icons.person_off_outlined, title: strings.doctorDetailNotFoundTitle, hint: strings.doctorDetailNotFoundHint, variant: EmptyStateVariant.compact))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [DoctorDetailSections(doctor: doctor, clinics: detail?.clinics ?? const [], reviews: detail?.reviews ?? const []), const SizedBox(height: AppTheme.spaceLg), _AvailabilitySection(strings: strings, date: _date, slots: state.doctorAvailability, loading: state.isLoadingDoctorAvailability, error: state.doctorAvailabilityError?.message, onDate: (date) { setState(() => _date = date); _availability(); }, onRetry: _availability), const SizedBox(height: AppTheme.spaceLg), PrimaryButton(label: strings.bookNewAppointment, onPressed: () => context.push(RoutePaths.appointmentBookingPath(doctorId: widget.doctorId)))]);
    return AppScaffold(appBar: AppBar(title: Text(strings.doctorDetailTitle)), useSafeArea: true, body: RefreshIndicator(onRefresh: _load, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg), children: [ResponsiveContent(maxWidth: 960, child: content)])));
  }
}
class _AvailabilitySection extends StatelessWidget { const _AvailabilitySection({required this.strings, required this.date, required this.slots, required this.loading, required this.error, required this.onDate, required this.onRetry}); final AppStrings strings; final DateTime? date; final List slots; final bool loading; final String? error; final ValueChanged<DateTime?> onDate; final VoidCallback onRetry;
  @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [SectionHeader(title: strings.doctorAvailabilityTitle, trailing: OutlinedButton.icon(onPressed: () async { final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)), initialDate: date ?? DateTime.now()); onDate(picked); }, icon: const Icon(Icons.calendar_today_outlined), label: Text(date == null ? strings.doctorChooseDateAction : date!.toLocal().toString().split(' ').first))), if (loading) const Center(child: CircularProgressIndicator()) else if (error != null) ErrorRetryState(title: strings.doctorAvailabilityLoadError, message: error!, retryLabel: strings.retry, onRetry: onRetry, variant: ErrorRetryVariant.compact) else if (date == null) Text(strings.doctorAvailabilityChooseDateHint) else if (slots.isEmpty) Text(strings.doctorAvailabilityNoneForDate) else Wrap(spacing: AppTheme.spaceSm, runSpacing: AppTheme.spaceSm, children: slots.map((slot) => Chip(label: Directionality(textDirection: TextDirection.ltr, child: Text([slot.startTime, slot.endTime].whereType<String>().join('–'))))).toList())]))); }
class _LoadingDetail extends StatelessWidget { const _LoadingDetail({required this.strings}); final AppStrings strings; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Row(children: [const SizedBox.square(dimension: AppTheme.iconLg, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: AppTheme.spaceMd), Expanded(child: Text(strings.doctorLoadingDetails))]))); }

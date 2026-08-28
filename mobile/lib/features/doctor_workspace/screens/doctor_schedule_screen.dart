import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/locale/locale_controller.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../routes/route_paths.dart';
import '../../../../shared/widgets/app_scaffold.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_retry_state.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../../../../shared/widgets/role_header_actions.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/doctor_schedule_models.dart';
import '../providers/doctor_schedule_provider.dart';

class DoctorScheduleScreen extends ConsumerStatefulWidget {
  const DoctorScheduleScreen({super.key});

  @override
  ConsumerState<DoctorScheduleScreen> createState() => _DoctorScheduleScreenState();
}

class _DoctorScheduleScreenState extends ConsumerState<DoctorScheduleScreen> {
  String _filter = 'upcoming';
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';
    final isDoctor = ref.watch(authControllerProvider).user?.role == 'doctor';
    if (!isDoctor) {
      return AppScaffold(
        appBar: AppBar(),
        body: const Center(child: EmptyState(icon: Icons.lock_outline, title: 'Doctor access required', hint: 'This workspace is available to approved doctor accounts only.')),
      );
    }
    final schedule = ref.watch(doctorScheduleProvider);
    return AppScaffold(
      appBar: AppBar(
        title: Text(ar ? 'جدولي المهني' : 'My schedule'),
        leading: IconButton(
          tooltip: ar ? 'الرئيسية' : 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: () => context.go(RoutePaths.home),
        ),
        actions: const [RoleHeaderActions(compact: true)],
      ),
      body: schedule.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetryState(
          title: ar ? 'تعذر تحميل الجدول' : 'Could not load schedule',
          message: ar ? 'تحقق من الاتصال ثم حاول مرة أخرى.' : 'Check your connection and try again.',
          retryLabel: ar ? 'إعادة المحاولة' : 'Retry',
          onRetry: () => ref.invalidate(doctorScheduleProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(doctorScheduleProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            children: [
              PageIntro(
                title: ar ? 'جدولي المهني' : 'My schedule',
                subtitle: data.isAcceptingPatients
                    ? (ar ? 'حسابك يستقبل حجوزات جديدة.' : 'Your account is accepting new bookings.')
                    : (ar ? 'حسابك لا يستقبل حجوزات جديدة حالياً.' : 'Your account is not accepting new bookings right now.'),
                icon: Icons.calendar_month_outlined,
                color: data.isAcceptingPatients ? AppTheme.success : AppTheme.warning,
              ),
              const SizedBox(height: AppTheme.spaceLg),
              _AvailabilitySummary(data: data, ar: ar),
              const SizedBox(height: AppTheme.spaceXl),
              Text(ar ? 'المواعيد' : 'Appointments', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppTheme.spaceSm),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'today', label: Text(ar ? 'اليوم' : 'Today'), icon: const Icon(Icons.today_outlined)),
                  ButtonSegment(value: 'upcoming', label: Text(ar ? 'القادمة' : 'Upcoming'), icon: const Icon(Icons.event_available_outlined)),
                  ButtonSegment(value: 'past', label: Text(ar ? 'السابقة' : 'Past'), icon: const Icon(Icons.history_outlined)),
                ],
                selected: {_filter},
                onSelectionChanged: (value) => setState(() => _filter = value.first),
              ),
              const SizedBox(height: AppTheme.spaceMd),
              if (_filtered(data.appointments).isEmpty)
                EmptyState(
                  icon: Icons.event_busy_outlined,
                  title: ar ? 'لا توجد مواعيد هنا' : 'No appointments here',
                  hint: ar ? 'ستظهر المواعيد المرتبطة بحسابك في هذا القسم.' : 'Appointments linked to your account will appear here.',
                )
              else
                for (final appointment in _filtered(data.appointments))
                  _AppointmentCard(
                    appointment: appointment,
                    ar: ar,
                    busy: _busyId == appointment.id,
                    onConfirm: appointment.status == 'scheduled' ? () => _update(appointment, 'confirm', ar) : null,
                    onComplete: {'confirmed', 'in_progress'}.contains(appointment.status) ? () => _update(appointment, 'complete', ar) : null,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  List<DoctorScheduleAppointment> _filtered(List<DoctorScheduleAppointment> appointments) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return appointments.where((appointment) {
      final finished = {'completed', 'cancelled', 'no_show'}.contains(appointment.status);
      if (_filter == 'today') return appointment.scheduledDate == today && !finished;
      if (_filter == 'past') return appointment.scheduledDate.compareTo(today) < 0 || finished;
      return appointment.scheduledDate.compareTo(today) > 0 || (appointment.scheduledDate == today && !finished);
    }).toList();
  }

  Future<void> _update(DoctorScheduleAppointment appointment, String action, bool ar) async {
    setState(() => _busyId = appointment.id);
    try {
      final api = ref.read(doctorScheduleApiProvider);
      if (action == 'confirm') {
        await api.confirm(appointment.id);
      } else {
        await api.complete(appointment.id);
      }
      ref.invalidate(doctorScheduleProvider);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(action == 'confirm' ? (ar ? 'تم تأكيد الموعد' : 'Appointment confirmed') : (ar ? 'تم إكمال الموعد' : 'Appointment completed'))));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ar ? 'تعذر تحديث الموعد. حاول مرة أخرى.' : 'Could not update the appointment. Please try again.')));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }
}

class _AvailabilitySummary extends StatelessWidget {
  const _AvailabilitySummary({required this.data, required this.ar});
  final DoctorSchedule data;
  final bool ar;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMd),
          child: Row(
            children: [
              Icon(data.isAcceptingPatients ? Icons.check_circle_outline : Icons.pause_circle_outline, color: data.isAcceptingPatients ? AppTheme.success : AppTheme.warning),
              const SizedBox(width: AppTheme.spaceMd),
              Expanded(child: Text(ar ? 'التوفر الأسبوعي: ${data.weeklyAvailability.where((slot) => slot.isActive).length} فترة' : 'Weekly availability: ${data.weeklyAvailability.where((slot) => slot.isActive).length} slots')),
              StatusBadge(label: data.isAcceptingPatients ? (ar ? 'متاح للحجز' : 'Open for booking') : (ar ? 'الحجز متوقف' : 'Bookings paused'), color: data.isAcceptingPatients ? AppTheme.success : AppTheme.warning),
            ],
          ),
        ),
      );
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.appointment, required this.ar, required this.busy, this.onConfirm, this.onComplete});
  final DoctorScheduleAppointment appointment;
  final bool ar;
  final bool busy;
  final VoidCallback? onConfirm;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final name = appointment.patientName(ar).isEmpty ? (ar ? 'مريض' : 'Patient') : appointment.patientName(ar);
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spaceSm),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const CircleAvatar(child: Icon(Icons.person_outline)),
            const SizedBox(width: AppTheme.spaceMd),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: Theme.of(context).textTheme.titleMedium), Text('${appointment.scheduledDate} · ${_time(appointment.startTime)}–${_time(appointment.endTime)}')])) ,
            StatusBadge(label: _status(ar, appointment.status), color: _statusColor(appointment.status)),
          ]),
          const SizedBox(height: AppTheme.spaceSm),
          Text('${appointment.type == 'telemedicine' ? (ar ? 'استشارة عن بُعد' : 'Telemedicine') : (ar ? 'زيارة للعيادة' : 'In-person')} · ${appointment.number}'),
          if (onConfirm != null || onComplete != null) ...[
            const SizedBox(height: AppTheme.spaceMd),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (busy) const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)) else ...[
                if (onConfirm != null) OutlinedButton.icon(onPressed: onConfirm, icon: const Icon(Icons.check_circle_outline), label: Text(ar ? 'تأكيد' : 'Confirm')),
                if (onComplete != null) FilledButton.icon(onPressed: onComplete, icon: const Icon(Icons.task_alt_outlined), label: Text(ar ? 'إكمال' : 'Complete')),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  static String _time(String value) => value.length >= 5 ? value.substring(0, 5) : value;
  static String _status(bool ar, String value) => switch (value) { 'scheduled' => ar ? 'مجدول' : 'Scheduled', 'confirmed' => ar ? 'مؤكد' : 'Confirmed', 'in_progress' => ar ? 'قيد التنفيذ' : 'In progress', 'completed' => ar ? 'مكتمل' : 'Completed', 'cancelled' => ar ? 'ملغى' : 'Cancelled', _ => value };
  static Color _statusColor(String value) => switch (value) { 'completed' => AppTheme.success, 'cancelled' => AppTheme.danger, 'confirmed' => AppTheme.primary, 'in_progress' => AppTheme.violet, _ => AppTheme.warning };
}

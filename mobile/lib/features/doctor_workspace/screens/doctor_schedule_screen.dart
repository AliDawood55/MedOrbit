import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/doctor_models.dart';
import '../providers/doctor_workspace_providers.dart';
import '../widgets/doctor_workspace_gate.dart';

class DoctorScheduleScreen extends ConsumerWidget {
  const DoctorScheduleScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStringsProvider),
        async = ref.watch(doctorScheduleProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(s.schedule)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAvailability(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text(s.addAvailability),
      ),
      body: DoctorWorkspaceGate(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorRetryState(
            title: s.schedule,
            message: doctorErrorMessage(s, e),
            retryLabel: s.retry,
            onRetry: () => ref.read(doctorScheduleProvider.notifier).load(),
          ),
          data: (schedule) => RefreshIndicator(
            onRefresh: () => ref.read(doctorScheduleProvider.notifier).load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: AppTheme.spaceLg, bottom: 96),
              children: [
                ResponsiveContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PageIntro(
                        title: s.schedule,
                        subtitle: s.bookingDaysValue(
                          schedule.bookingHorizonDays,
                        ),
                        icon: Icons.calendar_month_outlined,
                      ),
                      const SizedBox(height: AppTheme.spaceLg),
                      SectionHeader(title: s.weeklyAvailability),
                      if (schedule.weekly.isEmpty)
                        EmptyState(
                          icon: Icons.event_busy_outlined,
                          title: s.noAvailability,
                        )
                      else
                        ...schedule.weekly.map(
                          (r) => _ruleCard(context, ref, s, schedule, r),
                        ),
                      const SizedBox(height: AppTheme.spaceXl),
                      SectionHeader(title: s.dateOverrides),
                      if (schedule.overrides.isEmpty)
                        EmptyState(
                          icon: Icons.event_note_outlined,
                          title: s.noAvailability,
                        )
                      else
                        ...schedule.overrides.map(
                          (r) => _ruleCard(context, ref, s, schedule, r),
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

  Widget _ruleCard(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    DoctorSchedule schedule,
    DoctorAvailability rule,
  ) {
    final days = s.isArabic
        ? const [
            'الأحد',
            'الاثنين',
            'الثلاثاء',
            'الأربعاء',
            'الخميس',
            'الجمعة',
            'السبت',
          ]
        : const [
            'Sunday',
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
          ];
    DoctorClinic? clinic;
    for (final candidate in schedule.clinics) {
      if (candidate.id == rule.clinicId) {
        clinic = candidate;
        break;
      }
    }
    final title =
        rule.specificDate ??
        (rule.dayOfWeek != null && rule.dayOfWeek! >= 0 && rule.dayOfWeek! < 7
            ? days[rule.dayOfWeek!]
            : '—');
    final detail = rule.type == 'day_off'
        ? s.dayOff
        : '${rule.startTime.substring(0, 5)} – ${rule.endTime.substring(0, 5)} · ${rule.isTelemedicine ? s.telemedicine : (s.isArabic ? clinic?.nameAr : clinic?.nameEn) ?? s.inPerson}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(detail),
                  Text(
                    rule.isActive
                        ? (rule.type == 'blocked' ? s.blocked : s.available)
                        : s.doctorStatus('hidden'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: s.moreActionsTooltip,
              onSelected: (value) async {
                if (value == 'edit') {
                  await _openAvailability(
                    context,
                    ref,
                    rule,
                    schedule: schedule,
                  );
                } else {
                  final confirmed = await confirmDoctorAction(
                    context,
                    title: s.delete,
                    body: s.deleteConfirmation,
                    strings: s,
                  );
                  if (!confirmed || !context.mounted) return;
                  final result = await ref
                      .read(doctorScheduleProvider.notifier)
                      .deleteAvailability(rule.id);
                  if (context.mounted && result.error != null) {
                    showDoctorError(context, s, result.error);
                  }
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'edit', child: Text(s.edit)),
                PopupMenuItem(value: 'delete', child: Text(s.delete)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAvailability(
    BuildContext context,
    WidgetRef ref,
    DoctorAvailability? existing, {
    DoctorSchedule? schedule,
  }) async {
    final s = ref.read(appStringsProvider);
    final snapshot = schedule ?? ref.read(doctorScheduleProvider).valueOrNull;
    if (snapshot == null) return;
    var type = existing?.type ?? 'available',
        day = existing?.dayOfWeek ?? 0,
        dateSpecific =
            existing?.specificDate != null || existing?.type != 'available',
        telemedicine = existing?.isTelemedicine ?? snapshot.clinics.isEmpty,
        duration = existing?.slotDuration ?? 30,
        active = existing?.isActive ?? true,
        clinicId =
            existing?.clinicId ??
            (snapshot.clinics.isEmpty ? null : snapshot.clinics.first.id);
    DateTime date =
        DateTime.tryParse(existing?.specificDate ?? '') ?? DateTime.now();
    TimeOfDay start =
            _time(existing?.startTime) ?? const TimeOfDay(hour: 9, minute: 0),
        end = _time(existing?.endTime) ?? const TimeOfDay(hour: 13, minute: 0);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(
                Duration(days: snapshot.bookingHorizonDays),
              ),
            );
            if (picked != null) setLocal(() => date = picked);
          }

          Future<void> pickTime(bool isStart) async {
            final picked = await showTimePicker(
              context: context,
              initialTime: isStart ? start : end,
            );
            if (picked != null) {
              setLocal(() => isStart ? start = picked : end = picked);
            }
          }

          final requiresDate = type != 'available' || dateSpecific;
          return AlertDialog(
            scrollable: true,
            title: Text(existing == null ? s.addAvailability : s.edit),
            content: SizedBox(
              width: 480,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: InputDecoration(labelText: s.availabilityType),
                    items:
                        [
                              ('available', s.available),
                              ('blocked', s.blocked),
                              ('day_off', s.dayOff),
                            ]
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.$1,
                                child: Text(e.$2),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => setLocal(() => type = v ?? 'available'),
                  ),
                  if (type == 'available')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.specificDate),
                      value: dateSpecific,
                      onChanged: (v) => setLocal(() => dateSpecific = v),
                    ),
                  if (requiresDate)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.specificDate),
                      subtitle: Text(
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: pickDate,
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: day,
                      decoration: InputDecoration(labelText: s.weekday),
                      items: List.generate(
                        7,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text(
                            (s.isArabic
                                ? const [
                                    'الأحد',
                                    'الاثنين',
                                    'الثلاثاء',
                                    'الأربعاء',
                                    'الخميس',
                                    'الجمعة',
                                    'السبت',
                                  ]
                                : const [
                                    'Sunday',
                                    'Monday',
                                    'Tuesday',
                                    'Wednesday',
                                    'Thursday',
                                    'Friday',
                                    'Saturday',
                                  ])[i],
                          ),
                        ),
                      ),
                      onChanged: (v) => setLocal(() => day = v ?? 0),
                    ),
                  if (type != 'day_off')
                    Row(
                      children: [
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.startTime),
                            subtitle: Text(start.format(context)),
                            onTap: () => pickTime(true),
                          ),
                        ),
                        Expanded(
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(s.endTime),
                            subtitle: Text(end.format(context)),
                            onTap: () => pickTime(false),
                          ),
                        ),
                      ],
                    ),
                  if (type == 'available') ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.telemedicine),
                      value: telemedicine,
                      onChanged: (v) => setLocal(() => telemedicine = v),
                    ),
                    if (!telemedicine)
                      DropdownButtonFormField<String>(
                        initialValue: clinicId,
                        decoration: InputDecoration(labelText: s.clinic),
                        items: snapshot.clinics
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(
                                  (s.isArabic ? c.nameAr : c.nameEn) ?? '—',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocal(() => clinicId = v),
                      ),
                    DropdownButtonFormField<int>(
                      initialValue: duration,
                      decoration: InputDecoration(labelText: s.slotDuration),
                      items: const [15, 20, 30, 45, 60]
                          .map(
                            (v) =>
                                DropdownMenuItem(value: v, child: Text('$v')),
                          )
                          .toList(),
                      onChanged: (v) => setLocal(() => duration = v ?? 30),
                    ),
                  ],
                  if (existing != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.available),
                      value: active,
                      onChanged: (v) => setLocal(() => active = v),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.cancel),
              ),
              FilledButton(
                onPressed: () {
                  if (type == 'available' &&
                      !telemedicine &&
                      clinicId == null) {
                    showDoctorError(
                      context,
                      s,
                      const ApiException(message: '', code: 'CLINIC_REQUIRED'),
                    );
                    return;
                  }
                  final payload = <String, dynamic>{
                    'availability_type': type,
                    if (requiresDate)
                      'specific_date':
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
                    else
                      'day_of_week': day,
                    if (type != 'day_off')
                      'start_time':
                          '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                    if (type != 'day_off')
                      'end_time':
                          '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                    if (type == 'available')
                      'clinic_id': telemedicine ? null : clinicId,
                    if (type == 'available') 'slot_duration': duration,
                    if (type == 'available') 'is_telemedicine': telemedicine,
                    if (existing != null) 'is_active': active,
                  };
                  Navigator.pop(context, payload);
                },
                child: Text(s.save),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    final saved = await ref
        .read(doctorScheduleProvider.notifier)
        .saveAvailability(id: existing?.id, payload: result);
    if (context.mounted && saved.error != null) {
      showDoctorError(context, s, saved.error);
    }
  }

  TimeOfDay? _time(String? value) {
    if (value == null) return null;
    final p = value.split(':');
    if (p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return h == null || m == null ? null : TimeOfDay(hour: h, minute: m);
  }
}

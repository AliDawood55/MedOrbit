import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/enriched_appointment.dart';

(String, Color) appointmentStatusVisual(
  String status,
  AppStrings strings,
) {
  switch (status) {
    case 'scheduled':
      return (strings.statusScheduled, AppTheme.warning);
    case 'confirmed':
      return (strings.statusConfirmed, AppTheme.primary);
    case 'in_progress':
      return (strings.statusInProgress, AppTheme.info);
    case 'completed':
      return (strings.statusAppointmentCompleted, AppTheme.success);
    case 'no_show':
      return (strings.statusNoShow, AppTheme.danger);
    case 'cancelled':
      return (strings.statusAppointmentCancelled, AppTheme.danger);
    default:
      return (status, ThemeData.fallback().colorScheme.onSurfaceVariant);
  }
}

class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.entry,
    required this.strings,
    required this.isArabic,
    this.onCancel,
    this.isCancelling = false,
    this.cancelEnabled = true,
  });

  final EnrichedAppointment entry;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback? onCancel;
  final bool isCancelling;
  final bool cancelEnabled;

  @override
  Widget build(BuildContext context) {
    final appointment = entry.appointment;
    final doctorName = entry.doctorName(isArabic);
    final clinicName = entry.clinicName(isArabic);
    final (statusLabel, statusColor) =
        appointmentStatusVisual(appointment.status, strings);
    final dateLabel = formatDate(
      parseDateOnly(appointment.scheduledDate),
      localeCode: isArabic ? 'ar' : 'en',
    );
    final timeLabel =
        '${formatTime(appointment.startTime)}–${formatTime(appointment.endTime)}';
    final isTelemedicine = appointment.appointmentType == 'telemedicine';
    final typeLabel = isTelemedicine
        ? strings.appointmentTypeTelemedicine
        : strings.appointmentTypeInPerson;
    final reason = appointment.reasonForVisit?.trim();
    final semanticLabel = [
      strings.appointmentNumberValue(appointment.appointmentNumber),
      ?doctorName,
      statusLabel,
      dateLabel,
      timeLabel,
      typeLabel,
    ].join('. ');

    return Semantics(
      container: true,
      label: semanticLabel,
      child: Card(
        elevation: AppTheme.elevation1,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largeText = AppTheme.usesLargeText(context);
              final compact =
                  constraints.maxWidth < AppTheme.compactBreakpoint ||
                      largeText;
              final avatar = _DoctorAvatar(
                doctorName: doctorName,
                isTelemedicine: isTelemedicine,
              );
              final content = _AppointmentCardContent(
                appointmentNumber: appointment.appointmentNumber,
                doctorName: doctorName,
                clinicName: clinicName,
                dateLabel: dateLabel,
                timeLabel: timeLabel,
                typeLabel: typeLabel,
                typeIcon: isTelemedicine
                    ? Icons.chat_bubble_outline
                    : Icons.local_hospital_outlined,
                statusLabel: statusLabel,
                statusColor: statusColor,
                reason: reason,
                strings: strings,
                compact: compact,
                availableWidth: compact
                    ? constraints.maxWidth
                    : constraints.maxWidth -
                        52 -
                        AppTheme.spaceLg,
                onCancel: onCancel,
                isCancelling: isCancelling,
                cancelEnabled: cancelEnabled,
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    avatar,
                    const SizedBox(height: AppTheme.spaceMd),
                    content,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  avatar,
                  const SizedBox(width: AppTheme.spaceLg),
                  Expanded(child: content),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DoctorAvatar extends StatelessWidget {
  const _DoctorAvatar({
    required this.doctorName,
    required this.isTelemedicine,
  });

  final String? doctorName;
  final bool isTelemedicine;

  @override
  Widget build(BuildContext context) {
    final hasName = doctorName != null && doctorName!.trim().isNotEmpty;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        boxShadow: AppTheme.shadowSmOf(context),
      ),
      alignment: Alignment.center,
      child: hasName
          ? Text(
              doctorName!.trim().substring(0, 1).toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: AppTheme.weightExtraBold,
                  ),
            )
          : Icon(
              isTelemedicine
                  ? Icons.chat_bubble_outline
                  : Icons.medical_information_outlined,
              color: Colors.white,
              size: AppTheme.iconLg,
            ),
    );
  }
}

class _AppointmentCardContent extends StatelessWidget {
  const _AppointmentCardContent({
    required this.appointmentNumber,
    required this.doctorName,
    required this.clinicName,
    required this.dateLabel,
    required this.timeLabel,
    required this.typeLabel,
    required this.typeIcon,
    required this.statusLabel,
    required this.statusColor,
    required this.reason,
    required this.strings,
    required this.compact,
    required this.availableWidth,
    required this.onCancel,
    required this.isCancelling,
    required this.cancelEnabled,
  });

  final String appointmentNumber;
  final String? doctorName;
  final String? clinicName;
  final String dateLabel;
  final String timeLabel;
  final String typeLabel;
  final IconData typeIcon;
  final String statusLabel;
  final Color statusColor;
  final String? reason;
  final AppStrings strings;
  final bool compact;
  final double availableWidth;
  final VoidCallback? onCancel;
  final bool isCancelling;
  final bool cancelEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metadataWidth = compact
        ? availableWidth
        : (availableWidth - AppTheme.spaceMd) / 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppTheme.spaceSm,
          runSpacing: AppTheme.spaceSm,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                appointmentNumber,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: AppTheme.weightExtraBold,
                ),
              ),
            ),
            StatusBadge(label: statusLabel, color: statusColor),
          ],
        ),
        const SizedBox(height: AppTheme.spaceSm),
        Text(
          doctorName ?? strings.doctorNameUnavailable,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: AppTheme.weightBold,
          ),
        ),
        const SizedBox(height: AppTheme.spaceMd),
        Wrap(
          spacing: AppTheme.spaceMd,
          runSpacing: AppTheme.spaceSm,
          children: [
            if (clinicName != null)
              _MetadataItem(
                width: metadataWidth,
                icon: Icons.location_on_outlined,
                label: clinicName!,
              ),
            _MetadataItem(
              width: metadataWidth,
              icon: Icons.calendar_today_outlined,
              label: dateLabel,
            ),
            _MetadataItem(
              width: metadataWidth,
              icon: Icons.schedule_outlined,
              label: timeLabel,
              textDirection: TextDirection.ltr,
            ),
            _MetadataItem(
              width: metadataWidth,
              icon: typeIcon,
              label: typeLabel,
            ),
          ],
        ),
        if (reason != null && reason!.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spaceMd),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spaceMd),
            decoration: BoxDecoration(
              color: AppTheme.mutedSurfaceOf(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.visitReasonLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTheme.spaceXs),
                Text(
                  reason!,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
        if (onCancel != null) ...[
          const SizedBox(height: AppTheme.spaceMd),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Semantics(
              button: true,
              enabled: cancelEnabled && !isCancelling,
              label: strings.cancelAppointmentAction,
              child: OutlinedButton.icon(
                onPressed:
                    cancelEnabled && !isCancelling ? onCancel : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                ),
                icon: isCancelling
                    ? const SizedBox.square(
                        dimension: AppTheme.iconSm,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.danger,
                        ),
                      )
                    : const Icon(
                        Icons.close_rounded,
                        size: AppTheme.iconSm,
                      ),
                label: Text(
                  isCancelling
                      ? strings.cancellingAppointment
                      : strings.cancelAppointmentAction,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({
    required this.width,
    required this.icon,
    required this.label,
    this.textDirection,
  });

  final double width;
  final IconData icon;
  final String label;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppTheme.iconSm, color: AppTheme.primary),
          const SizedBox(width: AppTheme.spaceXs),
          Expanded(
            child: Directionality(
              textDirection:
                  textDirection ?? Directionality.of(context),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: color,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../discovery/models/doctor_models.dart';
import '../../discovery/widgets/doctor_result_card.dart';
import '../models/availability_slot_model.dart';

/// Read-only recap shown on the confirm step — doctor, clinic, date, time,
/// and appointment type. Mirrors the web wizard's `renderSummary`.
class BookingSummaryCard extends StatelessWidget {
  const BookingSummaryCard({
    super.key,
    required this.doctor,
    required this.clinic,
    required this.date,
    required this.slot,
    required this.strings,
  });

  final Doctor doctor;
  final DoctorClinicSummary clinic;
  final DateTime date;
  final GeneratedSlot slot;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final localeCode = strings.isArabic ? 'ar' : 'en';
    final typeLabel = slot.isTelemedicine
        ? strings.appointmentTypeTelemedicine
        : strings.appointmentTypeInPerson;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryRow(
              label: strings.doctorLabel,
              value: doctorDisplayName(doctor, direction),
            ),
            _SummaryRow(
              label: strings.clinicLabel,
              value: clinicDisplayName(clinic, direction),
            ),
            _SummaryRow(
              label: strings.dateLabel,
              value: formatDate(date, localeCode: localeCode),
            ),
            _SummaryRow(
              label: strings.timeLabel,
              value: '${slot.startDisplay} – ${slot.endDisplay}',
              ltr: true,
            ),
            _SummaryRow(
              label: strings.appointmentTypeLabel,
              value: typeLabel,
              showDivider: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.ltr = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool ltr;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelText = Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final valueText = DefaultTextStyle.merge(
      style: const TextStyle(fontWeight: AppTheme.weightExtraBold),
      child: ltr
          ? Directionality(textDirection: TextDirection.ltr, child: Text(value))
          : Text(value),
    );

    return Semantics(
      label: '$label. $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSm),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact =
                    constraints.maxWidth < AppTheme.compactBreakpoint ||
                    AppTheme.usesLargeText(context);
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      labelText,
                      const SizedBox(height: AppTheme.spaceXs),
                      valueText,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: labelText),
                    const SizedBox(width: AppTheme.spaceMd),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: valueText,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (showDivider) const Divider(height: 1),
        ],
      ),
    );
  }
}

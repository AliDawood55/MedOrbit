import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../discovery/models/doctor_models.dart';
import '../../discovery/widgets/doctor_result_card.dart' show clinicDisplayName;

/// Only rendered by the caller when a doctor has more than one clinic — a
/// single clinic is auto-selected and never shown as a choice, matching
/// `setupClinicSelect()` in the web wizard.
class BookingClinicSelector extends StatelessWidget {
  const BookingClinicSelector({super.key, required this.clinics, required this.selected, required this.onSelect});

  final List<DoctorClinicSummary> clinics;
  final DoctorClinicSummary? selected;
  final ValueChanged<DoctorClinicSummary> onSelect;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    return Wrap(
      spacing: AppTheme.spaceSm,
      runSpacing: AppTheme.spaceSm,
      children: [
        for (final clinic in clinics)
          ChoiceChip(
            key: ValueKey('booking-clinic-${clinic.id}'),
            label: Text(clinicDisplayName(clinic, direction)),
            selected: selected?.id == clinic.id,
            onSelected: (_) => onSelect(clinic),
          ),
      ],
    );
  }
}

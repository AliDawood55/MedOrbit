import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../discovery/models/doctor_models.dart';
import '../models/availability_slot_model.dart';
import 'booking_clinic_selector.dart';
import 'booking_date_strip.dart';
import 'booking_slot_grid.dart';
import 'slot_busy_state.dart';

class BookingSlotStep extends StatelessWidget {
  const BookingSlotStep({
    super.key,
    required this.strings,
    required this.isArabic,
    required this.clinics,
    required this.selectedClinic,
    required this.selectedDate,
    required this.slots,
    required this.selectedSlot,
    required this.isLoadingSlots,
    required this.slotsFailed,
    required this.showSlotBusy,
    required this.onSelectClinic,
    required this.onSelectDate,
    required this.onSelectSlot,
    required this.onRetry,
  });

  final AppStrings strings;
  final bool isArabic;
  final List<DoctorClinicSummary> clinics;
  final DoctorClinicSummary? selectedClinic;
  final DateTime? selectedDate;
  final List<GeneratedSlot> slots;
  final GeneratedSlot? selectedSlot;
  final bool isLoadingSlots;
  final bool slotsFailed;
  final bool showSlotBusy;
  final ValueChanged<DoctorClinicSummary> onSelectClinic;
  final ValueChanged<DateTime> onSelectDate;
  final ValueChanged<GeneratedSlot> onSelectSlot;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (clinics.isEmpty) {
      return EmptyState(
        icon: Icons.local_hospital_outlined,
        title: strings.noClinicsTitle,
        hint: strings.noClinicsHint,
        variant: EmptyStateVariant.compact,
      );
    }

    final labelStyle = Theme.of(context).textTheme.labelLarge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSlotBusy) ...[
          SlotBusyState(strings: strings),
          const SizedBox(height: AppTheme.spaceMd),
        ],
        if (clinics.length > 1) ...[
          Text(strings.chooseClinicLabel, style: labelStyle),
          const SizedBox(height: AppTheme.spaceSm),
          BookingClinicSelector(
            clinics: clinics,
            selected: selectedClinic,
            onSelect: onSelectClinic,
          ),
          const SizedBox(height: AppTheme.spaceLg),
        ],
        Text(strings.chooseDateLabel, style: labelStyle),
        const SizedBox(height: AppTheme.spaceSm),
        BookingDateStrip(
          selected: selectedDate,
          onSelect: onSelectDate,
          isArabic: isArabic,
        ),
        const SizedBox(height: AppTheme.spaceLg),
        Text(strings.availableSlotsLabel, style: labelStyle),
        const SizedBox(height: AppTheme.spaceSm),
        if (isLoadingSlots)
          Semantics(
            liveRegion: true,
            label: strings.loading,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: AppTheme.spaceXl),
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (slotsFailed)
          ErrorRetryState(
            title: strings.couldNotLoadSlots,
            message: strings.errorGeneric,
            retryLabel: strings.retry,
            onRetry: onRetry,
            variant: ErrorRetryVariant.compact,
          )
        else if (slots.isEmpty)
          EmptyState(
            icon: Icons.event_busy_outlined,
            title: strings.noSlotsTitle,
            hint: strings.noSlotsHint,
            variant: EmptyStateVariant.compact,
          )
        else ...[
          BookingSlotGrid(
            slots: slots,
            selected: selectedSlot,
            strings: strings,
            onSelect: onSelectSlot,
          ),
          const SizedBox(height: AppTheme.spaceMd),
          InlineMessage(
            message: strings.slotHonestyNote,
            tone: InlineMessageTone.info,
          ),
        ],
      ],
    );
  }
}

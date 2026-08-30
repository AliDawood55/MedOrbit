import 'package:flutter/material.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../models/availability_slot_model.dart';

/// Wraps generated slots as tappable tiles, each clearly labeled in-person or
/// telemedicine — required so the patient always knows what they're booking
/// before `appointment_type` is derived from their pick.
class BookingSlotGrid extends StatelessWidget {
  const BookingSlotGrid({
    super.key,
    required this.slots,
    required this.selected,
    required this.strings,
    required this.onSelect,
  });

  final List<GeneratedSlot> slots;
  final GeneratedSlot? selected;
  final AppStrings strings;
  final ValueChanged<GeneratedSlot> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = AppTheme.usesLargeText(context);
        final columns = largeText || constraints.maxWidth < 360
            ? 1
            : constraints.maxWidth >= 600
            ? 3
            : 2;
        final width =
            (constraints.maxWidth - AppTheme.spaceSm * (columns - 1)) / columns;
        return Wrap(
          spacing: AppTheme.spaceSm,
          runSpacing: AppTheme.spaceSm,
          children: [
            for (final slot in slots)
              SizedBox(
                width: width,
                child: _SlotButton(
                  key: ValueKey('booking-slot-${slot.id}'),
                  slot: slot,
                  isSelected: selected?.id == slot.id,
                  typeLabel: slot.isTelemedicine
                      ? strings.appointmentTypeTelemedicine
                      : strings.appointmentTypeInPerson,
                  scheme: scheme,
                  onTap: () => onSelect(slot),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SlotButton extends StatelessWidget {
  const _SlotButton({
    super.key,
    required this.slot,
    required this.isSelected,
    required this.typeLabel,
    required this.scheme,
    required this.onTap,
  });

  final GeneratedSlot slot;
  final bool isSelected;
  final String typeLabel;
  final ColorScheme scheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? Colors.white : scheme.onSurface;
    return Semantics(
      button: true,
      selected: isSelected,
      excludeSemantics: true,
      label: '${slot.startDisplay} – ${slot.endDisplay}. $typeLabel',
      child: Material(
        color: isSelected ? AppTheme.primary : scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceMd,
              vertical: AppTheme.spaceSm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: isSelected ? AppTheme.primary : scheme.outlineVariant,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    slot.startDisplay,
                    style: TextStyle(
                      color: foreground,
                      fontWeight: AppTheme.weightExtraBold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected) ...[
                      Icon(
                        Icons.check_circle_rounded,
                        size: AppTheme.iconSm,
                        color: foreground,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Icon(
                      slot.isTelemedicine
                          ? Icons.chat_bubble_outline
                          : Icons.local_hospital_outlined,
                      size: AppTheme.iconSm,
                      color: foreground,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        typeLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: foreground, fontSize: 10.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

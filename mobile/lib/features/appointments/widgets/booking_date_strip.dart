import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';

/// Horizontally scrolling strip of the next 21 days, starting today — mirrors
/// `renderDatePills()` in the web wizard. Only future/today dates are ever
/// rendered, so there is no separate "past date" state to handle.
class BookingDateStrip extends StatelessWidget {
  const BookingDateStrip({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.isArabic,
  });

  final DateTime? selected;
  final ValueChanged<DateTime> onSelect;
  final bool isArabic;

  static const int dayCount = 21;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekdayFormat = DateFormat('EEE', isArabic ? 'ar' : 'en');
    final height = AppTheme.usesLargeText(context) ? 112.0 : 72.0;

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dayCount,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppTheme.spaceSm),
        itemBuilder: (context, index) {
          final date = today.add(Duration(days: index));
          final isActive =
              selected != null &&
              selected!.year == date.year &&
              selected!.month == date.month &&
              selected!.day == date.day;
          return _DatePill(
            key: ValueKey(
              'booking-date-${date.year}-${date.month}-${date.day}',
            ),
            weekday: weekdayFormat.format(date),
            day: date.day,
            isActive: isActive,
            onTap: () => onSelect(date),
          );
        },
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({
    super.key,
    required this.weekday,
    required this.day,
    required this.isActive,
    required this.onTap,
  });

  final String weekday;
  final int day;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = isActive ? Colors.white : scheme.onSurface;
    return Semantics(
      button: true,
      selected: isActive,
      label: '$weekday $day',
      child: Material(
        color: isActive ? AppTheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSm,
              vertical: AppTheme.spaceSm,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  weekday,
                  style: TextStyle(color: foreground, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '$day',
                  style: TextStyle(
                    color: foreground,
                    fontWeight: AppTheme.weightExtraBold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

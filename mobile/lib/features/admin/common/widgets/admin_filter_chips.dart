import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

class AdminFilterOption<T> {
  const AdminFilterOption({required this.value, required this.label, this.key});

  /// `null` is the "All" option every administration filter offers, matching
  /// the empty `<option value="">` the web pages use.
  final T? value;
  final String label;
  final Key? key;
}

/// A single-select filter row rendered as chips.
///
/// Deliberately a [Wrap] rather than a horizontally scrolling list: a long
/// Arabic label or a large text scale makes the options taller instead of
/// pushing them off-screen, so the page never scrolls sideways on a 320 px
/// phone.
class AdminFilterChips<T> extends StatelessWidget {
  const AdminFilterChips({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final String label;
  final List<AdminFilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spaceSm),
          Wrap(
            spacing: AppTheme.spaceSm,
            runSpacing: AppTheme.spaceSm,
            children: [
              for (final option in options)
                ChoiceChip(
                  key: option.key,
                  label: Text(option.label),
                  selected: selected == option.value,
                  onSelected: enabled
                      ? (isSelected) {
                          if (!isSelected) return;
                          if (selected == option.value) return;
                          onSelected(option.value);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

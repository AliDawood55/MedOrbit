import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Pill-shaped status badge — mirrors `.badge` in
/// `frontend/src/css/components.css:111-121` (rounded pill, tinted
/// background at the brand color, solid text of the same color).
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceSm,
          vertical: AppTheme.spaceXs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          softWrap: true,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: AppTheme.weightBold,
                letterSpacing: isRtl ? 0 : 0.2,
              ),
        ),
      ),
    );
  }
}

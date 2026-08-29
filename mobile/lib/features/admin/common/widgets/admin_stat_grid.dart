import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/page_sections.dart';
import '../utils/admin_formatting.dart';

class AdminStat {
  const AdminStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  /// Already-formatted display text (a count, or a rating such as `4.5`).
  final String value;
  final String label;
  final IconData icon;
  final Color color;
}

/// Responsive KPI grid: one column on a 320 px phone, two from the compact
/// breakpoint up, three once there is tablet-width room.
///
/// Values are wrapped in isolate marks so a Latin numeral inside an Arabic
/// (RTL) layout keeps its own direction and never reorders against the label.
class AdminStatGrid extends StatelessWidget {
  const AdminStatGrid({super.key, required this.stats});

  final List<AdminStat> stats;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final columns = width >= 720
            ? 3
            : width >= AppTheme.compactBreakpoint
            ? 2
            : 1;
        const gap = AppTheme.spaceMd;
        final tileWidth = (width - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final stat in stats)
              SizedBox(
                width: tileWidth,
                child: StatTile(
                  value: adminIsolate(stat.value),
                  label: stat.label,
                  icon: stat.icon,
                  color: stat.color,
                ),
              ),
          ],
        );
      },
    );
  }
}

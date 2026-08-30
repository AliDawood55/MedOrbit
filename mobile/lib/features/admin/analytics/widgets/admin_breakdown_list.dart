import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../common/utils/admin_formatting.dart';

class AdminBreakdownEntry {
  const AdminBreakdownEntry({
    required this.label,
    required this.count,
    this.color,
  });

  final String label;
  final int count;
  final Color? color;
}

/// A proportional breakdown rendered as labelled bars.
///
/// This is the mobile form of the web page's doughnut/pie charts. A pie is a
/// poor fit on a phone — the slice labels either overlap or move into a legend
/// that has to be read separately — whereas a sorted bar list reads at a
/// glance, scales with the text size, works identically in RTL, and needs no
/// charting dependency.
class AdminBreakdownList extends StatelessWidget {
  const AdminBreakdownList({
    super.key,
    required this.entries,
    required this.shareLabel,
  });

  final List<AdminBreakdownEntry> entries;

  /// Builds the accessible per-row summary, e.g. "Patients: 28 (62%)".
  final String Function(String label, int count, String percent) shareLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = entries.fold<int>(0, (sum, entry) => sum + entry.count);
    final max = entries.fold<int>(0, (m, e) => e.count > m ? e.count : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in entries) ...[
          Semantics(
            container: true,
            label: shareLabel(
              entry.label,
              entry.count,
              adminPercentText(entry.count, total),
            ),
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.label,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spaceSm),
                      Flexible(
                        child: Text(
                          // Isolated so an Arabic paragraph never reorders the
                          // digits of a count sitting at the line's end.
                          adminIsolate('${entry.count}'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: AppTheme.weightBold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spaceXs),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    child: LinearProgressIndicator(
                      value: max == 0 ? 0 : entry.count / max,
                      minHeight: 8,
                      backgroundColor: AppTheme.mutedSurfaceOf(context),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        entry.color ?? theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spaceMd),
        ],
      ],
    );
  }
}

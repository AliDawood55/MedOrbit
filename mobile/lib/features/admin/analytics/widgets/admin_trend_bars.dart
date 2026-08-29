import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// A compact time-series bar chart built from layout primitives.
///
/// The web page draws these with Chart.js. Adding a charting package to the
/// app for two twelve-point series would not earn its download size, and a
/// canvas chart is invisible to a screen reader — so each bucket is a real
/// widget with its own [Semantics] label, and the whole row flexes to the
/// available width instead of scrolling sideways.
class AdminTrendBars extends StatelessWidget {
  const AdminTrendBars({
    super.key,
    required this.values,
    required this.bucketSemanticLabel,
    this.color,
    this.height = 120,
  });

  final List<int> values;

  /// Accessible description for bucket [index], e.g. "Week of Mar 3: 12".
  final String Function(int index, int value) bucketSemanticLabel;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    final max = values.fold<int>(0, (m, value) => value > m ? value : m);
    final track = AppTheme.mutedSurfaceOf(context);

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < values.length; index++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.space2xs,
                ),
                child: Semantics(
                  // Its own node: without a container each bar's label would
                  // merge into one unreadable run of numbers.
                  container: true,
                  label: bucketSemanticLabel(index, values[index]),
                  child: ExcludeSemantics(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // A full-height track keeps every bucket tappable-sized
                        // and makes an all-zero series read as "no data yet"
                        // rather than as an empty box.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: track,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusXs,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: FractionallySizedBox(
                            heightFactor: max == 0
                                ? 0
                                : (values[index] / max).clamp(0.0, 1.0),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusXs,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

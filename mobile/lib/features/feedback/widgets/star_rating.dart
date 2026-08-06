import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Accessible tap-to-set rating that preserves the existing 1–5 values.
class StarRating extends StatelessWidget {
  const StarRating({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    required this.valueSemanticLabel,
    required this.starSemanticLabelBuilder,
    this.size = AppTheme.iconXl,
    this.hasError = false,
    this.alignment = WrapAlignment.start,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String semanticLabel;
  final String valueSemanticLabel;
  final String Function(int value) starSemanticLabelBuilder;
  final double size;
  final bool hasError;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unselectedColor = hasError
        ? theme.colorScheme.error.withValues(alpha: 0.72)
        : AppTheme.strongBorderOf(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '$semanticLabel. $valueSemanticLabel',
      child: Wrap(
        alignment: alignment,
        runAlignment: alignment,
        spacing: 0,
        runSpacing: AppTheme.spaceXs,
        children: [
          for (var index = 0; index < 5; index++)
            Semantics(
              selected: index + 1 == value,
              child: IconButton(
                tooltip: starSemanticLabelBuilder(index + 1),
                onPressed: () => onChanged(index + 1),
                constraints: const BoxConstraints.tightFor(
                  width: AppTheme.minTouchTarget,
                  height: AppTheme.minTouchTarget,
                ),
                padding: const EdgeInsets.all(AppTheme.spaceXs),
                icon: Icon(
                  index < value
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: index < value ? AppTheme.accent : unselectedColor,
                  size: size,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

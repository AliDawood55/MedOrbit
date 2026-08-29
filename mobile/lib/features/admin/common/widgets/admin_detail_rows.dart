import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// One `label` / `value` pair in an administration detail view.
///
/// The label sits above the value rather than beside it. A side-by-side row
/// breaks down for long Arabic labels and at large text scales, and stacking
/// keeps every value left/start-aligned in both directions.
class AdminDetailRow extends StatelessWidget {
  const AdminDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
  });

  final String label;
  final String value;

  /// Long identifiers (licence numbers, entity ids, emails) are worth being
  /// able to select and copy.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
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
              const SizedBox(height: AppTheme.space2xs),
              selectable
                  ? SelectableText(value, style: theme.textTheme.bodyMedium)
                  : Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled card wrapping a group of [AdminDetailRow]s or any other content.
class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: AppTheme.weightBold,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppTheme.spaceSm),
                    Flexible(child: trailing!),
                  ],
                ],
              ),
              const SizedBox(height: AppTheme.spaceMd),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

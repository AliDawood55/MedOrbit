import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum EmptyStateVariant { compact, full }

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.action,
    this.variant = EmptyStateVariant.full,
  });

  final IconData icon;
  final String title;
  final String? hint;
  final Widget? action;
  final EmptyStateVariant variant;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = variant == EmptyStateVariant.compact;

    return Semantics(
      container: true,
      liveRegion: true,
      label: [title, if (hint != null) hint].join('. '),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(
            compact ? AppTheme.spaceLg : AppTheme.space2xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: compact ? 52 : 72,
                      height: compact ? 52 : 72,
                      decoration: BoxDecoration(
                        color: AppTheme.mutedSurfaceOf(context),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: compact ? AppTheme.iconLg : AppTheme.iconXl,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    SizedBox(
                      height: compact
                          ? AppTheme.spaceMd
                          : AppTheme.spaceLg,
                    ),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: AppTheme.spaceSm),
                      Text(
                        hint!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: AppTheme.spaceLg),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

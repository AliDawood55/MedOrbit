import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

enum ErrorRetryVariant { compact, full }

class ErrorRetryState extends StatelessWidget {
  const ErrorRetryState({
    super.key,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
    this.variant = ErrorRetryVariant.full,
    this.retryKey,
  });

  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;
  final ErrorRetryVariant variant;
  final Key? retryKey;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final compact = variant == ErrorRetryVariant.compact;

    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title. $message',
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
                        color: colorScheme.error.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: compact ? AppTheme.iconLg : AppTheme.iconXl,
                        color: colorScheme.error,
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
                    const SizedBox(height: AppTheme.spaceSm),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spaceLg),
              OutlinedButton.icon(
                key: retryKey,
                onPressed: onRetry,
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: AppTheme.iconMd,
                ),
                label: Text(retryLabel, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

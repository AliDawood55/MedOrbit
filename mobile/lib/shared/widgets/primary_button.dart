import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = !isLoading && onPressed != null;
    final content = isLoading
        ? const SizedBox.square(
            dimension: AppTheme.iconMd,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon!, size: AppTheme.iconMd),
                const SizedBox(width: AppTheme.spaceSm),
              ],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      liveRegion: isLoading,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppTheme.minTouchTarget),
        child: ElevatedButton(
          onPressed: enabled ? onPressed : null,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(AppTheme.minTouchTarget, AppTheme.minTouchTarget),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          ),
          child: ExcludeSemantics(child: content),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onPressed, this.isLoading = false, required this.label});

  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = !isLoading && onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      liveRegion: isLoading,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(AppTheme.minTouchTarget, AppTheme.minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const _GoogleLogo(),
              const SizedBox(width: AppTheme.spaceSm),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small inline approximation of the Google "G" mark using plain shapes —
/// avoids bundling an image asset just for one icon.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 18,
      width: 18,
      child: Icon(Icons.g_mobiledata, size: 24, color: Color(0xFF4285F4)),
    );
  }
}

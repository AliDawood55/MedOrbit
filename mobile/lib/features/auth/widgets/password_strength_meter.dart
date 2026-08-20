import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password, this.hintText});

  final String password;
  final String? hintText;

  int get _score {
    var score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return score;
  }

  Color get _color {
    final score = _score;
    if (score >= 4) return AppTheme.success;
    if (score >= 2) return AppTheme.warning;
    if (score >= 1) return AppTheme.danger;
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final score = _score;
    return Semantics(
      container: true,
      value: '$score/4',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (index) {
              final active = index < score;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsetsDirectional.only(
                    end: index == 3 ? 0 : AppTheme.spaceXs,
                  ),
                  decoration: BoxDecoration(
                    color: active ? _color.withValues(alpha: 0.9) : Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          if (hintText != null)
            Text(
              hintText!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}

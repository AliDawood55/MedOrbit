import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Shows a doctor's profile photo, or initials on a gradient tile when
/// there is no photo or the photo fails to load.
///
/// Web's `MyDoctor.__avatarFallback` swaps a broken `<img>` for initials on
/// `onerror`; `Image.network`'s `errorBuilder` reaches the same end state
/// here without ever surfacing a broken-image icon or a network error to
/// the patient.
class DoctorAvatar extends StatelessWidget {
  const DoctorAvatar({super.key, required this.name, this.imageUrl, this.size = 56});

  final String name;
  final String? imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppTheme.primaryGradient),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: AppTheme.weightExtraBold,
            ),
      ),
    );

    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}

String _initials(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
}

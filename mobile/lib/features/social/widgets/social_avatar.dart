import 'package:flutter/material.dart';

/// Resolves a backend-relative asset path against the *active* API origin,
/// matching `API.assetUrl` on the web. Mirrors the helper the messaging
/// feature uses, so a fallback host keeps images working.
String? socialAssetUrl(String origin, String? value) {
  final source = value?.trim() ?? '';
  if (source.isEmpty) return null;
  final uri = Uri.tryParse(source);
  if (uri?.hasScheme == true) return source;
  if (origin.isEmpty) return null;
  return '$origin/${source.replaceFirst(RegExp(r'^/+'), '')}';
}

/// Circular avatar with an initial fallback.
///
/// Profile names come from a `LEFT JOIN`, so an empty name is a normal
/// server response, not a bug — it degrades to a neutral placeholder rather
/// than a blank circle. Marked decorative: the author's name is already
/// announced by the card header, and repeating a single letter after it
/// only adds noise for a screen reader.
class SocialAvatar extends StatelessWidget {
  const SocialAvatar({
    super.key,
    required this.name,
    required this.imageUrl,
    this.radius = 22,
  });

  final String name;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final fallback = trimmed.isEmpty ? '?' : trimmed.characters.first;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        foregroundImage: imageUrl == null ? null : NetworkImage(imageUrl!),
        child: Text(fallback.toUpperCase()),
      ),
    );
  }
}

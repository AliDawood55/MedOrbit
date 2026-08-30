/// Text direction resolution for user-authored content, mirroring the
/// `dir="auto"` the web feed puts on post bodies.
///
/// Doctors write posts in Arabic, in English, and routinely in a mix — an
/// Arabic body quoting an English drug name, or an English body with an
/// Arabic clinic name. Rendering all of it in the *app's* direction pushes
/// leading punctuation and trailing numerals to the wrong end. The Unicode
/// rule the browser applies is: the first strong directional character in
/// the string wins; if there is none, inherit from the surrounding context.
library;

import 'package:flutter/material.dart';

bool _isStrongRtl(int rune) =>
    (rune >= 0x0590 && rune <= 0x05FF) || // Hebrew
    (rune >= 0x0600 && rune <= 0x06FF) || // Arabic
    (rune >= 0x0700 && rune <= 0x074F) || // Syriac
    (rune >= 0x0750 && rune <= 0x077F) || // Arabic Supplement
    (rune >= 0x0780 && rune <= 0x07BF) || // Thaana
    (rune >= 0x08A0 && rune <= 0x08FF) || // Arabic Extended-A
    (rune >= 0xFB1D && rune <= 0xFDFF) || // Hebrew/Arabic presentation forms
    (rune >= 0xFE70 && rune <= 0xFEFF);

bool _isStrongLtr(int rune) =>
    (rune >= 0x0041 && rune <= 0x005A) || // A-Z
    (rune >= 0x0061 && rune <= 0x007A) || // a-z
    (rune >= 0x00C0 && rune <= 0x024F) || // Latin supplement/extended
    (rune >= 0x0370 && rune <= 0x03FF) || // Greek
    (rune >= 0x0400 && rune <= 0x04FF); // Cyrillic

/// Returns the direction implied by [text], or `null` when it carries no
/// strong directional character (digits, punctuation, emoji only) and should
/// therefore inherit the ambient [Directionality].
TextDirection? autoTextDirection(String text) {
  for (final rune in text.runes) {
    if (_isStrongRtl(rune)) return TextDirection.rtl;
    if (_isStrongLtr(rune)) return TextDirection.ltr;
  }
  return null;
}

/// [Text] that lays out user-authored content in its own direction.
///
/// Alignment follows the resolved direction too, so an Arabic post stays
/// right-aligned inside an English UI and vice versa.
class AutoDirectionText extends StatelessWidget {
  const AutoDirectionText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.semanticsLabel,
  });

  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final direction = autoTextDirection(data);
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      softWrap: true,
      textDirection: direction,
      textAlign: direction == null ? null : TextAlign.start,
      semanticsLabel: semanticsLabel,
    );
  }
}

/// Picks between an Arabic/English pair of the same field (e.g.
/// `first_name_ar`/`first_name_en`), matching the fallback chain used
/// throughout the web frontend's per-page `name()` helpers: preferred
/// language first, then whichever of the two is non-empty.
String localizedField({required bool isArabic, String? ar, String? en}) {
  final preferred = isArabic ? ar : en;
  final fallback = isArabic ? en : ar;
  final trimmedPreferred = preferred?.trim() ?? '';
  if (trimmedPreferred.isNotEmpty) return trimmedPreferred;
  return fallback?.trim() ?? '';
}

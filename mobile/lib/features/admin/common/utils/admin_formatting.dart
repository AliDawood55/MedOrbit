import 'package:intl/intl.dart';

/// Date/time rendering for the administration screens.
///
/// Every call is guarded: `intl` falls back to its default locale when the
/// requested one has no symbol data loaded, and a malformed pattern must never
/// take down an operational list. The fallback is a stable, unambiguous
/// `YYYY-MM-DD` / `YYYY-MM-DD HH:mm` rendering rather than a thrown error.
String adminFormatDate(DateTime value, {required bool isArabic}) {
  final local = value.toLocal();
  try {
    return DateFormat.yMMMd(isArabic ? 'ar' : 'en').format(local);
  } catch (_) {
    return _isoDate(local);
  }
}

String adminFormatDateTime(DateTime value, {required bool isArabic}) {
  final local = value.toLocal();
  try {
    return DateFormat.yMMMd(isArabic ? 'ar' : 'en').add_jm().format(local);
  } catch (_) {
    return '${_isoDate(local)} ${_two(local.hour)}:${_two(local.minute)}';
  }
}

/// The `YYYY-MM-DD` week-start labels the analytics time series returns are
/// rendered as a short "MMM d" so twelve of them fit on a phone.
String adminFormatShortDay(String isoDate, {required bool isArabic}) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  try {
    return DateFormat.MMMd(isArabic ? 'ar' : 'en').format(parsed);
  } catch (_) {
    return '${_two(parsed.month)}-${_two(parsed.day)}';
  }
}

/// Whole-number percentage of [value] within [total], as text. Returns `0`
/// when [total] is zero so a share label never renders `NaN`.
String adminPercentText(int value, int total) {
  if (total <= 0) return '0';
  return ((value / total) * 100).round().toString();
}

/// Wraps [value] in a Unicode isolate (`U+2066 LRI` … `U+2069 PDI`).
///
/// Counts, dates, ids and email addresses are left-to-right runs that would
/// otherwise be reordered by the bidirectional algorithm when they sit inside
/// an Arabic sentence — a "12" at the end of an RTL line can render before the
/// label it belongs to. The escapes are spelled out rather than pasted so the
/// source stays readable.
String adminIsolate(String value) => '\u2066$value\u2069';

String _isoDate(DateTime value) =>
    '${value.year}-${_two(value.month)}-${_two(value.day)}';

String _two(int value) => value.toString().padLeft(2, '0');

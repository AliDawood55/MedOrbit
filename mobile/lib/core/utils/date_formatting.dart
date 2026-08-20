import 'package:intl/intl.dart';

/// Postgres `DATE` columns (no time component) can arrive shifted by a few
/// hours after round-tripping through the driver's local-midnight
/// serialization — reading the calendar date directly can land on the wrong
/// day depending on the device's timezone. Adding 12h before reading
/// year/month/day recovers the intended day regardless of offset direction.
/// Same fix the web frontend applies (`my-appointments.js`, `dashboard.js`).
DateTime parseDateOnly(String value) => DateTime.parse(value).add(const Duration(hours: 12));

String formatDate(DateTime date, {required String localeCode}) => DateFormat.yMMMd(localeCode).format(date);

/// Postgres `TIME` columns arrive as `"HH:mm:ss"` — trims to `"HH:mm"`.
String formatTime(String hhmmss) {
  final parts = hhmmss.split(':');
  if (parts.length < 2) return hhmmss;
  return '${parts[0]}:${parts[1]}';
}

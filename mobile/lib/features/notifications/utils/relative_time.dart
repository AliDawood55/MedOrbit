import '../../../core/localization/app_strings.dart';

/// `"2h ago"`-style relative time, ported from the web's
/// `formatRelativeTime` in `notifications.js`. Kept local to this feature —
/// no other screen in the app currently needs relative timestamps, so this
/// doesn't belong in the shared `core/utils/date_formatting.dart` yet.
///
/// [now] is injectable for tests; defaults to the real clock.
String formatNotificationRelativeTime(DateTime dateTime, {required AppStrings strings, DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diffMinutes = reference.difference(dateTime).inMinutes;

  if (diffMinutes < 1) return strings.notificationsJustNow;
  if (diffMinutes < 60) return strings.notificationsMinutesAgo(diffMinutes);

  final diffHours = (diffMinutes / 60).round();
  if (diffHours < 24) return strings.notificationsHoursAgo(diffHours);

  final diffDays = (diffHours / 24).round();
  return strings.notificationsDaysAgo(diffDays);
}

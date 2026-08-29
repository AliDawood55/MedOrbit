import 'package:intl/intl.dart';

String formatServerPrice({
  required int priceCents,
  required String currency,
  required bool isArabic,
}) {
  try {
    return NumberFormat.currency(
      locale: isArabic ? 'ar' : 'en',
      name: currency,
    ).format(priceCents / 100);
  } catch (_) {
    final amount = (priceCents / 100).toStringAsFixed(2);
    return '$amount $currency';
  }
}

String formatBillingDate(DateTime value, {required bool isArabic}) {
  return DateFormat.yMMMd(isArabic ? 'ar' : 'en').format(value.toLocal());
}

String formatBillingDateTime(DateTime value, {required bool isArabic}) {
  return DateFormat.yMMMd(
    isArabic ? 'ar' : 'en',
  ).add_jm().format(value.toLocal());
}

String formatRemainingDuration(Duration duration, {required bool isArabic}) {
  final totalSeconds = duration.inSeconds.clamp(0, 365 * 24 * 60 * 60);
  final days = totalSeconds ~/ Duration.secondsPerDay;
  final hours =
      (totalSeconds % Duration.secondsPerDay) ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;
  if (days > 0) {
    return isArabic ? '$days ي $hours س' : '${days}d ${hours}h';
  }
  if (hours > 0) {
    return isArabic ? '$hours س $minutes د' : '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return isArabic ? '$minutes د $seconds ث' : '${minutes}m ${seconds}s';
  }
  return isArabic ? '$seconds ث' : '${seconds}s';
}

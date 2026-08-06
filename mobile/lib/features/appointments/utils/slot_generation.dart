import '../models/availability_slot_model.dart';

/// `"YYYY-MM-DD"` in the device's local calendar, matching what the web
/// client sends (`dateKey()` in `book-appointment.js`) and what the backend's
/// `available-slots` query expects. Deliberately not `toIso8601String()`,
/// which would serialize in a way that can shift the calendar day.
String formatDateOnly(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${_pad2(date.month)}-${_pad2(date.day)}';
}

String _pad2(int value) => value.toString().padLeft(2, '0');

String _minutesToHHMM(int minutes) => '${_pad2(minutes ~/ 60)}:${_pad2(minutes % 60)}';

int? _timeToMinutes(String value) {
  final parts = value.split(':');
  if (parts.isEmpty) return null;
  final hours = int.tryParse(parts[0]);
  if (hours == null) return null;
  final minutes = parts.length > 1 ? int.tryParse(parts[1]) : 0;
  return hours * 60 + (minutes ?? 0);
}

/// Ports `buildSlotsFromWindows` from the web's `book-appointment.js`: chunks
/// each [AvailabilityWindow] into discrete slots of its own duration, drops
/// slots already in the past when [forDate] is today, and de-dupes on
/// `(start, duration, isTelemedicine)` — the backend can return the same
/// window twice (a `specific_date` override and its recurring `day_of_week`
/// row both matching).
///
/// [now] is injectable for tests; defaults to the real clock.
List<GeneratedSlot> generateSlotsFromWindows(
  List<AvailabilityWindow> windows, {
  required DateTime forDate,
  DateTime? now,
}) {
  final effectiveNow = now ?? DateTime.now();
  final isToday = forDate.year == effectiveNow.year &&
      forDate.month == effectiveNow.month &&
      forDate.day == effectiveNow.day;
  final nowMinutes = effectiveNow.hour * 60 + effectiveNow.minute;

  final seen = <String>{};
  final slots = <GeneratedSlot>[];

  for (final window in windows) {
    final duration = window.slotDurationMinutes > 0 ? window.slotDurationMinutes : 30;
    final startMinutes = _timeToMinutes(window.startTime);
    final endMinutes = _timeToMinutes(window.endTime);
    if (startMinutes == null || endMinutes == null) continue;

    for (var cur = startMinutes; cur + duration <= endMinutes; cur += duration) {
      if (isToday && cur <= nowMinutes) continue;

      final key = '$cur|$duration|${window.isTelemedicine ? 1 : 0}';
      if (!seen.add(key)) continue;

      slots.add(
        GeneratedSlot(
          id: key,
          startMinutes: cur,
          startTime: '${_minutesToHHMM(cur)}:00',
          endTime: '${_minutesToHHMM(cur + duration)}:00',
          startDisplay: _minutesToHHMM(cur),
          endDisplay: _minutesToHHMM(cur + duration),
          durationMinutes: duration,
          isTelemedicine: window.isTelemedicine,
        ),
      );
    }
  }

  slots.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  return slots;
}

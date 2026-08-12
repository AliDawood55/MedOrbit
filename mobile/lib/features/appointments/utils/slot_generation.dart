import '../models/availability_slot_model.dart';

/// `"YYYY-MM-DD"` in the device's local calendar, matching what the web
/// client sends (`dateKey()` in `book-appointment.js`) and what the backend's
/// `available-slots` query expects. Deliberately not `toIso8601String()`,
/// which would serialize in a way that can shift the calendar day.
String formatDateOnly(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-${_pad2(date.month)}-${_pad2(date.day)}';
}

String _pad2(int value) => value.toString().padLeft(2, '0');

String _minutesToHHMM(int minutes) =>
    '${_pad2(minutes ~/ 60)}:${_pad2(minutes % 60)}';

int? _timeToMinutes(String value) {
  final parts = value.split(':');
  if (parts.isEmpty) return null;
  final hours = int.tryParse(parts[0]);
  if (hours == null) return null;
  final minutes = parts.length > 1 ? int.tryParse(parts[1]) : 0;
  return hours * 60 + (minutes ?? 0);
}

/// Adapts the exact rows returned by `GET /appointments/available-slots` to
/// selectable UI values. It never subdivides a row or applies client-clock
/// filtering: availability, bookings, blocks, and past-time removal belong to
/// the backend. Malformed/stale non-slot rows are ignored defensively.
List<GeneratedSlot> normalizeServerSlots(List<AvailabilityWindow> rows) {
  final seen = <String>{};
  final slots = <GeneratedSlot>[];

  for (final row in rows) {
    final duration = row.slotDurationMinutes;
    final startMinutes = _timeToMinutes(row.startTime);
    final endMinutes = _timeToMinutes(row.endTime);
    if (startMinutes == null ||
        endMinutes == null ||
        duration <= 0 ||
        endMinutes - startMinutes != duration) {
      continue;
    }

    final key =
        '$startMinutes|$endMinutes|$duration|${row.isTelemedicine ? 1 : 0}';
    if (!seen.add(key)) continue;

    slots.add(
      GeneratedSlot(
        id: key,
        startMinutes: startMinutes,
        startTime: '${_minutesToHHMM(startMinutes)}:00',
        endTime: '${_minutesToHHMM(endMinutes)}:00',
        startDisplay: _minutesToHHMM(startMinutes),
        endDisplay: _minutesToHHMM(endMinutes),
        durationMinutes: duration,
        isTelemedicine: row.isTelemedicine,
      ),
    );
  }

  slots.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  return slots;
}

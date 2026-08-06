/// A doctor's recurring or one-off availability window, as returned verbatim
/// by `GET /appointments/available-slots` (a raw `doctor_availability` row).
///
/// This is *not* a bookable slot — the backend does not subtract already
/// booked appointments, so a window only says the doctor is generally
/// reachable then. [generateSlotsFromWindows] turns it into discrete,
/// individually selectable [GeneratedSlot]s.
class AvailabilityWindow {
  const AvailabilityWindow({
    required this.startTime,
    required this.endTime,
    this.slotDurationMinutes = 30,
    this.isTelemedicine = false,
  });

  /// `"HH:mm:ss"` — Postgres `TIME` serialized as a plain string.
  final String startTime;
  final String endTime;
  final int slotDurationMinutes;
  final bool isTelemedicine;

  factory AvailabilityWindow.fromJson(Map<String, dynamic> json) {
    return AvailabilityWindow(
      startTime: json['start_time'] as String? ?? '00:00:00',
      endTime: json['end_time'] as String? ?? '00:00:00',
      slotDurationMinutes: _asInt(json['slot_duration']) ?? 30,
      isTelemedicine: json['is_telemedicine'] == true,
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// A single bookable time slot, generated client-side by chunking an
/// [AvailabilityWindow] into pieces of its own `slotDurationMinutes`.
class GeneratedSlot {
  const GeneratedSlot({
    required this.id,
    required this.startMinutes,
    required this.startTime,
    required this.endTime,
    required this.startDisplay,
    required this.endDisplay,
    required this.durationMinutes,
    required this.isTelemedicine,
  });

  /// `startMinutes|durationMinutes|isTelemedicine` — stable identity for
  /// selection/highlighting. The same start time can legitimately appear
  /// twice (an in-person and a telemedicine window starting together, or two
  /// windows with different durations), so identity can't be `startMinutes`
  /// alone without ambiguously highlighting both.
  final String id;
  final int startMinutes;

  /// `"HH:mm:ss"` — wire format expected by `POST /appointments`.
  final String startTime;
  final String endTime;

  /// `"HH:mm"` — for display.
  final String startDisplay;
  final String endDisplay;
  final int durationMinutes;
  final bool isTelemedicine;
}

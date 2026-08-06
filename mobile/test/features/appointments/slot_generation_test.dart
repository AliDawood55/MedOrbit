import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/appointments/models/availability_slot_model.dart';
import 'package:mobile/features/appointments/utils/slot_generation.dart';

void main() {
  final future = DateTime(2026, 8, 10);
  final today = DateTime(2026, 8, 5);
  final referenceNow = DateTime(2026, 8, 5, 9, 30);

  group('formatDateOnly', () {
    test('formats local calendar date as YYYY-MM-DD', () {
      expect(formatDateOnly(DateTime(2026, 3, 4)), '2026-03-04');
    });
  });

  group('generateSlotsFromWindows', () {
    test('chunks a window into discrete slots of its own duration', () {
      final windows = [const AvailabilityWindow(startTime: '09:00:00', endTime: '10:00:00', slotDurationMinutes: 30)];

      final slots = generateSlotsFromWindows(windows, forDate: future);

      expect(slots, hasLength(2));
      expect(slots[0].startDisplay, '09:00');
      expect(slots[0].endDisplay, '09:30');
      expect(slots[0].startTime, '09:00:00');
      expect(slots[0].endTime, '09:30:00');
      expect(slots[1].startDisplay, '09:30');
      expect(slots[1].endDisplay, '10:00');
    });

    test('drops a trailing remainder shorter than the slot duration', () {
      // 09:00-10:10 at 30 min: 09:00, 09:30 fit; 10:00 does not (10:00+30 > 10:10).
      final windows = [const AvailabilityWindow(startTime: '09:00:00', endTime: '10:10:00', slotDurationMinutes: 30)];

      final slots = generateSlotsFromWindows(windows, forDate: future);

      expect(slots.map((s) => s.startDisplay), ['09:00', '09:30']);
    });

    test('excludes slots already in the past when forDate is today', () {
      final windows = [const AvailabilityWindow(startTime: '08:00:00', endTime: '11:00:00', slotDurationMinutes: 60)];

      final slots = generateSlotsFromWindows(windows, forDate: today, now: referenceNow);

      // 08:00 (<=09:30) and 09:00 (<=09:30) are in the past; 10:00 remains.
      expect(slots.map((s) => s.startDisplay), ['10:00']);
    });

    test('does not exclude past-looking times for a future date', () {
      final windows = [const AvailabilityWindow(startTime: '08:00:00', endTime: '09:00:00', slotDurationMinutes: 30)];

      final slots = generateSlotsFromWindows(windows, forDate: future, now: referenceNow);

      expect(slots, hasLength(2));
    });

    test('handles an empty window list', () {
      expect(generateSlotsFromWindows(const [], forDate: future), isEmpty);
    });

    test('de-dupes identical windows (start, duration, type) but keeps distinct ones at the same start', () {
      final windows = [
        const AvailabilityWindow(startTime: '09:00:00', endTime: '10:00:00', slotDurationMinutes: 30),
        // Exact duplicate (e.g. a specific_date override matching the recurring row too).
        const AvailabilityWindow(startTime: '09:00:00', endTime: '10:00:00', slotDurationMinutes: 30),
        // Same start, different type -> distinct slot, not a duplicate.
        const AvailabilityWindow(startTime: '09:00:00', endTime: '09:30:00', slotDurationMinutes: 30, isTelemedicine: true),
      ];

      final slots = generateSlotsFromWindows(windows, forDate: future);

      final atNine = slots.where((s) => s.startMinutes == 9 * 60).toList();
      expect(atNine, hasLength(2));
      expect(atNine.map((s) => s.isTelemedicine).toSet(), {false, true});
      expect(slots.map((s) => s.id).toSet(), hasLength(slots.length)); // ids unique
    });

    test('falls back to 30 minutes when slot_duration is 0', () {
      final windows = [const AvailabilityWindow(startTime: '09:00:00', endTime: '10:00:00', slotDurationMinutes: 0)];

      final slots = generateSlotsFromWindows(windows, forDate: future);

      expect(slots, hasLength(2));
      expect(slots.first.durationMinutes, 30);
    });

    test('sorts the merged result ascending by start time regardless of window order', () {
      final windows = [
        const AvailabilityWindow(startTime: '14:00:00', endTime: '14:30:00', slotDurationMinutes: 30),
        const AvailabilityWindow(startTime: '09:00:00', endTime: '09:30:00', slotDurationMinutes: 30),
      ];

      final slots = generateSlotsFromWindows(windows, forDate: future);

      expect(slots.map((s) => s.startDisplay), ['09:00', '14:00']);
    });

    test('never produces duplicate slot ids', () {
      final windows = [
        const AvailabilityWindow(startTime: '09:00:00', endTime: '12:00:00', slotDurationMinutes: 30),
        const AvailabilityWindow(startTime: '09:00:00', endTime: '12:00:00', slotDurationMinutes: 30),
        const AvailabilityWindow(startTime: '10:00:00', endTime: '13:00:00', slotDurationMinutes: 60),
      ];

      final slots = generateSlotsFromWindows(windows, forDate: future);

      expect(slots.map((s) => s.id).toSet(), hasLength(slots.length));
    });
  });
}

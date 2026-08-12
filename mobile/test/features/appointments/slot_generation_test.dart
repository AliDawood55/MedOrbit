import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/appointments/models/availability_slot_model.dart';
import 'package:mobile/features/appointments/utils/slot_generation.dart';

void main() {
  group('formatDateOnly', () {
    test('formats local calendar date as YYYY-MM-DD', () {
      expect(formatDateOnly(DateTime(2026, 3, 4)), '2026-03-04');
    });
  });

  group('normalizeServerSlots', () {
    test('preserves each exact backend slot without subdividing it', () {
      final rows = [
        const AvailabilityWindow(
          startTime: '09:00:00',
          endTime: '09:30:00',
          slotDurationMinutes: 30,
        ),
      ];

      final slots = normalizeServerSlots(rows);

      expect(slots, hasLength(1));
      expect(slots.single.startTime, '09:00:00');
      expect(slots.single.endTime, '09:30:00');
      expect(slots.single.durationMinutes, 30);
    });

    test(
      'rejects a raw availability window instead of generating client slots',
      () {
        final rows = [
          const AvailabilityWindow(
            startTime: '09:00:00',
            endTime: '10:00:00',
            slotDurationMinutes: 30,
          ),
        ];

        expect(normalizeServerSlots(rows), isEmpty);
      },
    );

    test(
      'de-duplicates exact rows, preserves type variants, and sorts by time',
      () {
        final rows = [
          const AvailabilityWindow(
            startTime: '14:00:00',
            endTime: '14:30:00',
            slotDurationMinutes: 30,
          ),
          const AvailabilityWindow(
            startTime: '09:00:00',
            endTime: '09:30:00',
            slotDurationMinutes: 30,
          ),
          const AvailabilityWindow(
            startTime: '09:00:00',
            endTime: '09:30:00',
            slotDurationMinutes: 30,
          ),
          const AvailabilityWindow(
            startTime: '09:00:00',
            endTime: '09:30:00',
            slotDurationMinutes: 30,
            isTelemedicine: true,
          ),
        ];

        final slots = normalizeServerSlots(rows);

        expect(slots.map((slot) => slot.startDisplay), [
          '09:00',
          '09:00',
          '14:00',
        ]);
        expect(
          slots
              .where((slot) => slot.startDisplay == '09:00')
              .map((slot) => slot.isTelemedicine)
              .toSet(),
          {false, true},
        );
        expect(slots.map((slot) => slot.id).toSet(), hasLength(slots.length));
      },
    );

    test('handles empty and malformed rows without inventing defaults', () {
      expect(normalizeServerSlots(const []), isEmpty);
      expect(
        normalizeServerSlots(const [
          AvailabilityWindow(
            startTime: 'bad',
            endTime: '09:30:00',
            slotDurationMinutes: 30,
          ),
        ]),
        isEmpty,
      );
      expect(
        normalizeServerSlots(const [
          AvailabilityWindow(
            startTime: '09:00:00',
            endTime: '09:30:00',
            slotDurationMinutes: 0,
          ),
        ]),
        isEmpty,
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/records/models/record_entry_model.dart';

const _canary = 'INTERNAL_ONLY_DO_NOT_RENDER';

Map<String, dynamic> _prescriptionEntryJson({Object? doctorNotes = _canary}) {
  return {
    'entry_type': 'prescription',
    'id': '1',
    'entry_date': '2026-08-01',
    'prescription_number': 'RX-2026-001',
    'prescription_date': '2026-08-01',
    'valid_until': null,
    'instructions': 'Take twice daily with food',
    'doctor_notes': doctorNotes,
    'items': const <Map<String, dynamic>>[],
  };
}

void main() {
  group('RecordEntryModel.fromJson', () {
    test('does not expose the backend doctor_notes field on the patient model', () {
      final entry = RecordEntryModel.fromJson(_prescriptionEntryJson());

      // The patient model has no doctorNotes property at all: a dynamic
      // lookup must fail rather than silently returning the private note.
      expect(
        () => (entry as dynamic).doctorNotes,
        throwsNoSuchMethodError,
      );
    });

    test('still maps legitimate patient-visible fields', () {
      final entry = RecordEntryModel.fromJson(_prescriptionEntryJson());

      expect(entry.instructions, 'Take twice daily with food');
      expect(entry.prescriptionNumber, 'RX-2026-001');
    });

    test('parses fine when doctor_notes is absent from the payload (current backend shape)', () {
      final json = _prescriptionEntryJson()..remove('doctor_notes');
      final entry = RecordEntryModel.fromJson(json);

      expect(entry.instructions, 'Take twice daily with food');
    });
  });
}

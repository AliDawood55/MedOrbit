import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/prescriptions/models/prescription_model.dart';

const _canary = 'INTERNAL_ONLY_DO_NOT_RENDER';

Map<String, dynamic> _json({Object? doctorNotes = _canary}) {
  return {
    'id': '1',
    'prescription_number': 'RX-2026-001',
    'prescription_date': '2026-08-01',
    'valid_until': null,
    'status': 'active',
    'diagnosis': 'Seasonal flu',
    'instructions': 'Take twice daily with food',
    'doctor_notes': doctorNotes,
    'items': const <Map<String, dynamic>>[],
  };
}

void main() {
  group('PrescriptionModel.fromJson', () {
    test('does not expose the backend doctor_notes field on the patient model', () {
      final prescription = PrescriptionModel.fromJson(_json());

      // The patient model has no doctorNotes property at all: a dynamic
      // lookup must fail rather than silently returning the private note.
      expect(
        () => (prescription as dynamic).doctorNotes,
        throwsNoSuchMethodError,
      );
    });

    test('still maps legitimate patient-visible fields', () {
      final prescription = PrescriptionModel.fromJson(_json());

      expect(prescription.diagnosis, 'Seasonal flu');
      expect(prescription.instructions, 'Take twice daily with food');
      expect(prescription.prescriptionNumber, 'RX-2026-001');
    });

    test('parses fine when doctor_notes is absent from the payload', () {
      final json = _json()..remove('doctor_notes');
      final prescription = PrescriptionModel.fromJson(json);

      expect(prescription.instructions, 'Take twice daily with food');
    });
  });
}

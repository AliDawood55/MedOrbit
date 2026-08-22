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

  group('PrescriptionModel.fromJson crash-safety', () {
    test('tolerates null optional fields', () {
      final json = _json()
        ..['valid_until'] = null
        ..['diagnosis'] = null
        ..['instructions'] = null;

      final prescription = PrescriptionModel.fromJson(json);

      expect(prescription.validUntil, isNull);
      expect(prescription.diagnosis, isNull);
      expect(prescription.instructions, isNull);
    });

    // id/prescription_number/prescription_date/status all come from
    // UUID/VARCHAR/DATE NOT NULL columns (`db/02_dependent_tables.sql`'s
    // `prescriptions` table) — never numeric or boolean in a well-formed
    // response, so none of them are silently coerced.
    test('throws FormatException for a numeric id instead of coercing it to a string', () {
      expect(() => PrescriptionModel.fromJson(_json()..['id'] = 7), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing id', () {
      final json = _json()..remove('id');

      expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing prescription_number', () {
      final json = _json()..remove('prescription_number');

      expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing prescription_date', () {
      final json = _json()..remove('prescription_date');

      expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing status instead of falling back to an empty string', () {
      final json = _json()..remove('status');

      expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when status is a structured value', () {
      expect(
        () => PrescriptionModel.fromJson(_json()..['status'] = {'nested': true}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when status is a boolean instead of coercing it to a string', () {
      expect(() => PrescriptionModel.fromJson(_json()..['status'] = true), throwsA(isA<FormatException>()));
    });

    test('a missing items key still parses to an empty list', () {
      final json = _json()..remove('items');

      expect(PrescriptionModel.fromJson(json).items, isEmpty);
    });

    test('a null items value still parses to an empty list', () {
      final prescription = PrescriptionModel.fromJson(_json()..['items'] = null);

      expect(prescription.items, isEmpty);
    });

    test('throws FormatException when items is present but not a list', () {
      final json = _json()..['items'] = {'not': 'a list'};

      expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test(
      'a malformed item entry fails the whole prescription instead of silently rendering a short medication list',
      () {
        final json = _json()
          ..['items'] = [
            {'medication_name_en': 'Amoxicillin', 'dosage': '500mg'},
            'not-an-object',
            {'medication_name_en': 'Ibuprofen', 'dosage': '200mg'},
          ];

        // The two well-formed entries must NOT leak through as a
        // partially-rendered "2 of 3 medications" list — the whole parse
        // fails so the patient sees the existing retry/error state instead.
        expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
      },
    );

    test('a null item entry fails the whole prescription', () {
      final json = _json()
        ..['items'] = [
          {'medication_name_en': 'Amoxicillin', 'dosage': '500mg'},
          null,
        ];

      expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test(
      'a structured malformed field inside an otherwise well-formed item fails the whole prescription',
      () {
        final json = _json()
          ..['items'] = [
            {
              'medication_name_en': {'unexpected': 'object'},
              'dosage': '500mg',
            },
          ];

        expect(() => PrescriptionModel.fromJson(json), throwsA(isA<FormatException>()));
      },
    );

    test('parses cleanly when every item entry is well-formed', () {
      final json = _json()
        ..['items'] = [
          {'medication_name_en': 'Amoxicillin', 'dosage': '500mg'},
          {'medication_name_en': 'Ibuprofen', 'dosage': '200mg'},
        ];

      final prescription = PrescriptionModel.fromJson(json);

      expect(prescription.items, hasLength(2));
      expect(prescription.items[0].medicationNameEn, 'Amoxicillin');
      expect(prescription.items[1].medicationNameEn, 'Ibuprofen');
    });
  });
}

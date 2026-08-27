import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/shared/models/prescription_item_model.dart';

void main() {
  group('PrescriptionItemModel.fromJson', () {
    test('maps a normal payload exactly', () {
      final item = PrescriptionItemModel.fromJson({
        'medication_name_ar': 'أموكسيسيلين',
        'medication_name_en': 'Amoxicillin',
        'dosage': '500mg',
        'frequency': 'twice daily',
        'duration': '7 days',
        'quantity': 14,
        'instructions': 'With food',
      });

      expect(item.medicationNameEn, 'Amoxicillin');
      expect(item.dosage, '500mg');
      expect(item.quantity, '14');
      expect(item.instructions, 'With food');
    });

    test('tolerates a fully empty object', () {
      final item = PrescriptionItemModel.fromJson(const {});

      expect(item.medicationNameEn, isNull);
      expect(item.dosage, isNull);
      expect(item.quantity, isNull);
    });

    // A nested Map/List is not "absent", it's malformed. Silently turning it
    // into `null` (previous P6D-draft behavior) would render an
    // incomplete-looking medication line without anyone knowing data was
    // lost — so this is a controlled failure instead, exactly like a
    // required field. The caller (PrescriptionModel.fromJson) turns this
    // into a controlled failure of the whole prescription parse rather than
    // a raw string label ("{unexpected: object}") ever reaching the UI.
    test('throws FormatException instead of turning a nested Map into an ugly stringified label', () {
      expect(
        () => PrescriptionItemModel.fromJson({'medication_name_en': {'unexpected': 'object'}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException instead of turning a nested Map quantity into an ugly stringified label', () {
      expect(
        () => PrescriptionItemModel.fromJson({'quantity': {'amount': 5}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException instead of turning a List value into an ugly stringified label', () {
      expect(
        () => PrescriptionItemModel.fromJson({
          'dosage': ['500mg', '250mg'],
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-structured wrong-type field (bool) is dropped, not stringified, and does not throw', () {
      final item = PrescriptionItemModel.fromJson({
        'medication_name_en': 'Ibuprofen',
        'frequency': true,
      });

      expect(item.medicationNameEn, 'Ibuprofen');
      expect(item.frequency, isNull);
    });
  });
}

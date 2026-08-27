import '../utils/json_parsing.dart';

class PrescriptionItemModel {
  const PrescriptionItemModel({
    this.medicationNameAr,
    this.medicationNameEn,
    this.dosage,
    this.frequency,
    this.duration,
    this.quantity,
    this.instructions,
  });

  final String? medicationNameAr;
  final String? medicationNameEn;
  final String? dosage;
  final String? frequency;
  final String? duration;
  final String? quantity;
  final String? instructions;

  /// All fields are optional (absent/null is a normal, legitimate shape),
  /// but this is clinical medication detail: a malformed *structured* value
  /// (a `Map`/`List` where a scalar was expected) throws a [FormatException]
  /// instead of being silently dropped, since silently nulling a medication
  /// name or dosage would render an incomplete-looking line without the
  /// patient — or the caller — ever knowing data was lost. `quantity` is the
  /// one field with a real product reason to also accept a bare `num`
  /// (backend's `quantity` column is `INTEGER NOT NULL`).
  factory PrescriptionItemModel.fromJson(Map<String, dynamic> json) {
    return PrescriptionItemModel(
      medicationNameAr: optionalStringOrFail(json, 'medication_name_ar'),
      medicationNameEn: optionalStringOrFail(json, 'medication_name_en'),
      dosage: optionalStringOrFail(json, 'dosage'),
      frequency: optionalStringOrFail(json, 'frequency'),
      duration: optionalStringOrFail(json, 'duration'),
      quantity: optionalScalarStringOrFail(json, 'quantity'),
      instructions: optionalStringOrFail(json, 'instructions'),
    );
  }
}

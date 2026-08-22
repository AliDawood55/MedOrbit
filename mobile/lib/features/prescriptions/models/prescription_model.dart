import '../../../shared/models/prescription_item_model.dart';
import '../../../shared/utils/json_parsing.dart';

/// One row of `GET /patients/me/prescriptions`
/// (`prescription.service.js#findByPatientId`).
class PrescriptionModel {
  const PrescriptionModel({
    required this.id,
    required this.prescriptionNumber,
    required this.prescriptionDate,
    this.validUntil,
    required this.status,
    this.diagnosis,
    this.instructions,
    this.items = const [],
  });

  final String id;
  final String prescriptionNumber;
  final String prescriptionDate;
  final String? validUntil;
  final String status;
  final String? diagnosis;
  final String? instructions;
  final List<PrescriptionItemModel> items;

  /// Throws a [FormatException] naming the missing/malformed field for
  /// required identity/date/status fields (`id`, `prescription_number`,
  /// `prescription_date`, `status`) — every one of these is a `UUID`/
  /// `VARCHAR`/`DATE NOT NULL`-shaped column (`db/02_dependent_tables.sql`'s
  /// `prescriptions` table); a fabricated id, date, or empty-string status
  /// would be worse than a controlled failure.
  ///
  /// `items`: a clinically important medication list must never silently
  /// render short. Missing/`null` `items` still parses to an empty list
  /// (a prescription can legitimately have none), but once present, every
  /// entry must be a valid object and parse cleanly — a non-list `items`,
  /// a non-object entry, or a malformed field inside one entry all fail the
  /// whole parse rather than silently dropping the entry or the field (see
  /// [PrescriptionItemModel.fromJson]).
  factory PrescriptionModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    List<PrescriptionItemModel> items;
    if (rawItems == null) {
      items = const [];
    } else if (rawItems is! List) {
      throw const FormatException('Malformed "items": expected a list');
    } else {
      items = rawItems.map((entry) {
        if (entry is! Map<String, dynamic>) {
          throw const FormatException('Malformed "items" entry: expected an object');
        }
        return PrescriptionItemModel.fromJson(entry);
      }).toList();
    }

    return PrescriptionModel(
      id: requireExactString(json, 'id'),
      prescriptionNumber: requireExactString(json, 'prescription_number'),
      prescriptionDate: requireExactString(json, 'prescription_date'),
      validUntil: optionalExactString(json, 'valid_until'),
      status: requireExactString(json, 'status').toLowerCase(),
      diagnosis: optionalExactString(json, 'diagnosis'),
      instructions: optionalExactString(json, 'instructions'),
      items: items,
    );
  }
}

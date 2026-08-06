import '../../../shared/models/prescription_item_model.dart';

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
    this.doctorNotes,
    this.items = const [],
  });

  final String id;
  final String prescriptionNumber;
  final String prescriptionDate;
  final String? validUntil;
  final String status;
  final String? diagnosis;
  final String? instructions;
  final String? doctorNotes;
  final List<PrescriptionItemModel> items;

  factory PrescriptionModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return PrescriptionModel(
      id: json['id'].toString(),
      prescriptionNumber: json['prescription_number'] as String,
      prescriptionDate: json['prescription_date'] as String,
      validUntil: json['valid_until'] as String?,
      status: (json['status'] as String? ?? '').toLowerCase(),
      diagnosis: json['diagnosis'] as String?,
      instructions: json['instructions'] as String?,
      doctorNotes: json['doctor_notes'] as String?,
      items: rawItems is List
          ? rawItems.map((e) => PrescriptionItemModel.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
    );
  }
}

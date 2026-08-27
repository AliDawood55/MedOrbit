import '../../../shared/utils/json_parsing.dart';

/// One row of `GET /patients/me/doctors/:doctorId/notes`
/// (`backend/src/routes/patient.routes.js`) — only rows the doctor
/// explicitly marked `visible_to_patient=true` and never `is_draft=true`.
///
/// PRIVACY: the backend query never selects `doctor_notes`, and this model
/// must never gain a field for it — that column stays doctor-internal even
/// for an otherwise-shared record. There is deliberately no `fromJson`
/// pathway that reads `json['doctor_notes']` anywhere in this class.
class SharedNoteModel {
  const SharedNoteModel({
    required this.id,
    this.recordType,
    this.chiefComplaint,
    this.diagnosis,
    this.treatmentPlan,
    this.clinicalNotes,
    this.createdAt,
  });

  final String id;
  final String? recordType;
  final String? chiefComplaint;
  final String? diagnosis;
  final String? treatmentPlan;
  final String? clinicalNotes;
  final String? createdAt;

  /// Throws a [FormatException] naming "id" if missing/blank — every other
  /// field is optional clinical presentation text that degrades the card
  /// rather than failing the whole note.
  factory SharedNoteModel.fromJson(Map<String, dynamic> json) {
    return SharedNoteModel(
      id: requireExactString(json, 'id'),
      recordType: optionalExactString(json, 'record_type'),
      chiefComplaint: optionalExactString(json, 'chief_complaint'),
      diagnosis: optionalExactString(json, 'diagnosis'),
      treatmentPlan: optionalExactString(json, 'treatment_plan'),
      clinicalNotes: optionalExactString(json, 'clinical_notes'),
      createdAt: optionalExactString(json, 'created_at'),
    );
  }
}

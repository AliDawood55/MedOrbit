import '../../../shared/models/prescription_item_model.dart';
import '../../../shared/utils/localized_field.dart';

/// One row of `GET /patients/me/records` — a polymorphic timeline entry.
/// Backend merges 3 sources (`patient.routes.js:134-144`); only the fields
/// relevant to `entryType` are populated, the rest stay null.
class RecordEntryModel {
  const RecordEntryModel({
    required this.entryType,
    required this.id,
    this.entryDate,
    this.createdAt,
    this.appointmentNumber,
    this.scheduledDate,
    this.startTime,
    this.status,
    this.appointmentType,
    this.reasonForVisit,
    this.specialtyAr,
    this.specialtyEn,
    this.recordNumber,
    this.recordType,
    this.chiefComplaint,
    this.diagnosis,
    this.treatmentPlan,
    this.vitals,
    this.prescriptionNumber,
    this.prescriptionDate,
    this.validUntil,
    this.instructions,
    this.items = const [],
    this.doctorFirstNameAr,
    this.doctorFirstNameEn,
    this.doctorLastNameAr,
    this.doctorLastNameEn,
  });

  final String entryType; // 'appointment' | 'record' | 'prescription'
  final String id;
  final String? entryDate;
  final String? createdAt;

  // entry_type == 'appointment'
  final String? appointmentNumber;
  final String? scheduledDate;
  final String? startTime;
  final String? status;
  final String? appointmentType;
  final String? reasonForVisit;
  final String? specialtyAr;
  final String? specialtyEn;

  // entry_type == 'record'
  final String? recordNumber;
  final String? recordType;
  final String? chiefComplaint;
  final String? diagnosis;
  final String? treatmentPlan;
  final Map<String, dynamic>? vitals;

  // entry_type == 'prescription'
  final String? prescriptionNumber;
  final String? prescriptionDate;
  final String? validUntil;
  final String? instructions;
  final List<PrescriptionItemModel> items;

  // shared by 'appointment' and 'record'
  final String? doctorFirstNameAr;
  final String? doctorFirstNameEn;
  final String? doctorLastNameAr;
  final String? doctorLastNameEn;

  String? doctorFullName(bool isArabic) {
    final first = localizedField(isArabic: isArabic, ar: doctorFirstNameAr, en: doctorFirstNameEn);
    final last = localizedField(isArabic: isArabic, ar: doctorLastNameAr, en: doctorLastNameEn);
    final full = '$first $last'.trim();
    return full.isEmpty ? null : full;
  }

  String? specialty(bool isArabic) {
    final value = localizedField(isArabic: isArabic, ar: specialtyAr, en: specialtyEn);
    return value.isEmpty ? null : value;
  }

  factory RecordEntryModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawVitals = json['vitals'];
    return RecordEntryModel(
      entryType: json['entry_type'] as String,
      id: json['id'].toString(),
      entryDate: json['entry_date']?.toString(),
      createdAt: json['created_at']?.toString(),
      appointmentNumber: json['appointment_number'] as String?,
      scheduledDate: json['scheduled_date'] as String?,
      startTime: json['start_time'] as String?,
      status: json['status'] as String?,
      appointmentType: json['appointment_type'] as String?,
      reasonForVisit: json['reason_for_visit'] as String?,
      specialtyAr: json['specialty_ar'] as String?,
      specialtyEn: json['specialty_en'] as String?,
      recordNumber: json['record_number'] as String?,
      recordType: json['record_type'] as String?,
      chiefComplaint: json['chief_complaint'] as String?,
      diagnosis: json['diagnosis'] as String?,
      treatmentPlan: json['treatment_plan'] as String?,
      vitals: rawVitals is Map
          ? Map<String, dynamic>.from(rawVitals)
          : null,
      prescriptionNumber: json['prescription_number'] as String?,
      prescriptionDate: json['prescription_date'] as String?,
      validUntil: json['valid_until'] as String?,
      instructions: json['instructions'] as String?,
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map(
                (item) => PrescriptionItemModel.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
          : const [],
      doctorFirstNameAr: json['doctor_first_name_ar'] as String?,
      doctorFirstNameEn: json['doctor_first_name_en'] as String?,
      doctorLastNameAr: json['doctor_last_name_ar'] as String?,
      doctorLastNameEn: json['doctor_last_name_en'] as String?,
    );
  }
}

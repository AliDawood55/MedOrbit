class PatientDoctor {
  const PatientDoctor({
    required this.id,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.specialtyAr,
    this.specialtyEn,
    this.nextAppointmentDate,
    this.lastAppointmentDate,
    this.hasUpcoming = false,
  });

  final String id;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? specialtyAr;
  final String? specialtyEn;
  final String? nextAppointmentDate;
  final String? lastAppointmentDate;
  final bool hasUpcoming;

  factory PatientDoctor.fromJson(Map<String, dynamic> json) => PatientDoctor(
    id: _string(json['id']),
    firstNameAr: _nullableString(json['first_name_ar']),
    lastNameAr: _nullableString(json['last_name_ar']),
    firstNameEn: _nullableString(json['first_name_en']),
    lastNameEn: _nullableString(json['last_name_en']),
    specialtyAr: _nullableString(json['specialty_ar']),
    specialtyEn: _nullableString(json['specialty_en']),
    nextAppointmentDate: _nullableString(json['next_appointment_date']),
    lastAppointmentDate: _nullableString(json['last_appointment_date']),
    hasUpcoming: json['has_upcoming'] == true,
  );

  String fullName(bool isArabic) {
    final values = isArabic
        ? [firstNameAr, lastNameAr]
        : [firstNameEn, lastNameEn];
    final result = values
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .join(' ');
    if (result.isNotEmpty) return result;
    return isArabic
        ? [firstNameEn, lastNameEn].whereType<String>().join(' ')
        : [firstNameAr, lastNameAr].whereType<String>().join(' ');
  }

  String? specialty(bool isArabic) =>
      isArabic ? (specialtyAr ?? specialtyEn) : (specialtyEn ?? specialtyAr);
}

class SharedDoctorNote {
  const SharedDoctorNote({
    required this.id,
    this.recordType,
    this.diagnosis,
    this.treatmentPlan,
    this.clinicalNotes,
    this.createdAt,
  });

  final String id;
  final String? recordType;
  final String? diagnosis;
  final String? treatmentPlan;
  final String? clinicalNotes;
  final String? createdAt;

  factory SharedDoctorNote.fromJson(Map<String, dynamic> json) =>
      SharedDoctorNote(
        id: _string(json['id']),
        recordType: _nullableString(json['record_type']),
        diagnosis: _nullableString(json['diagnosis']),
        treatmentPlan: _nullableString(json['treatment_plan']),
        clinicalNotes: _nullableString(json['clinical_notes']),
        createdAt: _nullableString(json['created_at']),
      );
}

String _string(Object? value) => value is String ? value : '';
String? _nullableString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

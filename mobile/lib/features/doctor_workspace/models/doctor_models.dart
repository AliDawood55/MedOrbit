import '../../../shared/utils/json_parsing.dart';

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('Missing or invalid object "$field"');
}

List<Map<String, dynamic>> _maps(Object? value, String field) {
  if (value is! List) throw FormatException('Missing or invalid list "$field"');
  return value.map((entry) => _map(entry, field)).toList(growable: false);
}

int? _integer(Object? value) => value is int
    ? value
    : value is num
    ? value.toInt()
    : null;
double? _decimal(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
bool _boolean(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;
List<String> _strings(Object? value) => value is List
    ? value
          .whereType<String>()
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(growable: false)
    : const [];

class DoctorProfile {
  const DoctorProfile({
    required this.id,
    required this.approvalStatus,
    required this.isAcceptingPatients,
    this.licenseNumber,
    this.specialtyAr,
    this.specialtyEn,
    this.subSpecialty,
    this.headline,
    this.bio,
    this.city,
    this.yearsOfExperience,
    this.consultationFee,
    this.consultationDuration,
    this.profileImageUrl,
    this.expertise = const [],
    this.interests = const [],
    this.languages = const [],
    this.education = const [],
    this.certifications = const [],
  });
  final String id, approvalStatus;
  final bool isAcceptingPatients;
  final String? licenseNumber,
      specialtyAr,
      specialtyEn,
      subSpecialty,
      headline,
      bio,
      city,
      profileImageUrl;
  final int? yearsOfExperience, consultationDuration;
  final double? consultationFee;
  final List<String> expertise, interests, languages, education, certifications;
  bool get isApproved => approvalStatus.toLowerCase() == 'approved';
  factory DoctorProfile.fromJson(Map<String, dynamic> json) => DoctorProfile(
    id: requireExactString(json, 'id'),
    approvalStatus: requireExactString(json, 'approval_status'),
    isAcceptingPatients: _boolean(json['is_accepting_patients']),
    licenseNumber: optionalExactString(json, 'medical_license_number'),
    specialtyAr: optionalExactString(json, 'specialty_ar'),
    specialtyEn: optionalExactString(json, 'specialty_en'),
    subSpecialty: optionalExactString(json, 'sub_specialty'),
    headline: optionalExactString(json, 'professional_headline'),
    bio: optionalExactString(json, 'professional_bio'),
    city: optionalExactString(json, 'city'),
    yearsOfExperience: _integer(json['years_of_experience']),
    consultationFee: _decimal(json['consultation_fee']),
    consultationDuration: _integer(json['consultation_duration']),
    profileImageUrl: optionalExactString(json, 'profile_image_url'),
    expertise: _strings(json['areas_of_expertise']),
    interests: _strings(json['professional_interests']),
    languages: _strings(json['languages_spoken']),
    education: _strings(json['education']),
    certifications: _strings(json['certifications']),
  );
}

class DoctorClinic {
  const DoctorClinic({
    required this.id,
    this.nameAr,
    this.nameEn,
    required this.isPrimary,
  });
  final String id;
  final String? nameAr, nameEn;
  final bool isPrimary;
  factory DoctorClinic.fromJson(Map<String, dynamic> json) => DoctorClinic(
    id: requireExactString(json, 'id'),
    nameAr: optionalExactString(json, 'name_ar'),
    nameEn: optionalExactString(json, 'name_en'),
    isPrimary: _boolean(json['is_primary']),
  );
}

class DoctorAvailability {
  const DoctorAvailability({
    required this.id,
    this.clinicId,
    this.dayOfWeek,
    this.specificDate,
    required this.startTime,
    required this.endTime,
    required this.slotDuration,
    required this.isTelemedicine,
    required this.type,
    required this.isActive,
  });
  final String id, startTime, endTime, type;
  final String? clinicId, specificDate;
  final int? dayOfWeek;
  final int slotDuration;
  final bool isTelemedicine, isActive;
  factory DoctorAvailability.fromJson(Map<String, dynamic> json) =>
      DoctorAvailability(
        id: requireExactString(json, 'id'),
        clinicId: optionalExactString(json, 'clinic_id'),
        dayOfWeek: _integer(json['day_of_week']),
        specificDate: optionalExactString(json, 'specific_date'),
        startTime: requireExactString(json, 'start_time'),
        endTime: requireExactString(json, 'end_time'),
        slotDuration:
            _integer(json['slot_duration']) ??
            (throw const FormatException('Invalid slot_duration')),
        isTelemedicine: _boolean(json['is_telemedicine']),
        type: requireExactString(json, 'availability_type'),
        isActive: _boolean(json['is_active']),
      );
}

class DoctorAppointment {
  const DoctorAppointment({
    required this.id,
    required this.number,
    this.patientProfileId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.status,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.reason,
  });
  final String id, number, date, startTime, endTime, type, status;
  final String? patientProfileId,
      firstNameAr,
      lastNameAr,
      firstNameEn,
      lastNameEn,
      reason;
  factory DoctorAppointment.fromJson(Map<String, dynamic> json) =>
      DoctorAppointment(
        id: requireExactString(json, 'id'),
        number: requireExactString(json, 'appointment_number'),
        patientProfileId: optionalExactString(json, 'patient_profile_id'),
        date: requireExactString(json, 'scheduled_date'),
        startTime: requireExactString(json, 'start_time'),
        endTime: requireExactString(json, 'end_time'),
        type: requireExactString(json, 'appointment_type'),
        status: requireExactString(json, 'status'),
        firstNameAr: optionalExactString(json, 'first_name_ar'),
        lastNameAr: optionalExactString(json, 'last_name_ar'),
        firstNameEn: optionalExactString(json, 'first_name_en'),
        lastNameEn: optionalExactString(json, 'last_name_en'),
        reason: optionalExactString(json, 'reason_for_visit'),
      );
}

class DoctorSchedule {
  const DoctorSchedule({
    required this.bookingHorizonDays,
    required this.weekly,
    required this.overrides,
    required this.clinics,
    required this.appointments,
  });
  final int bookingHorizonDays;
  final List<DoctorAvailability> weekly, overrides;
  final List<DoctorClinic> clinics;
  final List<DoctorAppointment> appointments;
  factory DoctorSchedule.fromJson(Map<String, dynamic> json) => DoctorSchedule(
    bookingHorizonDays:
        _integer(json['booking_horizon_days']) ??
        (throw const FormatException('Invalid booking horizon')),
    weekly: _maps(
      json['weekly'],
      'weekly',
    ).map(DoctorAvailability.fromJson).toList(growable: false),
    overrides: _maps(
      json['overrides'],
      'overrides',
    ).map(DoctorAvailability.fromJson).toList(growable: false),
    clinics: _maps(
      json['clinics'],
      'clinics',
    ).map(DoctorClinic.fromJson).toList(growable: false),
    appointments: _maps(
      json['appointments'],
      'appointments',
    ).map(DoctorAppointment.fromJson).toList(growable: false),
  );
}

class DoctorPatient {
  const DoctorPatient({
    required this.id,
    required this.email,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.phone,
    this.profileImageUrl,
    this.relationshipStartedAt,
    this.relationshipSource,
    this.nextAppointmentDate,
    this.lastAppointmentDate,
    required this.hasUpcoming,
    this.dateOfBirth,
    this.gender,
  });
  final String id, email;
  final String? firstNameAr,
      lastNameAr,
      firstNameEn,
      lastNameEn,
      phone,
      profileImageUrl,
      relationshipStartedAt,
      relationshipSource,
      nextAppointmentDate,
      lastAppointmentDate,
      dateOfBirth,
      gender;
  final bool hasUpcoming;
  factory DoctorPatient.fromJson(Map<String, dynamic> json) => DoctorPatient(
    id: requireExactString(json, 'id'),
    email: requireExactString(json, 'email'),
    firstNameAr: optionalExactString(json, 'first_name_ar'),
    lastNameAr: optionalExactString(json, 'last_name_ar'),
    firstNameEn: optionalExactString(json, 'first_name_en'),
    lastNameEn: optionalExactString(json, 'last_name_en'),
    phone: optionalExactString(json, 'phone'),
    profileImageUrl: optionalExactString(json, 'profile_image_url'),
    relationshipStartedAt: optionalExactString(json, 'relationship_started_at'),
    relationshipSource: optionalExactString(json, 'relationship_source'),
    nextAppointmentDate: optionalExactString(json, 'next_appointment_date'),
    lastAppointmentDate: optionalExactString(json, 'last_appointment_date'),
    hasUpcoming: _boolean(json['has_upcoming']),
    dateOfBirth: optionalExactString(json, 'date_of_birth'),
    gender: optionalExactString(json, 'gender'),
  );
}

class ClinicalRecord {
  const ClinicalRecord({
    required this.id,
    required this.recordNumber,
    required this.recordType,
    required this.isDraft,
    required this.visibleToPatient,
    this.appointmentId,
    this.patientId,
    this.doctorId,
    this.chiefComplaint,
    this.diagnosis,
    this.treatmentPlan,
    this.clinicalNotes,
    this.doctorNotes,
    this.createdAt,
  });
  final String id, recordNumber, recordType;
  final String? appointmentId,
      patientId,
      doctorId,
      chiefComplaint,
      diagnosis,
      treatmentPlan,
      clinicalNotes,
      doctorNotes,
      createdAt;
  final bool isDraft, visibleToPatient;
  factory ClinicalRecord.fromJson(Map<String, dynamic> json) => ClinicalRecord(
    id: requireExactString(json, 'id'),
    recordNumber: requireExactString(json, 'record_number'),
    recordType: requireExactString(json, 'record_type'),
    appointmentId: optionalExactString(json, 'appointment_id'),
    patientId: optionalExactString(json, 'patient_id'),
    doctorId: optionalExactString(json, 'doctor_id'),
    chiefComplaint: optionalExactString(json, 'chief_complaint'),
    diagnosis: optionalExactString(json, 'diagnosis'),
    treatmentPlan: optionalExactString(json, 'treatment_plan'),
    clinicalNotes: optionalExactString(json, 'clinical_notes'),
    doctorNotes: optionalExactString(json, 'doctor_notes'),
    createdAt: optionalExactString(json, 'created_at'),
    isDraft: _boolean(json['is_draft']),
    visibleToPatient: _boolean(json['visible_to_patient']),
  );
}

class DoctorPrescription {
  const DoctorPrescription({
    required this.id,
    required this.number,
    required this.status,
    this.date,
    this.validUntil,
    this.diagnosis,
    this.instructions,
  });
  final String id, number, status;
  final String? date, validUntil, diagnosis, instructions;
  factory DoctorPrescription.fromJson(Map<String, dynamic> json) =>
      DoctorPrescription(
        id: requireExactString(json, 'id'),
        number: requireExactString(json, 'prescription_number'),
        status: requireExactString(json, 'status'),
        date: optionalExactString(json, 'prescription_date'),
        validUntil: optionalExactString(json, 'valid_until'),
        diagnosis: optionalExactString(json, 'diagnosis'),
        instructions: optionalExactString(json, 'instructions'),
      );
}

class DoctorPatientDetail {
  const DoctorPatientDetail({
    required this.patient,
    required this.appointments,
    required this.notes,
    required this.prescriptions,
  });
  final DoctorPatient patient;
  final List<DoctorAppointment> appointments;
  final List<ClinicalRecord> notes;
  final List<DoctorPrescription> prescriptions;
  factory DoctorPatientDetail.fromJson(Map<String, dynamic> json) =>
      DoctorPatientDetail(
        patient: DoctorPatient.fromJson(_map(json['patient'], 'patient')),
        appointments: _maps(
          json['appointments'],
          'appointments',
        ).map(DoctorAppointment.fromJson).toList(growable: false),
        notes: _maps(
          json['notes'],
          'notes',
        ).map(ClinicalRecord.fromJson).toList(growable: false),
        prescriptions: _maps(
          json['prescriptions'],
          'prescriptions',
        ).map(DoctorPrescription.fromJson).toList(growable: false),
      );
}

class DoctorPost {
  const DoctorPost({
    required this.id,
    required this.title,
    required this.category,
    required this.body,
    required this.isPublished,
    required this.status,
    required this.moderationStatus,
    this.publishedAt,
    this.createdAt,
    this.updatedAt,
    this.likeCount = 0,
    this.commentCount = 0,
  });
  final String id, title, category, body, status, moderationStatus;
  final bool isPublished;
  final String? publishedAt, createdAt, updatedAt;
  final int likeCount, commentCount;
  factory DoctorPost.fromJson(Map<String, dynamic> json) => DoctorPost(
    id: requireExactString(json, 'id'),
    title: requireExactString(json, 'title'),
    category: requireExactString(json, 'category'),
    body: requireExactString(json, 'body'),
    isPublished: _boolean(json['is_published']),
    status: requireExactString(json, 'status'),
    moderationStatus: requireExactString(json, 'moderation_status'),
    publishedAt: optionalExactString(json, 'published_at'),
    createdAt: optionalExactString(json, 'created_at'),
    updatedAt: optionalExactString(json, 'updated_at'),
    likeCount: _integer(json['like_count']) ?? 0,
    commentCount: _integer(json['comment_count']) ?? 0,
  );
}

class PrescriptionResult {
  const PrescriptionResult({
    required this.prescription,
    required this.safetyStatus,
  });
  final DoctorPrescription prescription;
  final String safetyStatus;
}

import '../../../shared/utils/json_parsing.dart';
import '../../../shared/utils/localized_field.dart';

/// One row of `GET /patients/me/doctors`
/// (`backend/src/routes/patient.routes.js`) — doctors with an active
/// `doctor_patient_relationships` row for this patient. `id` is the
/// clinical `doctors.id`, never the underlying `users.id`.
class MyDoctorModel {
  const MyDoctorModel({
    required this.id,
    this.email,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.phone,
    this.profileImageUrl,
    this.specialtyAr,
    this.specialtyEn,
    this.consultationFee,
    this.averageRating,
    this.relationshipStartedAt,
    this.relationshipSource,
    this.nextAppointmentDate,
    this.lastAppointmentDate,
    this.hasUpcoming = false,
  });

  final String id;
  final String? email;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? phone;
  final String? profileImageUrl;
  final String? specialtyAr;
  final String? specialtyEn;
  final double? consultationFee;
  final double? averageRating;
  final String? relationshipStartedAt;
  final String? relationshipSource;
  final String? nextAppointmentDate;
  final String? lastAppointmentDate;
  final bool hasUpcoming;

  /// Throws a [FormatException] naming "id" if missing/blank — `d.id` is a
  /// `UUID NOT NULL` column (`db/02_dependent_tables.sql`'s `doctors`
  /// table) and every action on the My Doctor screen (view doctor, book
  /// appointment, load shared notes) is keyed off it, so a fabricated id
  /// would silently point the patient at the wrong doctor. Every other
  /// field is presentation-only and parses leniently — a malformed/missing
  /// name, specialty, avatar, rating, or date degrades the card instead of
  /// failing the whole doctor.
  factory MyDoctorModel.fromJson(Map<String, dynamic> json) {
    return MyDoctorModel(
      id: requireExactString(json, 'id'),
      email: optionalExactString(json, 'email'),
      firstNameAr: optionalExactString(json, 'first_name_ar'),
      lastNameAr: optionalExactString(json, 'last_name_ar'),
      firstNameEn: optionalExactString(json, 'first_name_en'),
      lastNameEn: optionalExactString(json, 'last_name_en'),
      phone: optionalExactString(json, 'phone'),
      profileImageUrl: optionalExactString(json, 'profile_image_url'),
      specialtyAr: optionalExactString(json, 'specialty_ar'),
      specialtyEn: optionalExactString(json, 'specialty_en'),
      consultationFee: _asDouble(json['consultation_fee']),
      averageRating: _asDouble(json['average_rating']),
      relationshipStartedAt: optionalExactString(json, 'relationship_started_at'),
      relationshipSource: optionalExactString(json, 'relationship_source'),
      nextAppointmentDate: optionalExactString(json, 'next_appointment_date'),
      lastAppointmentDate: optionalExactString(json, 'last_appointment_date'),
      hasUpcoming: _asBool(json['has_upcoming']) ?? false,
    );
  }

  /// Preferred-language full name, falling back to the other language then
  /// to the account email — same fallback chain as the web app's
  /// `my-doctor.js#doctorName`.
  String displayName(bool isArabic) {
    final first = localizedField(isArabic: isArabic, ar: firstNameAr, en: firstNameEn);
    final last = localizedField(isArabic: isArabic, ar: lastNameAr, en: lastNameEn);
    final full = '$first $last'.trim();
    if (full.isNotEmpty) return full;
    return email?.trim() ?? '';
  }

  String? displaySpecialty(bool isArabic) {
    final value = localizedField(isArabic: isArabic, ar: specialtyAr, en: specialtyEn);
    return value.isEmpty ? null : value;
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) return bool.tryParse(value);
  return null;
}

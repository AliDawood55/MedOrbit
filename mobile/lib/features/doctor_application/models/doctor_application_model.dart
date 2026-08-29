import '../../../shared/utils/json_parsing.dart';

enum DoctorApplicationStatus { pending, approved, rejected, withdrawn, unknown }

extension DoctorApplicationStatusParsing on DoctorApplicationStatus {
  static DoctorApplicationStatus fromWireValue(String value) {
    switch (value) {
      case 'pending':
        return DoctorApplicationStatus.pending;
      case 'approved':
        return DoctorApplicationStatus.approved;
      case 'rejected':
        return DoctorApplicationStatus.rejected;
      case 'withdrawn':
        return DoctorApplicationStatus.withdrawn;
      default:
        return DoctorApplicationStatus.unknown;
    }
  }
}

class DoctorApplication {
  const DoctorApplication({
    required this.id,
    required this.userId,
    required this.specialtyId,
    required this.medicalLicenseNumber,
    required this.status,
    required this.statusValue,
    required this.submittedAt,
    this.subSpecialty,
    this.yearsOfExperience,
    this.education = const [],
    this.certifications = const [],
    this.bio,
    this.bioAr,
    this.bioEn,
    this.consultationFee,
    this.consultationDuration,
    this.reviewedAt,
    this.rejectionReason,
    this.approvedDoctorId,
  });

  final String id;
  final String userId;
  final String specialtyId;
  final String medicalLicenseNumber;
  final String? subSpecialty;
  final int? yearsOfExperience;
  final List<String> education;
  final List<String> certifications;
  final String? bio;
  final String? bioAr;
  final String? bioEn;
  final double? consultationFee;
  final int? consultationDuration;
  final DoctorApplicationStatus status;

  /// The original server value is retained so an unknown status is never
  /// presented as one of the known lifecycle states.
  final String statusValue;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final String? approvedDoctorId;

  factory DoctorApplication.fromJson(Map<String, dynamic> json) {
    final statusValue = requireExactString(json, 'status');
    return DoctorApplication(
      id: requireExactString(json, 'id'),
      userId: requireExactString(json, 'user_id'),
      specialtyId: requireExactString(json, 'specialty_id'),
      medicalLicenseNumber: requireExactString(json, 'medical_license_number'),
      subSpecialty: optionalExactString(json, 'sub_specialty'),
      yearsOfExperience: _optionalInt(json['years_of_experience']),
      education: _stringList(json['education']),
      certifications: _stringList(json['certifications']),
      bio: optionalExactString(json, 'bio'),
      bioAr: optionalExactString(json, 'bio_ar'),
      bioEn: optionalExactString(json, 'bio_en'),
      consultationFee: _optionalDouble(json['consultation_fee']),
      consultationDuration: _optionalInt(json['consultation_duration']),
      status: DoctorApplicationStatusParsing.fromWireValue(statusValue),
      statusValue: statusValue,
      submittedAt: _requireDate(json, 'submitted_at'),
      reviewedAt: _optionalDate(json['reviewed_at']),
      rejectionReason: optionalExactString(json, 'rejection_reason'),
      approvedDoctorId: optionalExactString(json, 'approved_doctor_id'),
    );
  }
}

class DoctorApplicationRequest {
  DoctorApplicationRequest({
    required String specialtyId,
    required String medicalLicenseNumber,
    String? subSpecialty,
    this.yearsOfExperience,
    Iterable<String> education = const [],
    Iterable<String> certifications = const [],
    String? bio,
  }) : specialtyId = specialtyId.trim(),
       medicalLicenseNumber = _requiredTrimmed(medicalLicenseNumber, 'medicalLicenseNumber'),
       subSpecialty = _nullableTrimmed(subSpecialty),
       education = _normalizeLines(education),
       certifications = _normalizeLines(certifications),
       bio = _nullableTrimmed(bio) {
    if (this.specialtyId.isEmpty) {
      throw ArgumentError.value(specialtyId, 'specialtyId', 'must not be blank');
    }
  }

  final String specialtyId;
  final String medicalLicenseNumber;
  final String? subSpecialty;
  final int? yearsOfExperience;
  final List<String> education;
  final List<String> certifications;
  final String? bio;

  factory DoctorApplicationRequest.fromMultiline({
    required String specialtyId,
    required String medicalLicenseNumber,
    String? subSpecialty,
    int? yearsOfExperience,
    String? education,
    String? certifications,
    String? bio,
  }) => DoctorApplicationRequest(
    specialtyId: specialtyId,
    medicalLicenseNumber: medicalLicenseNumber,
    subSpecialty: subSpecialty,
    yearsOfExperience: yearsOfExperience,
    education: _splitLines(education),
    certifications: _splitLines(certifications),
    bio: bio,
  );

  Map<String, dynamic> toJson() => {
    'specialty_id': specialtyId,
    'medical_license_number': medicalLicenseNumber,
    'sub_specialty': subSpecialty,
    'years_of_experience': yearsOfExperience,
    'education': List<String>.from(education),
    'certifications': List<String>.from(certifications),
    'bio': bio,
  };
}

String _requiredTrimmed(String value, String name) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) throw ArgumentError.value(value, name, 'must not be blank');
  return trimmed;
}

String? _nullableTrimmed(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> _splitLines(String? value) => value == null ? const [] : value.split(RegExp(r'\r?\n'));

List<String> _normalizeLines(Iterable<String> values) => List.unmodifiable(
  values.map((value) => value.trim()).where((value) => value.isNotEmpty),
);

List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('Malformed string list.');
  }
  return List.unmodifiable(value.cast<String>());
}

DateTime _requireDate(Map<String, dynamic> json, String field) {
  final value = json[field];
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null) throw FormatException('Missing or invalid required field "$field"');
  return parsed;
}

DateTime? _optionalDate(Object? value) => value is String ? DateTime.tryParse(value) : null;

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return value is String ? int.tryParse(value) : null;
}

double? _optionalDouble(Object? value) => value is num ? value.toDouble() : (value is String ? double.tryParse(value) : null);

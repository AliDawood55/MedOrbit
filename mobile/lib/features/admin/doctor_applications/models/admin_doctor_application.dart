import '../../../../shared/utils/localized_field.dart';
import '../../common/models/admin_parsing.dart';

/// Lifecycle states of `medorbit.doctor_applications.status`.
enum AdminApplicationStatus { pending, approved, rejected, withdrawn, unknown }

AdminApplicationStatus adminApplicationStatusFromWire(String value) =>
    switch (value) {
      'pending' => AdminApplicationStatus.pending,
      'approved' => AdminApplicationStatus.approved,
      'rejected' => AdminApplicationStatus.rejected,
      'withdrawn' => AdminApplicationStatus.withdrawn,
      _ => AdminApplicationStatus.unknown,
    };

/// The `status` query value for each filter, or `null` for "all".
/// The web review page offers exactly these four options.
String? adminApplicationStatusWireValue(AdminApplicationStatus? status) =>
    switch (status) {
      AdminApplicationStatus.pending => 'pending',
      AdminApplicationStatus.approved => 'approved',
      AdminApplicationStatus.rejected => 'rejected',
      AdminApplicationStatus.withdrawn => 'withdrawn',
      _ => null,
    };

/// The applicant identity block the admin projection adds.
class AdminApplicant {
  const AdminApplicant({
    required this.email,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
  });

  final String? email;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;

  /// Bilingual display name with the web page's fallback chain: preferred
  /// language, then the other language, then the email address.
  String displayName({required bool isArabic}) {
    final first = localizedField(
      isArabic: isArabic,
      ar: firstNameAr,
      en: firstNameEn,
    );
    final last = localizedField(
      isArabic: isArabic,
      ar: lastNameAr,
      en: lastNameEn,
    );
    final full = adminJoinName(first, last);
    if (full.isNotEmpty) return full;
    return email ?? '';
  }

  factory AdminApplicant.fromJson(Map<String, dynamic> json) => AdminApplicant(
    email: adminOptionalString(json, 'email'),
    firstNameAr: adminOptionalString(json, 'first_name_ar'),
    lastNameAr: adminOptionalString(json, 'last_name_ar'),
    firstNameEn: adminOptionalString(json, 'first_name_en'),
    lastNameEn: adminOptionalString(json, 'last_name_en'),
  );
}

/// One row of `GET /api/admin/doctor-applications`, shaped by `adminDto`
/// (`backend/src/services/doctorApplication.service.js:4`).
class AdminDoctorApplication {
  const AdminDoctorApplication({
    required this.id,
    required this.userId,
    required this.status,
    required this.statusValue,
    required this.submittedAt,
    required this.medicalLicenseNumber,
    required this.applicant,
    this.specialtyNameAr,
    this.specialtyNameEn,
    this.subSpecialty,
    this.yearsOfExperience,
    this.education = const [],
    this.certifications = const [],
    this.bio,
    this.bioAr,
    this.bioEn,
    this.reviewedAt,
    this.rejectionReason,
    this.approvedDoctorId,
  });

  final String id;
  final String userId;
  final AdminApplicationStatus status;

  /// The raw server value, so an unrecognized status is shown rather than
  /// silently mapped onto one of the four known ones.
  final String statusValue;
  final DateTime submittedAt;
  final String medicalLicenseNumber;
  final AdminApplicant applicant;
  final String? specialtyNameAr;
  final String? specialtyNameEn;
  final String? subSpecialty;
  final int? yearsOfExperience;
  final List<String> education;
  final List<String> certifications;
  final String? bio;
  final String? bioAr;
  final String? bioEn;
  final DateTime? reviewedAt;
  final String? rejectionReason;
  final String? approvedDoctorId;

  bool get isPending => status == AdminApplicationStatus.pending;

  String specialtyName({required bool isArabic}) => localizedField(
    isArabic: isArabic,
    ar: specialtyNameAr,
    en: specialtyNameEn,
  );

  String? resolvedBio({required bool isArabic}) {
    if (bio != null && bio!.isNotEmpty) return bio;
    final localized = localizedField(isArabic: isArabic, ar: bioAr, en: bioEn);
    return localized.isEmpty ? null : localized;
  }

  factory AdminDoctorApplication.fromJson(Map<String, dynamic> json) {
    final statusValue = adminRequireString(json, 'status');
    final specialty = adminOptionalMap(json['specialty']);
    return AdminDoctorApplication(
      id: adminRequireString(json, 'id'),
      userId: adminRequireString(json, 'user_id'),
      status: adminApplicationStatusFromWire(statusValue),
      statusValue: statusValue,
      submittedAt: adminRequireDate(json, 'submitted_at'),
      medicalLicenseNumber: adminRequireString(json, 'medical_license_number'),
      applicant: AdminApplicant.fromJson(adminOptionalMap(json['applicant'])),
      specialtyNameAr: adminOptionalString(specialty, 'name_ar'),
      specialtyNameEn: adminOptionalString(specialty, 'name_en'),
      subSpecialty: adminOptionalString(json, 'sub_specialty'),
      yearsOfExperience: adminOptionalInt(json['years_of_experience']),
      education: _stringList(json['education']),
      certifications: _stringList(json['certifications']),
      bio: adminOptionalString(json, 'bio'),
      bioAr: adminOptionalString(json, 'bio_ar'),
      bioEn: adminOptionalString(json, 'bio_en'),
      reviewedAt: adminOptionalDate(json['reviewed_at']),
      rejectionReason: adminOptionalString(json, 'rejection_reason'),
      approvedDoctorId: adminOptionalString(json, 'approved_doctor_id'),
    );
  }
}

/// `education` / `certifications` are `TEXT[]` columns. A non-string element
/// is a malformed record — an application review must not quietly drop a
/// credential line the reviewer is deciding on.
List<String> _stringList(Object? value) {
  if (value == null) return const [];
  if (value is! List) {
    throw const FormatException('Malformed credential list.');
  }
  final items = <String>[];
  for (final item in value) {
    if (item is! String) {
      throw const FormatException('Malformed credential list.');
    }
    final trimmed = item.trim();
    if (trimmed.isNotEmpty) items.add(trimmed);
  }
  return List.unmodifiable(items);
}

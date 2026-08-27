class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.role,
    required this.isActive,
    this.firstName,
    this.lastName,
  });
  final String id;
  final String email;
  final String role;
  final bool isActive;
  final String? firstName;
  final String? lastName;
  String get displayName {
    final name = [
      firstName,
      lastName,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' ');
    return name.isEmpty ? email : name;
  }

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: '${json['id'] ?? ''}',
    email: '${json['email'] ?? ''}',
    role: '${json['role'] ?? ''}',
    isActive: json['is_active'] == true,
    firstName: json['first_name_en']?.toString(),
    lastName: json['last_name_en']?.toString(),
  );
}

class DoctorApplication {
  const DoctorApplication({
    required this.id,
    required this.status,
    required this.email,
    required this.name,
    required this.specialty,
    this.license,
  });
  final String id;
  final String status;
  final String email;
  final String name;
  final String specialty;
  final String? license;
  factory DoctorApplication.fromJson(
    Map<String, dynamic> json, {
    required bool isArabic,
  }) {
    final applicant = json['applicant'] is Map
        ? Map<String, dynamic>.from(json['applicant'] as Map)
        : const <String, dynamic>{};
    final specialty = json['specialty'] is Map
        ? Map<String, dynamic>.from(json['specialty'] as Map)
        : const <String, dynamic>{};
    final first =
        (isArabic ? applicant['first_name_ar'] : applicant['first_name_en']) ??
        applicant['first_name_en'] ??
        applicant['first_name_ar'];
    final last =
        (isArabic ? applicant['last_name_ar'] : applicant['last_name_en']) ??
        applicant['last_name_en'] ??
        applicant['last_name_ar'];
    return DoctorApplication(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? ''}',
      email: '${applicant['email'] ?? ''}',
      name: [
        first,
        last,
      ].where((value) => value != null && '$value'.trim().isNotEmpty).join(' '),
      specialty:
          '${(isArabic ? specialty['name_ar'] : specialty['name_en']) ?? specialty['name_en'] ?? specialty['name_ar'] ?? ''}',
      license: json['medical_license_number']?.toString(),
    );
  }
}

class AdminInvitation {
  const AdminInvitation({
    required this.id,
    required this.email,
    required this.status,
  });
  final String id;
  final String email;
  final String status;
  factory AdminInvitation.fromJson(Map<String, dynamic> json) =>
      AdminInvitation(
        id: '${json['id'] ?? ''}',
        email: '${json['email'] ?? ''}',
        status: '${json['status'] ?? ''}',
      );
}

/// Read-only, non-clinical metadata returned by the administration activity
/// endpoint. No notes, diagnoses, medication instructions, or attachments are
/// included in this model.
class AdminActivityItem {
  const AdminActivityItem({
    required this.id,
    required this.reference,
    required this.status,
    required this.occurredOn,
    required this.patientEmail,
    required this.doctorEmail,
    this.detail,
  });
  final String id;
  final String reference;
  final String status;
  final String occurredOn;
  final String patientEmail;
  final String doctorEmail;
  final String? detail;

  factory AdminActivityItem.fromJson(Map<String, dynamic> json) =>
      AdminActivityItem(
        id: '${json['id'] ?? ''}',
        reference: '${json['reference'] ?? ''}',
        status: '${json['status'] ?? ''}',
        occurredOn: '${json['occurred_on'] ?? ''}',
        patientEmail: '${json['patient_email'] ?? ''}',
        doctorEmail: '${json['doctor_email'] ?? ''}',
        detail: json['detail']?.toString(),
      );
}

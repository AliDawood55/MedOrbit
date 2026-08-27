class DoctorPatient {
  const DoctorPatient({
    required this.id,
    required this.email,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.phone,
    this.hasUpcoming = false,
  });
  final String id;
  final String email;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? phone;
  final bool hasUpcoming;
  String name(bool ar) {
    final values = ar ? [firstNameAr, lastNameAr] : [firstNameEn, lastNameEn];
    final fallback = ar ? [firstNameEn, lastNameEn] : [firstNameAr, lastNameAr];
    final value = values
        .whereType<String>()
        .where((v) => v.trim().isNotEmpty)
        .join(' ');
    return value.isEmpty
        ? fallback
              .whereType<String>()
              .where((v) => v.trim().isNotEmpty)
              .join(' ')
        : value;
  }

  factory DoctorPatient.fromJson(Map<String, dynamic> json) => DoctorPatient(
    id: '${json['id'] ?? ''}',
    email: '${json['email'] ?? ''}',
    firstNameAr: json['first_name_ar']?.toString(),
    lastNameAr: json['last_name_ar']?.toString(),
    firstNameEn: json['first_name_en']?.toString(),
    lastNameEn: json['last_name_en']?.toString(),
    phone: json['phone']?.toString(),
    hasUpcoming: json['has_upcoming'] == true,
  );
}

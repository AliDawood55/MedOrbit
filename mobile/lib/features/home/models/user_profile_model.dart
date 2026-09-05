import '../../../shared/utils/localized_field.dart';

/// `GET /users/me` (`backend/src/routes/user.routes.js:25-84`).
///
/// Covers every field that endpoint returns — home only renders a subset
/// (name/avatar), the profile screen renders the rest (phone/gender/address/
/// city/preferredLanguage/createdAt).
class UserProfileModel {
  const UserProfileModel({
    required this.id,
    required this.email,
    required this.role,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.avatarUrl,
    this.phone,
    this.gender,
    this.address,
    this.city,
    this.preferredLanguage,
    this.createdAt,
    this.socialLinks = const {},
  });

  final String id;
  final String email;
  final String role;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? avatarUrl;
  final String? phone;

  /// `'male' | 'female' | 'other'` per the DB check constraint — not enforced
  /// client-side beyond offering those three choices.
  final String? gender;
  final String? address;
  final String? city;

  /// `'ar' | 'en'` by convention; the backend does not constrain this column.
  final String? preferredLanguage;
  final DateTime? createdAt;

  /// Public contact links returned as `social_links` from `/users/me`.
  /// Values are backend-validated HTTPS URLs except WhatsApp, which is an
  /// international number stored without punctuation.
  final Map<String, String> socialLinks;

  String displayName(bool isArabic) {
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
    final full = '$first $last'.trim();
    return full.isEmpty ? email : full;
  }

  String get initial {
    final source = firstNameEn ?? firstNameAr ?? email;
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id'].toString(),
      email: json['email'] as String,
      role: json['role'] as String,
      firstNameAr: json['first_name_ar'] as String?,
      lastNameAr: json['last_name_ar'] as String?,
      firstNameEn: json['first_name_en'] as String?,
      lastNameEn: json['last_name_en'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      phone: json['phone'] as String?,
      gender: json['gender'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      preferredLanguage: json['preferred_language'] as String?,
      createdAt: json['created_at'] is String
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      socialLinks: _socialLinks(json['social_links']),
    );
  }
}

Map<String, String> _socialLinks(Object? value) {
  if (value is! Map) return const {};
  return Map.unmodifiable(
    Map<String, String>.fromEntries(
      value.entries
          .where((entry) => entry.key is String && entry.value is String)
          .map(
            (entry) =>
                MapEntry(entry.key as String, (entry.value as String).trim()),
          )
          .where((entry) => entry.value.isNotEmpty),
    ),
  );
}

import '../../home/models/user_profile_model.dart';

/// The editable subset of a profile, matching `PUT /users/me`'s payload
/// shape exactly (`firstNameAr`, `lastNameAr`, `firstNameEn`, `lastNameEn`,
/// `phone`, `gender`, `address`, `city` — camelCase on the wire, unlike the
/// snake_case `GET /users/me` response `UserProfileModel` parses).
///
/// Separate from [UserProfileModel] because that one is a read-only server
/// snapshot (also carries `id`/`email`/`role`/`avatarUrl`/etc., none of
/// which this endpoint accepts), while this is the mutable form draft.
class ProfileEditModel {
  const ProfileEditModel({
    required this.firstNameAr,
    required this.lastNameAr,
    required this.firstNameEn,
    required this.lastNameEn,
    this.phone = '',
    this.gender,
    this.address = '',
    this.city = '',
  });

  final String firstNameAr;
  final String lastNameAr;
  final String firstNameEn;
  final String lastNameEn;
  final String phone;

  /// `'male' | 'female' | 'other'`, or null if not set.
  final String? gender;
  final String address;
  final String city;

  factory ProfileEditModel.fromProfile(UserProfileModel profile) {
    return ProfileEditModel(
      firstNameAr: profile.firstNameAr ?? '',
      lastNameAr: profile.lastNameAr ?? '',
      firstNameEn: profile.firstNameEn ?? '',
      lastNameEn: profile.lastNameEn ?? '',
      phone: profile.phone ?? '',
      gender: profile.gender,
      address: profile.address ?? '',
      city: profile.city ?? '',
    );
  }

  ProfileEditModel copyWith({
    String? firstNameAr,
    String? lastNameAr,
    String? firstNameEn,
    String? lastNameEn,
    String? phone,
    String? gender,
    bool clearGender = false,
    String? address,
    String? city,
  }) {
    return ProfileEditModel(
      firstNameAr: firstNameAr ?? this.firstNameAr,
      lastNameAr: lastNameAr ?? this.lastNameAr,
      firstNameEn: firstNameEn ?? this.firstNameEn,
      lastNameEn: lastNameEn ?? this.lastNameEn,
      phone: phone ?? this.phone,
      gender: clearGender ? null : (gender ?? this.gender),
      address: address ?? this.address,
      city: city ?? this.city,
    );
  }

  /// `PUT /users/me` request body — exact field names the backend reads.
  Map<String, dynamic> toJson() {
    return {
      'firstNameAr': firstNameAr.trim(),
      'lastNameAr': lastNameAr.trim(),
      'firstNameEn': firstNameEn.trim(),
      'lastNameEn': lastNameEn.trim(),
      'phone': phone.trim(),
      'gender': gender,
      'address': address.trim(),
      'city': city.trim(),
    };
  }
}

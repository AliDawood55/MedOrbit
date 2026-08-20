import 'doctor_models.dart';

class ClinicListResponse {
  const ClinicListResponse({this.clinics = const [], this.pagination, this.extra = const {}});

  final List<Clinic> clinics;
  final ClinicPagination? pagination;
  final Map<String, dynamic> extra;

  factory ClinicListResponse.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    final pagination = _asMap(data['pagination']);
    return ClinicListResponse(
      clinics: _list(data['clinics']).map(Clinic.fromJson).toList(),
      pagination: pagination == null ? null : ClinicPagination.fromJson(pagination),
      extra: _extra(data, const {'clinics', 'pagination'}),
    );
  }
}

class NearbyClinicResponse {
  const NearbyClinicResponse({this.clinics = const [], this.extra = const {}});

  final List<Clinic> clinics;
  final Map<String, dynamic> extra;

  factory NearbyClinicResponse.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    return NearbyClinicResponse(
      clinics: _list(data['clinics']).map(Clinic.fromJson).toList(),
      extra: _extra(data, const {'clinics'}),
    );
  }
}

class ClinicDetailResponse {
  const ClinicDetailResponse({this.clinic, this.doctors = const [], this.extra = const {}});

  final Clinic? clinic;
  final List<ClinicDoctorSummary> doctors;
  final Map<String, dynamic> extra;

  factory ClinicDetailResponse.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    final clinic = _asMap(data['clinic']);
    return ClinicDetailResponse(
      clinic: clinic == null ? null : Clinic.fromJson(clinic),
      doctors: _list(data['doctors']).map(ClinicDoctorSummary.fromJson).toList(),
      extra: _extra(data, const {'clinic', 'doctors'}),
    );
  }
}

class Clinic {
  const Clinic({
    required this.id,
    this.nameAr,
    this.nameEn,
    this.addressAr,
    this.addressEn,
    this.city,
    this.region,
    this.latitude,
    this.longitude,
    this.phone,
    this.email,
    this.website,
    this.operatingHours,
    this.services = const [],
    this.insuranceAccepted = const [],
    this.images = const [],
    this.logoUrl,
    this.type,
    this.verificationStatus = ClinicVerificationStatus.unknown,
    this.verificationStatusValue,
    this.isActive,
    this.distanceKm,
    this.averageRating,
    this.rating,
    this.extra = const {},
  });

  final String id;
  final String? nameAr;
  final String? nameEn;
  final String? addressAr;
  final String? addressEn;
  final String? city;
  final String? region;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? email;
  final String? website;
  final ClinicOperatingHours? operatingHours;
  final List<String> services;
  final List<String> insuranceAccepted;
  final List<String> images;
  final String? logoUrl;
  final String? type;
  final ClinicVerificationStatus verificationStatus;
  final String? verificationStatusValue;
  final bool? isActive;
  final double? distanceKm;
  final double? averageRating;
  final double? rating;
  final Map<String, dynamic> extra;

  factory Clinic.fromJson(Map<String, dynamic> json) {
    final status = _asString(_read(json, 'verification_status', 'verificationStatus'));
    final operatingHours = _asMap(_read(json, 'operating_hours', 'operatingHours'));
    return Clinic(
      id: _asString(json['id']) ?? '',
      nameAr: _asString(_read(json, 'name_ar', 'nameAr')),
      nameEn: _asString(_read(json, 'name_en', 'nameEn')) ?? _asString(json['name']),
      addressAr: _asString(_read(json, 'address_ar', 'addressAr')),
      addressEn: _asString(_read(json, 'address_en', 'addressEn')) ?? _asString(json['address']),
      city: _asString(json['city']),
      region: _asString(json['region']),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      phone: _asString(json['phone']),
      email: _asString(json['email']),
      website: _asString(json['website']),
      operatingHours: operatingHours == null ? null : ClinicOperatingHours.fromJson(operatingHours),
      services: _stringList(json['services']),
      insuranceAccepted: _stringList(_read(json, 'insurance_accepted', 'insuranceAccepted')),
      images: _stringList(json['images']),
      logoUrl: _asString(_read(json, 'logo_url', 'logoUrl')),
      type: _asString(json['type']),
      verificationStatus: ClinicVerificationStatus.fromJson(status),
      verificationStatusValue: status,
      isActive: _asBool(_read(json, 'is_active', 'isActive')),
      distanceKm: _asDouble(_read(json, 'distance_km', 'distanceKm')),
      averageRating: _asDouble(_read(json, 'average_rating', 'averageRating')),
      rating: _asDouble(json['rating']),
      extra: _extra(json, const {
        'id',
        'name_ar',
        'nameAr',
        'name_en',
        'nameEn',
        'name',
        'address_ar',
        'addressAr',
        'address_en',
        'addressEn',
        'address',
        'city',
        'region',
        'latitude',
        'longitude',
        'phone',
        'email',
        'website',
        'operating_hours',
        'operatingHours',
        'services',
        'insurance_accepted',
        'insuranceAccepted',
        'images',
        'logo_url',
        'logoUrl',
        'type',
        'verification_status',
        'verificationStatus',
        'is_active',
        'isActive',
        'distance_km',
        'distanceKm',
        'average_rating',
        'averageRating',
        'rating',
      }),
    );
  }

  Map<String, dynamic> toJson() => {
    ..._copyMap(extra),
    'id': id,
    if (nameAr != null) 'name_ar': nameAr,
    if (nameEn != null) 'name_en': nameEn,
    if (addressAr != null) 'address_ar': addressAr,
    if (addressEn != null) 'address_en': addressEn,
    if (city != null) 'city': city,
    if (region != null) 'region': region,
    if (latitude != null) 'latitude': latitude,
    if (longitude != null) 'longitude': longitude,
    if (phone != null) 'phone': phone,
    if (email != null) 'email': email,
    if (website != null) 'website': website,
    if (operatingHours != null) 'operating_hours': operatingHours!.toJson(),
    'services': List<String>.from(services),
    'insurance_accepted': List<String>.from(insuranceAccepted),
    'images': List<String>.from(images),
    if (logoUrl != null) 'logo_url': logoUrl,
    if (type != null) 'type': type,
    if (verificationStatusValue != null) 'verification_status': verificationStatusValue,
    if (isActive != null) 'is_active': isActive,
    if (distanceKm != null) 'distance_km': distanceKm,
    if (averageRating != null) 'average_rating': averageRating,
    if (rating != null) 'rating': rating,
  };
}

enum ClinicVerificationStatus {
  pending,
  verified,
  rejected,
  suspended,
  unknown;

  static ClinicVerificationStatus fromJson(String? value) {
    return switch (value) {
      'pending' => ClinicVerificationStatus.pending,
      'verified' => ClinicVerificationStatus.verified,
      'rejected' => ClinicVerificationStatus.rejected,
      'suspended' => ClinicVerificationStatus.suspended,
      _ => ClinicVerificationStatus.unknown,
    };
  }
}

class ClinicOperatingHours {
  const ClinicOperatingHours({this.days = const {}, this.extra = const {}});

  final Map<String, ClinicDayHours> days;
  final Map<String, dynamic> extra;

  factory ClinicOperatingHours.fromJson(Map<String, dynamic> json) {
    final days = <String, ClinicDayHours>{};
    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is Map) {
        days[entry.key] = ClinicDayHours.fromJson(Map<String, dynamic>.from(value));
      } else {
        extra[entry.key] = value;
      }
    }
    return ClinicOperatingHours(days: days, extra: extra);
  }

  Map<String, dynamic> toJson() {
    return {
      ..._copyMap(extra),
      for (final entry in days.entries) entry.key: entry.value.toJson(),
    };
  }
}

class ClinicDayHours {
  const ClinicDayHours({this.open, this.close, this.isClosed, this.extra = const {}});

  final String? open;
  final String? close;
  final bool? isClosed;
  final Map<String, dynamic> extra;

  factory ClinicDayHours.fromJson(Map<String, dynamic> json) {
    return ClinicDayHours(
      open: _asString(json['open']),
      close: _asString(json['close']),
      isClosed: _asBool(_read(json, 'is_closed', 'isClosed')),
      extra: _extra(json, const {'open', 'close', 'is_closed', 'isClosed'}),
    );
  }

  Map<String, dynamic> toJson() => {
    ..._copyMap(extra),
    if (open != null) 'open': open,
    if (close != null) 'close': close,
    if (isClosed != null) 'is_closed': isClosed,
  };
}

class ClinicDoctorSummary {
  const ClinicDoctorSummary({
    required this.id,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.specialtyAr,
    this.specialtyEn,
    this.consultationFee,
    this.averageRating,
    this.isAcceptingPatients,
    this.extra = const {},
  });

  final String id;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? specialtyAr;
  final String? specialtyEn;
  final double? consultationFee;
  final double? averageRating;
  final bool? isAcceptingPatients;
  final Map<String, dynamic> extra;

  factory ClinicDoctorSummary.fromJson(Map<String, dynamic> json) {
    return ClinicDoctorSummary(
      id: _asString(json['id']) ?? '',
      firstNameAr: _asString(_read(json, 'first_name_ar', 'firstNameAr')),
      lastNameAr: _asString(_read(json, 'last_name_ar', 'lastNameAr')),
      firstNameEn: _asString(_read(json, 'first_name_en', 'firstNameEn')),
      lastNameEn: _asString(_read(json, 'last_name_en', 'lastNameEn')),
      specialtyAr: _asString(_read(json, 'specialty_ar', 'specialtyAr')),
      specialtyEn: _asString(_read(json, 'specialty_en', 'specialtyEn')),
      consultationFee: _asDouble(_read(json, 'consultation_fee', 'consultationFee')),
      averageRating: _asDouble(_read(json, 'average_rating', 'averageRating')),
      isAcceptingPatients: _asBool(_read(json, 'is_accepting_patients', 'isAcceptingPatients')),
      extra: _extra(json, const {
        'id',
        'first_name_ar',
        'firstNameAr',
        'last_name_ar',
        'lastNameAr',
        'first_name_en',
        'firstNameEn',
        'last_name_en',
        'lastNameEn',
        'specialty_ar',
        'specialtyAr',
        'specialty_en',
        'specialtyEn',
        'consultation_fee',
        'consultationFee',
        'average_rating',
        'averageRating',
        'is_accepting_patients',
        'isAcceptingPatients',
      }),
    );
  }

  factory ClinicDoctorSummary.fromDoctor(Doctor doctor) {
    return ClinicDoctorSummary(
      id: doctor.id,
      firstNameAr: doctor.firstNameAr,
      lastNameAr: doctor.lastNameAr,
      firstNameEn: doctor.firstNameEn,
      lastNameEn: doctor.lastNameEn,
      specialtyAr: doctor.specialtyAr,
      specialtyEn: doctor.specialtyEn,
      consultationFee: doctor.consultationFee,
      averageRating: doctor.averageRating,
      isAcceptingPatients: doctor.isAcceptingPatients,
      extra: doctor.extra,
    );
  }
}

class ClinicPagination {
  const ClinicPagination({this.page, this.limit, this.total, this.totalPages, this.hasNext, this.hasPrevious, this.extra = const {}});

  final int? page;
  final int? limit;
  final int? total;
  final int? totalPages;
  final bool? hasNext;
  final bool? hasPrevious;
  final Map<String, dynamic> extra;

  factory ClinicPagination.fromJson(Map<String, dynamic> json) {
    return ClinicPagination(
      page: _asInt(json['page']),
      limit: _asInt(json['limit']),
      total: _asInt(json['total']),
      totalPages: _asInt(_read(json, 'total_pages', 'totalPages')),
      hasNext: _asBool(_read(json, 'has_next', 'hasNext')),
      hasPrevious: _asBool(_read(json, 'has_previous', 'hasPrevious')),
      extra: _extra(json, const {'page', 'limit', 'total', 'total_pages', 'totalPages', 'has_next', 'hasNext', 'has_previous', 'hasPrevious'}),
    );
  }
}

Map<String, dynamic> _payload(Map<String, dynamic> json) => _asMap(json['data']) ?? json;

Object? _read(Map<String, dynamic> json, String snake, String camel) => json.containsKey(snake) ? json[snake] : json[camel];

Map<String, dynamic>? _asMap(Object? value) => value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.where((item) => item != null).map((item) => item.toString()).toList();
}

String? _asString(Object? value) => value?.toString();

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value == '1') return true;
    if (value == '0') return false;
    return bool.tryParse(value);
  }
  if (value is num) return value != 0;
  return null;
}

Map<String, dynamic> _extra(Map<String, dynamic> json, Set<String> known) {
  return _copyMap(Map<String, dynamic>.fromEntries(json.entries.where((entry) => !known.contains(entry.key))));
}

Map<String, dynamic> _copyMap(Map<String, dynamic> value) {
  return value.map((key, item) => MapEntry(key, _copyValue(item)));
}

Object? _copyValue(Object? value) {
  if (value is Map) return _copyMap(Map<String, dynamic>.from(value));
  if (value is List) return value.map(_copyValue).toList();
  return value;
}

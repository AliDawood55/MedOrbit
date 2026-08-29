import '../../../shared/utils/json_parsing.dart';

class DoctorListResponse {
  const DoctorListResponse({
    this.doctors = const [],
    this.pagination,
    this.extra = const {},
  });

  final List<Doctor> doctors;
  final DoctorPagination? pagination;
  final Map<String, dynamic> extra;

  factory DoctorListResponse.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    final pagination = _asMap(data['pagination']);
    return DoctorListResponse(
      doctors: _list(data['doctors']).map(Doctor.fromJson).toList(),
      pagination: pagination == null
          ? null
          : DoctorPagination.fromJson(pagination),
      extra: _extra(data, const {'doctors', 'pagination'}),
    );
  }
}

class DoctorDetailResponse {
  const DoctorDetailResponse({
    this.doctor,
    this.clinics = const [],
    this.availability = const [],
    this.reviews = const [],
    this.extra = const {},
  });

  final Doctor? doctor;
  final List<DoctorClinicSummary> clinics;
  final List<DoctorAvailabilitySlot> availability;
  final List<DoctorReview> reviews;
  final Map<String, dynamic> extra;

  factory DoctorDetailResponse.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    final doctor = _asMap(data['doctor']);
    return DoctorDetailResponse(
      doctor: doctor == null ? null : Doctor.fromJson(doctor),
      clinics: _list(
        data['clinics'],
      ).map(DoctorClinicSummary.fromJson).toList(),
      availability: _list(
        data['availability'],
      ).map(DoctorAvailabilitySlot.fromJson).toList(),
      reviews: _list(data['reviews']).map(DoctorReview.fromJson).toList(),
      extra: _extra(data, const {
        'doctor',
        'clinics',
        'availability',
        'reviews',
      }),
    );
  }
}

class DoctorAvailabilityResponse {
  const DoctorAvailabilityResponse({
    this.slots = const [],
    this.extra = const {},
  });

  final List<DoctorAvailabilitySlot> slots;
  final Map<String, dynamic> extra;

  factory DoctorAvailabilityResponse.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    return DoctorAvailabilityResponse(
      slots: _list(data['slots']).map(DoctorAvailabilitySlot.fromJson).toList(),
      extra: _extra(data, const {'slots'}),
    );
  }
}

class Doctor {
  const Doctor({
    required this.id,
    this.userId,
    this.medicalLicenseNumber,
    this.yearsOfExperience,
    this.consultationFee,
    this.consultationDuration,
    this.averageRating,
    this.totalRatings,
    this.isAcceptingPatients,
    this.education = const [],
    this.certifications = const [],
    this.areasOfExpertise = const [],
    this.professionalInterests = const [],
    this.languagesSpoken = const [],
    this.professionalHeadline,
    this.subSpecialty,
    this.profileImageUrl,
    this.professionalBio,
    this.professionalBioAr,
    this.professionalBioEn,
    this.email,
    this.firstNameAr,
    this.lastNameAr,
    this.firstNameEn,
    this.lastNameEn,
    this.specialtyId,
    this.specialtyAr,
    this.specialtyEn,
    this.specialtyNameAr,
    this.specialtyNameEn,
    this.clinics = const [],
    this.availability = const [],
    this.reviews = const [],
    this.createdAt,
    this.extra = const {},
  });

  final String id;
  final String? userId;
  final String? medicalLicenseNumber;
  final int? yearsOfExperience;
  final double? consultationFee;
  final int? consultationDuration;
  final double? averageRating;
  final int? totalRatings;
  final bool? isAcceptingPatients;
  final List<String> education;
  final List<String> certifications;
  final List<String> areasOfExpertise;
  final List<String> professionalInterests;
  final List<String> languagesSpoken;
  final String? professionalHeadline;
  final String? subSpecialty;
  final String? profileImageUrl;
  final String? professionalBio;
  final String? professionalBioAr;
  final String? professionalBioEn;
  final String? email;
  final String? firstNameAr;
  final String? lastNameAr;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? specialtyId;
  final String? specialtyAr;
  final String? specialtyEn;
  final String? specialtyNameAr;
  final String? specialtyNameEn;
  final List<DoctorClinicSummary> clinics;
  final List<DoctorAvailabilitySlot> availability;
  final List<DoctorReview> reviews;
  final DateTime? createdAt;
  final Map<String, dynamic> extra;

  factory Doctor.fromJson(Map<String, dynamic> json) {
    return Doctor(
      id: requireExactString(json, 'id'),
      userId: _asString(_read(json, 'user_id', 'userId')),
      medicalLicenseNumber: _asString(
        _read(json, 'medical_license_number', 'medicalLicenseNumber'),
      ),
      yearsOfExperience: _asInt(
        _read(json, 'years_of_experience', 'yearsOfExperience'),
      ),
      consultationFee: _asDouble(
        _read(json, 'consultation_fee', 'consultationFee'),
      ),
      consultationDuration: _asInt(
        _read(json, 'consultation_duration', 'consultationDuration'),
      ),
      averageRating: _asDouble(_read(json, 'average_rating', 'averageRating')),
      totalRatings: _asInt(_read(json, 'total_ratings', 'totalRatings')),
      isAcceptingPatients: _asBool(
        _read(json, 'is_accepting_patients', 'isAcceptingPatients'),
      ),
      education: _stringList(json['education']),
      certifications: _stringList(json['certifications']),
      areasOfExpertise: _stringList(
        _read(json, 'areas_of_expertise', 'areasOfExpertise'),
      ),
      professionalInterests: _stringList(
        _read(json, 'professional_interests', 'professionalInterests'),
      ),
      languagesSpoken: _stringList(
        _read(json, 'languages_spoken', 'languagesSpoken'),
      ),
      professionalHeadline: _asString(
        _read(json, 'professional_headline', 'professionalHeadline'),
      ),
      subSpecialty: _asString(_read(json, 'sub_specialty', 'subSpecialty')),
      profileImageUrl: _asString(
        _read(json, 'profile_image_url', 'profileImageUrl'),
      ),
      professionalBio: _asString(
        _read(json, 'professional_bio', 'professionalBio'),
      ),
      professionalBioAr: _asString(
        _read(json, 'professional_bio_ar', 'professionalBioAr'),
      ),
      professionalBioEn: _asString(
        _read(json, 'professional_bio_en', 'professionalBioEn'),
      ),
      email: _asString(json['email']),
      firstNameAr: _asString(_read(json, 'first_name_ar', 'firstNameAr')),
      lastNameAr: _asString(_read(json, 'last_name_ar', 'lastNameAr')),
      firstNameEn: _asString(_read(json, 'first_name_en', 'firstNameEn')),
      lastNameEn: _asString(_read(json, 'last_name_en', 'lastNameEn')),
      specialtyId: _asString(_read(json, 'specialty_id', 'specialtyId')),
      specialtyAr: _asString(_read(json, 'specialty_ar', 'specialtyAr')),
      specialtyEn: _asString(_read(json, 'specialty_en', 'specialtyEn')),
      specialtyNameAr: _asString(
        _read(json, 'specialty_name_ar', 'specialtyNameAr'),
      ),
      specialtyNameEn: _asString(
        _read(json, 'specialty_name_en', 'specialtyNameEn'),
      ),
      clinics: _list(
        json['clinics'],
      ).map(DoctorClinicSummary.fromJson).toList(),
      availability: _list(
        json['availability'],
      ).map(DoctorAvailabilitySlot.fromJson).toList(),
      reviews: _list(json['reviews']).map(DoctorReview.fromJson).toList(),
      createdAt: _asDate(_read(json, 'created_at', 'createdAt')),
      extra: _extra(json, const {
        'id',
        'user_id',
        'userId',
        'medical_license_number',
        'medicalLicenseNumber',
        'years_of_experience',
        'yearsOfExperience',
        'consultation_fee',
        'consultationFee',
        'consultation_duration',
        'consultationDuration',
        'average_rating',
        'averageRating',
        'total_ratings',
        'totalRatings',
        'is_accepting_patients',
        'isAcceptingPatients',
        'education',
        'certifications',
        'areas_of_expertise',
        'areasOfExpertise',
        'professional_interests',
        'professionalInterests',
        'languages_spoken',
        'languagesSpoken',
        'professional_headline',
        'professionalHeadline',
        'sub_specialty',
        'subSpecialty',
        'profile_image_url',
        'profileImageUrl',
        'professional_bio',
        'professionalBio',
        'professional_bio_ar',
        'professionalBioAr',
        'professional_bio_en',
        'professionalBioEn',
        'email',
        'first_name_ar',
        'firstNameAr',
        'last_name_ar',
        'lastNameAr',
        'first_name_en',
        'firstNameEn',
        'last_name_en',
        'lastNameEn',
        'specialty_id',
        'specialtyId',
        'specialty_ar',
        'specialtyAr',
        'specialty_en',
        'specialtyEn',
        'specialty_name_ar',
        'specialtyNameAr',
        'specialty_name_en',
        'specialtyNameEn',
        'clinics',
        'availability',
        'reviews',
        'created_at',
        'createdAt',
      }),
    );
  }

  Map<String, dynamic> toJson() => {
    ..._copyMap(extra),
    'id': id,
    if (userId != null) 'user_id': userId,
    if (medicalLicenseNumber != null)
      'medical_license_number': medicalLicenseNumber,
    if (yearsOfExperience != null) 'years_of_experience': yearsOfExperience,
    if (consultationFee != null) 'consultation_fee': consultationFee,
    if (consultationDuration != null)
      'consultation_duration': consultationDuration,
    if (averageRating != null) 'average_rating': averageRating,
    if (totalRatings != null) 'total_ratings': totalRatings,
    if (isAcceptingPatients != null)
      'is_accepting_patients': isAcceptingPatients,
    'education': List<String>.from(education),
    'certifications': List<String>.from(certifications),
    if (areasOfExpertise.isNotEmpty)
      'areas_of_expertise': List<String>.from(areasOfExpertise),
    if (professionalInterests.isNotEmpty)
      'professional_interests': List<String>.from(professionalInterests),
    if (languagesSpoken.isNotEmpty)
      'languages_spoken': List<String>.from(languagesSpoken),
    if (professionalHeadline != null)
      'professional_headline': professionalHeadline,
    if (subSpecialty != null) 'sub_specialty': subSpecialty,
    if (profileImageUrl != null) 'profile_image_url': profileImageUrl,
    if (professionalBio != null) 'professional_bio': professionalBio,
    if (professionalBioAr != null) 'professional_bio_ar': professionalBioAr,
    if (professionalBioEn != null) 'professional_bio_en': professionalBioEn,
    if (email != null) 'email': email,
    if (firstNameAr != null) 'first_name_ar': firstNameAr,
    if (lastNameAr != null) 'last_name_ar': lastNameAr,
    if (firstNameEn != null) 'first_name_en': firstNameEn,
    if (lastNameEn != null) 'last_name_en': lastNameEn,
    if (specialtyId != null) 'specialty_id': specialtyId,
    if (specialtyAr != null) 'specialty_ar': specialtyAr,
    if (specialtyEn != null) 'specialty_en': specialtyEn,
    if (specialtyNameAr != null) 'specialty_name_ar': specialtyNameAr,
    if (specialtyNameEn != null) 'specialty_name_en': specialtyNameEn,
    'clinics': clinics.map((clinic) => clinic.toJson()).toList(),
    'availability': availability.map((slot) => slot.toJson()).toList(),
    'reviews': reviews.map((review) => review.toJson()).toList(),
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

class DoctorClinicSummary {
  const DoctorClinicSummary({
    required this.id,
    this.nameAr,
    this.nameEn,
    this.addressAr,
    this.addressEn,
    this.city,
    this.region,
    this.latitude,
    this.longitude,
    this.distanceKm,
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
  final double? distanceKm;
  final Map<String, dynamic> extra;

  factory DoctorClinicSummary.fromJson(Map<String, dynamic> json) {
    return DoctorClinicSummary(
      id: requireExactString(json, 'id'),
      nameAr: _asString(_read(json, 'name_ar', 'nameAr')),
      nameEn:
          _asString(_read(json, 'name_en', 'nameEn')) ??
          _asString(json['name']),
      addressAr: _asString(_read(json, 'address_ar', 'addressAr')),
      addressEn:
          _asString(_read(json, 'address_en', 'addressEn')) ??
          _asString(json['address']),
      city: _asString(json['city']),
      region: _asString(json['region']),
      latitude: _asDouble(json['latitude']),
      longitude: _asDouble(json['longitude']),
      distanceKm: _asDouble(_read(json, 'distance_km', 'distanceKm')),
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
        'distance_km',
        'distanceKm',
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
    if (distanceKm != null) 'distance_km': distanceKm,
  };
}

class DoctorAvailabilitySlot {
  const DoctorAvailabilitySlot({
    required this.id,
    this.doctorId,
    this.clinicId,
    this.date,
    this.startTime,
    this.endTime,
    this.isAvailable,
    this.status,
    this.extra = const {},
  });

  final String id;
  final String? doctorId;
  final String? clinicId;
  final DateTime? date;
  final String? startTime;
  final String? endTime;
  final bool? isAvailable;
  final String? status;
  final Map<String, dynamic> extra;

  factory DoctorAvailabilitySlot.fromJson(Map<String, dynamic> json) {
    return DoctorAvailabilitySlot(
      id: requireExactString(json, 'id'),
      doctorId: _asString(_read(json, 'doctor_id', 'doctorId')),
      clinicId: _asString(_read(json, 'clinic_id', 'clinicId')),
      date: _asDate(json['date']),
      startTime: _asString(_read(json, 'start_time', 'startTime')),
      endTime: _asString(_read(json, 'end_time', 'endTime')),
      isAvailable: _asBool(_read(json, 'is_available', 'isAvailable')),
      status: _asString(json['status']),
      extra: _extra(json, const {
        'id',
        'doctor_id',
        'doctorId',
        'clinic_id',
        'clinicId',
        'date',
        'start_time',
        'startTime',
        'end_time',
        'endTime',
        'is_available',
        'isAvailable',
        'status',
      }),
    );
  }

  Map<String, dynamic> toJson() => {
    ..._copyMap(extra),
    'id': id,
    if (doctorId != null) 'doctor_id': doctorId,
    if (clinicId != null) 'clinic_id': clinicId,
    if (date != null) 'date': date!.toIso8601String(),
    if (startTime != null) 'start_time': startTime,
    if (endTime != null) 'end_time': endTime,
    if (isAvailable != null) 'is_available': isAvailable,
    if (status != null) 'status': status,
  };
}

class DoctorReview {
  const DoctorReview({
    required this.id,
    this.patientId,
    this.patientName,
    this.patientFirstNameAr,
    this.patientFirstNameEn,
    this.rating,
    this.comment,
    this.reviewText,
    this.reviewTextAr,
    this.reviewTextEn,
    this.createdAt,
    this.extra = const {},
  });

  final String id;
  final String? patientId;
  final String? patientName;
  final String? patientFirstNameAr;
  final String? patientFirstNameEn;
  final double? rating;

  /// Legacy generic comment field. The backend doctor-detail endpoint sends
  /// the review body as `review_text` (canonical) plus `review_text_ar` /
  /// `review_text_en`; [localizedText] resolves across all of these.
  final String? comment;
  final String? reviewText;
  final String? reviewTextAr;
  final String? reviewTextEn;
  final DateTime? createdAt;
  final Map<String, dynamic> extra;

  /// Locale-appropriate review body, mirroring the web doctor profile's
  /// `review.review_text || localized(review, 'review_text_ar', 'review_text_en')`.
  String? localizedText({required bool isArabic}) {
    final ordered = isArabic
        ? [reviewText, reviewTextAr, reviewTextEn, comment]
        : [reviewText, reviewTextEn, reviewTextAr, comment];
    for (final value in ordered) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// Locale-appropriate reviewer display name, mirroring the web profile's
  /// `localized(review, 'patient_first_name_ar', 'patient_first_name_en')`.
  /// Returns null when the backend sent no reviewer name (caller supplies a
  /// localized "Patient" fallback).
  String? reviewerName({required bool isArabic}) {
    final ordered = isArabic
        ? [patientFirstNameAr, patientFirstNameEn, patientName]
        : [patientFirstNameEn, patientFirstNameAr, patientName];
    for (final value in ordered) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  factory DoctorReview.fromJson(Map<String, dynamic> json) {
    return DoctorReview(
      id: requireExactString(json, 'id'),
      patientId: _asString(_read(json, 'patient_id', 'patientId')),
      patientName: _asString(_read(json, 'patient_name', 'patientName')),
      patientFirstNameAr: _asString(
        _read(json, 'patient_first_name_ar', 'patientFirstNameAr'),
      ),
      patientFirstNameEn: _asString(
        _read(json, 'patient_first_name_en', 'patientFirstNameEn'),
      ),
      rating: _asDouble(json['rating']),
      comment: _asString(json['comment']),
      reviewText: _asString(_read(json, 'review_text', 'reviewText')),
      reviewTextAr: _asString(_read(json, 'review_text_ar', 'reviewTextAr')),
      reviewTextEn: _asString(_read(json, 'review_text_en', 'reviewTextEn')),
      createdAt: _asDate(_read(json, 'created_at', 'createdAt')),
      extra: _extra(json, const {
        'id',
        'patient_id',
        'patientId',
        'patient_name',
        'patientName',
        'patient_first_name_ar',
        'patientFirstNameAr',
        'patient_first_name_en',
        'patientFirstNameEn',
        'rating',
        'comment',
        'review_text',
        'reviewText',
        'review_text_ar',
        'reviewTextAr',
        'review_text_en',
        'reviewTextEn',
        'created_at',
        'createdAt',
      }),
    );
  }

  Map<String, dynamic> toJson() => {
    ..._copyMap(extra),
    'id': id,
    if (patientId != null) 'patient_id': patientId,
    if (patientName != null) 'patient_name': patientName,
    if (patientFirstNameAr != null)
      'patient_first_name_ar': patientFirstNameAr,
    if (patientFirstNameEn != null)
      'patient_first_name_en': patientFirstNameEn,
    if (rating != null) 'rating': rating,
    if (comment != null) 'comment': comment,
    if (reviewText != null) 'review_text': reviewText,
    if (reviewTextAr != null) 'review_text_ar': reviewTextAr,
    if (reviewTextEn != null) 'review_text_en': reviewTextEn,
    if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
  };
}

/// A medical specialty from `GET /specialties`. [nameEn] is the value sent
/// back to the `/doctors` specialty filter (the backend matches either the
/// English or Arabic name); [label] picks the locale-appropriate text.
class Specialty {
  const Specialty({required this.nameEn, required this.nameAr, this.id});

  final String? id;
  final String nameEn;
  final String nameAr;

  String label(bool isArabic) =>
      isArabic ? (nameAr.isEmpty ? nameEn : nameAr) : nameEn;

  factory Specialty.fromJson(Map<String, dynamic> json) {
    final en = _asString(_read(json, 'name_en', 'nameEn'))?.trim() ?? '';
    final ar = _asString(_read(json, 'name_ar', 'nameAr'))?.trim() ?? '';
    return Specialty(
      id: _asString(json['id']),
      nameEn: en,
      nameAr: ar.isEmpty ? en : ar,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Specialty &&
      other.id == id &&
      other.nameEn == nameEn &&
      other.nameAr == nameAr;

  @override
  int get hashCode => Object.hash(id, nameEn, nameAr);
}

/// Parses the `GET /specialties` array envelope (`{ success, data: [...] }`).
/// Returns an empty list on any unexpected shape so callers can fall back
/// to [kDoctorSpecialtyFallback] instead of failing the screen.
List<Specialty> parseSpecialtyList(Map<String, dynamic>? envelope) {
  if (envelope == null) return const [];
  final data = envelope['data'] ?? envelope['specialties'];
  if (data is! List) return const [];
  return data
      .whereType<Map>()
      .map((row) => Specialty.fromJson(Map<String, dynamic>.from(row)))
      .where((specialty) => specialty.nameEn.isNotEmpty)
      .toList();
}

/// Offline fallback specialty list, mirroring the hard-coded list the web
/// Find Doctors page ships (`frontend/src/js/find-doctors.js`) for when
/// `GET /specialties` is unavailable.
const List<Specialty> kDoctorSpecialtyFallback = [
  Specialty(nameEn: 'Anesthesiology', nameAr: 'التخدير'),
  Specialty(nameEn: 'Cardiology', nameAr: 'طب القلب'),
  Specialty(nameEn: 'Dentistry', nameAr: 'طب الأسنان'),
  Specialty(nameEn: 'Dermatology', nameAr: 'طب الجلدية'),
  Specialty(nameEn: 'Emergency Medicine', nameAr: 'طب الطوارئ'),
  Specialty(nameEn: 'Endocrinology', nameAr: 'طب الغدد الصماء'),
  Specialty(nameEn: 'ENT', nameAr: 'طب الأنف والأذن والحنجرة'),
  Specialty(nameEn: 'Gastroenterology', nameAr: 'طب الجهاز الهضمي'),
  Specialty(nameEn: 'General Practice', nameAr: 'طب عام'),
  Specialty(nameEn: 'General Surgery', nameAr: 'جراحة عامة'),
  Specialty(nameEn: 'Geriatrics', nameAr: 'طب الشيخوخة'),
  Specialty(nameEn: 'Hematology', nameAr: 'طب الدم'),
  Specialty(nameEn: 'Nephrology', nameAr: 'طب الكلى'),
  Specialty(nameEn: 'Neurology', nameAr: 'طب الأعصاب'),
  Specialty(nameEn: 'Obstetrics & Gynecology', nameAr: 'طب النساء والتوليد'),
  Specialty(nameEn: 'Oncology', nameAr: 'طب الأورام'),
  Specialty(nameEn: 'Ophthalmology', nameAr: 'طب العيون'),
  Specialty(nameEn: 'Orthopedics', nameAr: 'جراحة العظام'),
  Specialty(nameEn: 'Pediatrics', nameAr: 'طب الأطفال'),
  Specialty(nameEn: 'Physiotherapy', nameAr: 'طب إعادة التأهيل'),
  Specialty(nameEn: 'Psychiatry', nameAr: 'طب نفسي'),
  Specialty(nameEn: 'Pulmonology', nameAr: 'طب الرئة'),
  Specialty(nameEn: 'Radiology', nameAr: 'الأشعة'),
  Specialty(nameEn: 'Rheumatology', nameAr: 'طب الروماتيزم'),
  Specialty(nameEn: 'Urology', nameAr: 'جراحة المسالك البولية'),
];

class DoctorPagination {
  const DoctorPagination({
    this.page,
    this.limit,
    this.total,
    this.totalPages,
    this.hasNext,
    this.hasPrevious,
    this.extra = const {},
  });

  final int? page;
  final int? limit;
  final int? total;
  final int? totalPages;
  final bool? hasNext;
  final bool? hasPrevious;
  final Map<String, dynamic> extra;

  factory DoctorPagination.fromJson(Map<String, dynamic> json) {
    return DoctorPagination(
      page: _asInt(json['page']),
      limit: _asInt(json['limit']),
      total: _asInt(json['total']),
      totalPages: _asInt(_read(json, 'total_pages', 'totalPages')),
      hasNext: _asBool(_read(json, 'has_next', 'hasNext')),
      hasPrevious: _asBool(_read(json, 'has_previous', 'hasPrevious')),
      extra: _extra(json, const {
        'page',
        'limit',
        'total',
        'total_pages',
        'totalPages',
        'has_next',
        'hasNext',
        'has_previous',
        'hasPrevious',
      }),
    );
  }
}

Map<String, dynamic> _payload(Map<String, dynamic> json) =>
    _asMap(json['data']) ?? json;

Object? _read(Map<String, dynamic> json, String snake, String camel) =>
    json.containsKey(snake) ? json[snake] : json[camel];

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) return const [];
  return value.map((item) {
    if (item is! Map) {
      throw const FormatException('Malformed list item: expected an object.');
    }
    return Map<String, dynamic>.from(item);
  }).toList();
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .where((item) => item != null)
      .map((item) => item.toString())
      .toList();
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

DateTime? _asDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

Map<String, dynamic> _extra(Map<String, dynamic> json, Set<String> known) {
  return _copyMap(
    Map<String, dynamic>.fromEntries(
      json.entries.where((entry) => !known.contains(entry.key)),
    ),
  );
}

Map<String, dynamic> _copyMap(Map<String, dynamic> value) {
  return value.map((key, item) => MapEntry(key, _copyValue(item)));
}

Object? _copyValue(Object? value) {
  if (value is Map) return _copyMap(Map<String, dynamic>.from(value));
  if (value is List) return value.map(_copyValue).toList();
  return value;
}

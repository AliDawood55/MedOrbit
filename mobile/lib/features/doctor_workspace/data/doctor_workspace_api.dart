import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/doctor_models.dart';

const _invalidResponse = ApiException(
  message: 'Unexpected response from server. Please try again.',
  code: 'INVALID_RESPONSE',
);

class DoctorWorkspaceApi {
  DoctorWorkspaceApi(this._dio);
  final Dio _dio;

  Object? _data(Response<dynamic> response) =>
      response.data is Map<String, dynamic>
      ? (response.data as Map<String, dynamic>)['data']
      : null;
  Map<String, dynamic> _dataMap(Response<dynamic> response) {
    final value = _data(response);
    if (value is! Map<String, dynamic>) throw _invalidResponse;
    return value;
  }

  List<Map<String, dynamic>> _dataList(Response<dynamic> response) {
    final value = _data(response);
    if (value is! List) throw _invalidResponse;
    return value
        .map((entry) {
          if (entry is! Map<String, dynamic>) throw _invalidResponse;
          return entry;
        })
        .toList(growable: false);
  }

  T _parse<T>(T Function() parser) {
    try {
      return parser();
    } on FormatException {
      throw _invalidResponse;
    } on TypeError {
      throw _invalidResponse;
    }
  }

  Future<T> _model<T>(
    Future<Response<dynamic>> request,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await request;
    return _parse(() => fromJson(_dataMap(response)));
  }

  Future<List<T>> _models<T>(
    Future<Response<dynamic>> request,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final response = await request;
    return _parse(
      () => _dataList(response).map(fromJson).toList(growable: false),
    );
  }

  Future<DoctorProfile> getProfile() =>
      _model(_dio.get('/doctors/me/profile'), DoctorProfile.fromJson);

  Future<DoctorProfile> updateProfile({
    required String headline,
    required String bio,
    required String subSpecialty,
    required int? yearsOfExperience,
    required List<String> expertise,
    required List<String> interests,
    required List<String> education,
    required List<String> certifications,
    required List<String> languages,
    required String city,
    required double? consultationFee,
    required int consultationDuration,
    required bool isAcceptingPatients,
  }) async {
    final response = await _dio.put(
      '/doctors/me/profile',
      data: {
        'professionalHeadline': headline.trim(),
        'bio': bio.trim(),
        'subSpecialty': subSpecialty.trim(),
        'yearsOfExperience': yearsOfExperience,
        'areasOfExpertise': expertise,
        'professionalInterests': interests,
        'education': education,
        'certifications': certifications,
        'languagesSpoken': languages,
        'city': city.trim(),
        'consultationFee': consultationFee,
        'consultationDuration': consultationDuration,
        'isAcceptingPatients': isAcceptingPatients,
      },
    );
    return _parse(() => DoctorProfile.fromJson(_dataMap(response)));
  }

  Future<DoctorSchedule> getSchedule() =>
      _model(_dio.get('/doctors/me/schedule'), DoctorSchedule.fromJson);

  Future<DoctorAvailability> createAvailability(Map<String, dynamic> payload) =>
      _model(
        _dio.post('/doctors/me/availability', data: payload),
        DoctorAvailability.fromJson,
      );
  Future<DoctorAvailability> updateAvailability(
    String id,
    Map<String, dynamic> payload,
  ) => _model(
    _dio.put('/doctors/me/availability/$id', data: payload),
    DoctorAvailability.fromJson,
  );
  Future<void> deleteAvailability(String id) async {
    await _dio.delete('/doctors/me/availability/$id');
  }

  Future<DoctorAppointment> confirmAppointment(String id) => _model(
    _dio.put('/appointments/$id/confirm', data: const {}),
    DoctorAppointment.fromJson,
  );
  Future<DoctorAppointment> completeAppointment(String id) => _model(
    _dio.put('/appointments/$id/complete', data: const {}),
    DoctorAppointment.fromJson,
  );
  Future<DoctorAppointment> cancelAppointment(String id, {String? reason}) =>
      _model(
        _dio.put(
          '/appointments/$id/cancel',
          data: {
            if (reason != null && reason.trim().isNotEmpty)
              'reason': reason.trim(),
          },
        ),
        DoctorAppointment.fromJson,
      );

  Future<List<DoctorPatient>> getPatients({String? search}) async {
    final query = search?.trim();
    return _models(
      _dio.get(
        '/doctors/me/patients',
        queryParameters: {
          if (query != null && query.isNotEmpty) 'search': query,
        },
      ),
      DoctorPatient.fromJson,
    );
  }

  Future<DoctorPatientDetail> getPatient(String id) => _model(
    _dio.get('/doctors/me/patients/$id'),
    DoctorPatientDetail.fromJson,
  );
  Future<ClinicalRecord> createSessionNote(
    String patientId, {
    required String recordType,
    required String chiefComplaint,
    required String diagnosis,
    required String clinicalNotes,
    required bool isDraft,
    required bool visibleToPatient,
  }) => _model(
    _dio.post(
      '/doctors/me/patients/$patientId/notes',
      data: {
        'record_type': recordType,
        'chief_complaint': chiefComplaint.trim(),
        'diagnosis': diagnosis.trim(),
        'clinical_notes': clinicalNotes.trim(),
        'is_draft': isDraft,
        'visible_to_patient': visibleToPatient,
      },
    ),
    ClinicalRecord.fromJson,
  );
  Future<void> endRelationship(String patientId, String reason) async {
    await _dio.post(
      '/doctors/me/patients/$patientId/relationship/end',
      data: {'reason': reason.trim()},
    );
  }

  Future<List<DoctorPost>> getPosts() =>
      _models(_dio.get('/doctors/me/posts'), DoctorPost.fromJson);
  Future<DoctorPost> savePost({
    String? id,
    required String title,
    required String category,
    required String body,
    required bool publish,
  }) async {
    final payload = {
      'title': title.trim(),
      'category': category,
      'body': body.trim(),
      'isPublished': publish,
    };
    final response = id == null
        ? await _dio.post('/doctors/me/posts', data: payload)
        : await _dio.put('/doctors/me/posts/$id', data: payload);
    return _parse(() => DoctorPost.fromJson(_dataMap(response)));
  }

  Future<void> deletePost(String id) async {
    await _dio.delete('/doctors/me/posts/$id');
  }

  Future<List<ClinicalRecord>> getRecords() =>
      _models(_dio.get('/medical-records'), ClinicalRecord.fromJson);
  Future<ClinicalRecord> createRecord({
    required String appointmentId,
    required String recordType,
    required String chiefComplaint,
    required String diagnosis,
    required String treatmentPlan,
    required String clinicalNotes,
    required String doctorNotes,
    required bool isDraft,
  }) => _model(
    _dio.post(
      '/medical-records',
      data: {
        'appointment_id': appointmentId,
        'record_type': recordType,
        'chief_complaint': chiefComplaint.trim(),
        'diagnosis': diagnosis.trim(),
        'treatment_plan': treatmentPlan.trim(),
        'clinical_notes': clinicalNotes.trim(),
        'doctor_notes': doctorNotes.trim(),
        'is_draft': isDraft,
      },
    ),
    ClinicalRecord.fromJson,
  );
  Future<ClinicalRecord> updateRecord(
    String id, {
    required String diagnosis,
    required String treatmentPlan,
    required String clinicalNotes,
    required String doctorNotes,
    required bool isDraft,
  }) => _model(
    _dio.put(
      '/medical-records/$id',
      data: {
        'diagnosis': diagnosis.trim(),
        'treatment_plan': treatmentPlan.trim(),
        'clinical_notes': clinicalNotes.trim(),
        'doctor_notes': doctorNotes.trim(),
        'is_draft': isDraft,
      },
    ),
    ClinicalRecord.fromJson,
  );
  Future<void> deleteRecord(String id) async {
    await _dio.delete('/medical-records/$id');
  }

  Future<PrescriptionResult> createPrescription({
    required String patientId,
    required String appointmentId,
    String? validUntil,
    required String diagnosis,
    required String instructions,
    required String doctorNotes,
    required List<Map<String, dynamic>> items,
  }) async {
    final data = _dataMap(
      await _dio.post(
        '/prescriptions',
        data: {
          'patient_id': patientId,
          'appointment_id': appointmentId,
          if (validUntil != null && validUntil.isNotEmpty)
            'valid_until': validUntil,
          'diagnosis': diagnosis.trim(),
          'instructions': instructions.trim(),
          'doctor_notes': doctorNotes.trim(),
          'items': items,
        },
      ),
    );
    final safety = data['safety_check'];
    return PrescriptionResult(
      prescription: _parse(() => DoctorPrescription.fromJson(data)),
      safetyStatus: safety is Map<String, dynamic> && safety['status'] is String
          ? safety['status'] as String
          : 'unavailable',
    );
  }
}

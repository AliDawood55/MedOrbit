import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/my_doctor_model.dart';
import '../models/shared_note_model.dart';

const _invalidResponse = ApiException(
  message: 'Unexpected response from server. Please try again.',
  code: 'INVALID_RESPONSE',
);

class CareApi {
  CareApi(this._dio);

  final Dio _dio;

  /// A malformed entry fails the whole fetch rather than being silently
  /// dropped — a treating doctor quietly missing from the list would read
  /// to the patient as "you have no doctor", which is worse than a
  /// retryable error state (same reasoning as `AppointmentsApi.list`). An
  /// empty `data: []` is a legitimate "no active doctors" response and
  /// returns normally.
  Future<List<MyDoctorModel>> myDoctors() async {
    final response = await _dio.get('/patients/me/doctors');
    final data = response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! List) throw _invalidResponse;
    return data.map((e) {
      if (e is! Map<String, dynamic>) throw _invalidResponse;
      return MyDoctorModel.fromJson(e);
    }).toList();
  }

  /// A legitimate `200` with an empty list means "no shared notes yet" and
  /// must reach the caller as `[]`; any other failure (network, malformed
  /// envelope, malformed entry) throws instead, so the UI can tell the two
  /// apart rather than collapsing both into an empty list.
  Future<List<SharedNoteModel>> sharedNotes(String doctorId) async {
    final response = await _dio.get('/patients/me/doctors/$doctorId/notes');
    final data = response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! List) throw _invalidResponse;
    return data.map((e) {
      if (e is! Map<String, dynamic>) throw _invalidResponse;
      return SharedNoteModel.fromJson(e);
    }).toList();
  }
}

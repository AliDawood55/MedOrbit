import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/clinic_models.dart';
import '../models/doctor_models.dart';

class DiscoveryApi {
  DiscoveryApi(this._dio);

  final Dio _dio;

  Future<ClinicListResponse> listClinics({
    String? region,
    String? service,
    String? insurance,
    String? search,
    String? type,
    int page = 1,
    int limit = 10,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/clinics',
      queryParameters: _withoutNulls({
        'region': region,
        'service': service,
        'insurance': insurance,
        'search': search,
        'type': type,
        'page': page,
        'limit': limit,
      }),
    );
    return ClinicListResponse.fromJson(_envelopeData(response.data));
  }

  Future<NearbyClinicResponse> nearbyClinics({
    required double lat,
    required double lng,
    double radius = 5,
    String? type,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/clinics/nearby',
      queryParameters: _withoutNulls({
        'lat': lat,
        'lng': lng,
        'radius': radius,
        'type': type,
      }),
    );
    return NearbyClinicResponse.fromJson(_envelopeData(response.data));
  }

  Future<ClinicDetailResponse> getClinic(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/clinics/$id');
    return ClinicDetailResponse.fromJson(_envelopeData(response.data));
  }

  Future<DoctorListResponse> listDoctors({
    String? specialty,
    String? region,
    double? minRating,
    double? minFee,
    double? maxFee,
    String? search,
    int page = 1,
    int limit = 10,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/doctors',
      queryParameters: _withoutNulls({
        'specialty': specialty,
        'region': region,
        'minRating': minRating,
        'minFee': minFee,
        'maxFee': maxFee,
        'search': search,
        'page': page,
        'limit': limit,
      }),
    );
    return DoctorListResponse.fromJson(_envelopeData(response.data));
  }

  /// `GET /specialties` — the canonical specialty list that backs the Find
  /// Doctors specialty filter. Returns an empty list on an unexpected
  /// payload; callers fall back to [kDoctorSpecialtyFallback].
  Future<List<Specialty>> listSpecialties() async {
    final response = await _dio.get<Map<String, dynamic>>('/specialties');
    return parseSpecialtyList(response.data);
  }

  /// `GET /recommendations/doctors` — the authenticated "Recommended
  /// doctors" strip on the web Find Doctors page. Backend caps `limit` at
  /// 30 and returns ranked doctors carrying a `reason_code` (surfaced via
  /// [Doctor.extra]).
  Future<List<Doctor>> recommendedDoctors({int limit = 6}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/recommendations/doctors',
      queryParameters: {'limit': limit},
    );
    return DoctorListResponse.fromJson(_envelopeData(response.data)).doctors;
  }

  /// `POST /recommendations/specialties/:id/search` — best-effort telemetry
  /// the web page fires when a signed-in user picks a specialty. The
  /// backend rate-limits and de-duplicates per user/specialty/day, so
  /// callers just fire and forget.
  Future<void> recordSpecialtySearch(String specialtyId) async {
    await _dio.post<Map<String, dynamic>>(
      '/recommendations/specialties/$specialtyId/search',
    );
  }

  Future<DoctorDetailResponse> getDoctor(String id) async {
    final response = await _dio.get<Map<String, dynamic>>('/doctors/$id');
    return DoctorDetailResponse.fromJson(_envelopeData(response.data));
  }

  Future<DoctorAvailabilityResponse> getDoctorAvailability(String id, {String? date}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/doctors/$id/availability',
      queryParameters: _withoutNulls({'date': date}),
    );
    return DoctorAvailabilityResponse.fromJson(_envelopeData(response.data));
  }
}

Map<String, dynamic> _envelopeData(Map<String, dynamic>? envelope) {
  if (envelope == null) {
    throw const ApiException(message: 'Empty response from server.', code: 'EMPTY_RESPONSE');
  }

  if (envelope['success'] == false) {
    throw ApiException(
      message: envelope['message'] as String? ?? 'Request failed.',
      code: 'BACKEND_FAILURE',
    );
  }

  final data = envelope['data'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  throw const ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE');
}

Map<String, dynamic> _withoutNulls(Map<String, dynamic> value) {
  return Map<String, dynamic>.fromEntries(value.entries.where((entry) => entry.value != null));
}

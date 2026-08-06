import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/appointment_model.dart';
import '../models/availability_slot_model.dart';

class BookingApi {
  BookingApi(this._dio);

  final Dio _dio;

  /// `GET /appointments/available-slots` — public endpoint, returns the
  /// doctor's raw availability windows for [date] at [clinicId]. It does not
  /// account for appointments already booked; see [generateSlotsFromWindows]
  /// (`slot_generation.dart`) for turning this into selectable slots.
  Future<List<AvailabilityWindow>> availableSlots({
    required String doctorId,
    required String clinicId,
    required String date,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/appointments/available-slots',
      queryParameters: {'doctor_id': doctorId, 'clinic_id': clinicId, 'date': date},
    );

    final envelope = response.data;
    if (envelope == null) {
      throw const ApiException(message: 'Empty response from server.', code: 'EMPTY_RESPONSE');
    }
    if (envelope['success'] == false) {
      throw const ApiException(message: 'Request failed.', code: 'BACKEND_FAILURE');
    }

    final data = envelope['data'];
    if (data is! List) {
      throw const ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE');
    }

    return data.whereType<Map>().map((row) => AvailabilityWindow.fromJson(Map<String, dynamic>.from(row))).toList();
  }

  /// `POST /appointments`. A `SLOT_BUSY` conflict surfaces as an
  /// [ApiException] with `code == 'SLOT_BUSY'` via the shared error
  /// interceptor — same normalization every other feature relies on.
  Future<AppointmentModel> create({
    required String doctorId,
    required String clinicId,
    required String scheduledDate,
    required String startTime,
    required String endTime,
    required int durationMinutes,
    required String appointmentType,
    String? reasonForVisit,
    String? notes,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/appointments',
      data: {
        'doctor_id': doctorId,
        'clinic_id': clinicId,
        'scheduled_date': scheduledDate,
        'start_time': startTime,
        'end_time': endTime,
        'duration_minutes': durationMinutes,
        'appointment_type': appointmentType,
        'reason_for_visit': reasonForVisit,
        'notes': notes,
      },
    );

    final data = response.data?['data'];
    if (data is! Map) {
      throw const ApiException(message: 'Unexpected response from server.', code: 'INVALID_RESPONSE');
    }
    return AppointmentModel.fromJson(Map<String, dynamic>.from(data));
  }
}

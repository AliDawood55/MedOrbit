import 'package:dio/dio.dart';

import '../../common/data/admin_response.dart';
import '../models/admin_doctor_application.dart';

/// Client for `/api/admin/doctor-applications` (`authorizeAdmin`).
///
/// The list endpoint takes only `status` and returns the 100 most recent rows
/// (`LIMIT 100` in `doctor-application.routes.js:64`) — there is no pagination
/// parameter to send, so none is invented here.
///
/// Deliberately **not** exposed: `POST /admin/doctor-applications/doctors/
/// :id/:action` (suspend/reactivate a doctor). No endpoint returns a doctor's
/// current `approval_status` to an administrator — `GET /doctors/:id` filters
/// to `approval_status='approved'` — so a suspended doctor becomes unreadable
/// and the app could offer a suspend button it can never show the result of,
/// or undo. The web admin product does not expose it either.
class AdminDoctorApplicationsApi {
  AdminDoctorApplicationsApi(this._dio);

  final Dio _dio;

  Future<List<AdminDoctorApplication>> list({
    AdminApplicationStatus? status,
  }) async {
    final wireStatus = adminApplicationStatusWireValue(status);
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/doctor-applications',
      queryParameters: wireStatus == null ? null : {'status': wireStatus},
    );
    return adminEnvelopeList(
      response.data,
    ).map(AdminDoctorApplication.fromJson).toList(growable: false);
  }

  Future<AdminDoctorApplication> get(String applicationId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/doctor-applications/${Uri.encodeComponent(applicationId)}',
    );
    return AdminDoctorApplication.fromJson(
      adminEnvelopeObject(response.data),
    );
  }

  /// Approving converts the applicant's account to `doctor` and revokes its
  /// sessions server-side. There is no undo endpoint.
  Future<void> approve(String applicationId) async {
    await _dio.post<Map<String, dynamic>>(
      '/admin/doctor-applications/${Uri.encodeComponent(applicationId)}/approve',
      data: const <String, dynamic>{},
    );
  }

  /// `rejection_reason` is required by the service
  /// (`decide(..., approve: false)` fails with `VALIDATION_ERROR` on a blank
  /// reason), so it is validated before the request is sent as well.
  Future<void> reject(String applicationId, String reason) async {
    await _dio.post<Map<String, dynamic>>(
      '/admin/doctor-applications/${Uri.encodeComponent(applicationId)}/reject',
      data: {'rejection_reason': reason},
    );
  }
}

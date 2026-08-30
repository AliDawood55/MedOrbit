import 'package:dio/dio.dart';
import '../../../../core/network/api_exception.dart';
import '../models/admin_management_models.dart';

class AdminManagementApi {
  AdminManagementApi(this._dio);
  final Dio _dio;
  Future<List<AdminUser>> users({String? role}) {
    final query = role == null || role.isEmpty
        ? ''
        : '?role=${Uri.encodeQueryComponent(role)}';
    return _list('/admin/users$query', AdminUser.fromJson);
  }

  Future<void> setUserActive(String id, bool active) async => _dio.put<void>(
    '/admin/users/$id/${active ? 'reactivate' : 'deactivate'}',
  );
  Future<List<DoctorApplication>> applications({
    required bool isArabic,
  }) async => _list(
    '/admin/doctor-applications?status=pending',
    (json) => DoctorApplication.fromJson(json, isArabic: isArabic),
  );
  Future<void> approveApplication(String id) async =>
      _dio.post<void>('/admin/doctor-applications/$id/approve');
  Future<void> rejectApplication(String id, String reason) async =>
      _dio.post<void>(
        '/admin/doctor-applications/$id/reject',
        data: {'rejection_reason': reason},
      );
  Future<List<AdminInvitation>> invitations() async =>
      _list('/admin/invitations', AdminInvitation.fromJson);
  Future<List<AdminActivityItem>> activity(String kind) {
    const allowed = {'appointments', 'records', 'prescriptions', 'reviews'};
    if (!allowed.contains(kind)) {
      throw const ApiException(
        message: 'Unsupported activity type.',
        code: 'VALIDATION_ERROR',
      );
    }
    return _list('/admin/activity/$kind', AdminActivityItem.fromJson);
  }

  /// Returns the one-time handoff URL only when the server could not deliver
  /// the invitation by email. It is intentionally never available in lists.
  Future<String?> createInvitation(String email) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/invitations',
      data: {'email': email},
    );
    final data = response.data?['data'];
    if (response.data?['success'] != true || data is! Map) {
      throw const ApiException(
        message: 'The invitation response was incomplete.',
        code: 'INVALID_RESPONSE',
      );
    }
    final values = Map<String, dynamic>.from(data);
    return values['delivery'] == 'manual'
        ? values['acceptance_url']?.toString()
        : null;
  }

  Future<void> revokeInvitation(String id) async =>
      _dio.delete<void>('/admin/invitations/$id');
  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) convert,
  ) async {
    final response = await _dio.get<Map<String, dynamic>>(path);
    final data = response.data?['data'];
    if (response.data?['success'] != true || data is! List) {
      throw const ApiException(
        message: 'The administration response was incomplete.',
        code: 'INVALID_RESPONSE',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => convert(Map<String, dynamic>.from(item)))
        .toList();
  }
}

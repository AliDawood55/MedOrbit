import 'package:dio/dio.dart';

import '../../common/data/admin_response.dart';
import '../models/admin_user.dart';

/// Client for `/api/admin/users` (`authorizeAdmin`).
///
/// Only the three filters the backend actually implements are sent — `role`,
/// `active`, `search`. There is no pagination on this endpoint: the query has
/// no `LIMIT`, so the response is the complete filtered account list and the
/// screen renders it lazily rather than inventing page parameters the server
/// would ignore.
class AdminUsersApi {
  AdminUsersApi(this._dio);

  final Dio _dio;

  Future<List<AdminUser>> list({
    String? search,
    AdminUserRole? role,
    bool? active,
  }) async {
    final trimmedSearch = search?.trim();
    final query = <String, dynamic>{
      if (trimmedSearch != null && trimmedSearch.isNotEmpty)
        'search': trimmedSearch,
      if (adminUserRoleWireValue(role) case final String value) 'role': value,
      // The backend compares `active === 'true'`, so this must travel as the
      // string form the web `<select>` submits, not as a JSON boolean.
      if (active != null) 'active': active ? 'true' : 'false',
    };

    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/users',
      queryParameters: query.isEmpty ? null : query,
    );
    return adminEnvelopeList(
      response.data,
    ).map(AdminUser.fromJson).toList(growable: false);
  }

  Future<AdminUserStateUpdate> deactivate(String userId) =>
      _setActive(userId, 'deactivate');

  Future<AdminUserStateUpdate> reactivate(String userId) =>
      _setActive(userId, 'reactivate');

  Future<AdminUserStateUpdate> _setActive(String userId, String action) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/admin/users/${Uri.encodeComponent(userId)}/$action',
      data: const <String, dynamic>{},
    );
    return AdminUserStateUpdate.fromJson(adminEnvelopeObject(response.data));
  }
}

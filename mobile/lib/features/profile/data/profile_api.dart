import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../home/models/user_profile_model.dart';
import '../models/profile_edit_model.dart';

class ProfileApi {
  ProfileApi(this._dio);

  final Dio _dio;

  Future<UserProfileModel> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>('/users/me');
    return UserProfileModel.fromJson(_envelopeData(response.data));
  }

  /// `PUT /users/me` — always returns `data: null` on success; the caller
  /// must re-fetch via [getMe] to see the saved values reflected.
  Future<void> updateMe(ProfileEditModel draft) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/users/me',
      data: draft.toJson(),
    );
    _envelopeSuccess(response.data);
  }

  /// `PUT /users/me/preferences` — body is `{ language }` only. The backend
  /// accepts any string here (no server-side enum check), so the caller must
  /// restrict this to `'ar'`/`'en'` itself.
  Future<void> updateLanguagePreference(String language) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/users/me/preferences',
      data: {'language': language},
    );
    _envelopeSuccess(response.data);
  }

  /// Stores the backend-validated public contact links under the account
  /// preferences document. Admin roles are refused by the server.
  Future<void> updateSocialLinks(Map<String, String> socialLinks) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/users/me/preferences',
      data: {'social_links': socialLinks},
    );
    _envelopeSuccess(response.data);
  }

  /// `POST /users/me/avatar`, multipart field name `avatar` (must match
  /// exactly — the backend's `multer` middleware is configured with
  /// `upload.single("avatar")`). Returns the new relative avatar path
  /// (`data.avatar`, e.g. `/uploads/avatars/1699999999999.jpg`) — note this
  /// response uses the key `avatar`, while `GET /users/me` returns the same
  /// concept under `avatar_url`; the two are not interchangeable field names.
  Future<String> uploadAvatar({
    required String filePath,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/users/me/avatar',
      data: formData,
    );
    final data = _envelopeData(response.data);
    final avatar = data['avatar'];
    if (avatar is! String || avatar.isEmpty) {
      throw const ApiException(
        message: 'Unexpected response from server.',
        code: 'INVALID_RESPONSE',
      );
    }
    return avatar;
  }

  /// `POST /auth/change-password` — `{ currentPassword, newPassword }`. A
  /// wrong current password or a new password failing the server's policy
  /// both surface as a normal HTTP 400 through the shared error interceptor,
  /// not through this success path.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/change-password',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    _envelopeSuccess(response.data);
  }
}

void _envelopeSuccess(Map<String, dynamic>? envelope) {
  if (envelope == null) {
    throw const ApiException(
      message: 'Empty response from server.',
      code: 'EMPTY_RESPONSE',
    );
  }
  if (envelope['success'] == false) {
    throw const ApiException(
      message: 'Request failed.',
      code: 'BACKEND_FAILURE',
    );
  }
}

Map<String, dynamic> _envelopeData(Map<String, dynamic>? envelope) {
  _envelopeSuccess(envelope);
  final data = envelope!['data'];
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  throw const ApiException(
    message: 'Unexpected response from server.',
    code: 'INVALID_RESPONSE',
  );
}

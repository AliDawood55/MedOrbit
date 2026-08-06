import 'package:dio/dio.dart';

/// Raw HTTP calls against the existing `/auth/*` backend contract.
/// Returns each response's `data` payload as-is; error normalization and
/// session persistence happen one layer up, in the repository.
class AuthApi {
  AuthApi(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final response = await _dio.post(
      '/auth/login',
      data: {'email': email, 'password': password, 'platform': 'mobile'},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String firstNameAr,
    required String lastNameAr,
    required String firstNameEn,
    required String lastNameEn,
    String? phone,
    String? gender,
  }) async {
    final response = await _dio.post(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        'role': 'patient',
        'firstNameAr': firstNameAr,
        'lastNameAr': lastNameAr,
        'firstNameEn': firstNameEn,
        'lastNameEn': lastNameEn,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (gender != null && gender.isNotEmpty) 'gender': gender,
      },
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> googleLogin(String idToken) async {
    final response = await _dio.post(
      '/auth/google',
      data: {'idToken': idToken, 'platform': 'mobile'},
    );
    return response.data['data'] as Map<String, dynamic>;
  }

  Future<void> logout(String refreshToken) async {
    await _dio.post('/auth/logout', data: {'refreshToken': refreshToken});
  }

  Future<void> forgotPassword(String email) async {
    await _dio.post('/auth/forgot-password', data: {'email': email});
  }

  Future<void> verifyEmail({required String token, String? email}) async {
    await _dio.post(
      '/auth/verify-email',
      data: {'token': token, if (email != null && email.isNotEmpty) 'email': email},
    );
  }

  Future<void> resendVerification(String email) async {
    await _dio.post('/auth/resend-verification', data: {'email': email});
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    await _dio.post('/auth/reset-password', data: {'token': token, 'newPassword': newPassword});
  }
}

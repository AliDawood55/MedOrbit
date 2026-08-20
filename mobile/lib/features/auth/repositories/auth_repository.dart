import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../data/auth_api.dart';
import '../models/auth_result_model.dart';
import '../models/user_model.dart';

class AuthRepository {
  AuthRepository(this._api, this._storage);

  final AuthApi _api;
  final SecureStorageService _storage;

  Future<AuthResultModel> login({required String email, required String password}) async {
    try {
      final json = await _api.login(email: email, password: password);
      final result = AuthResultModel.fromJson(json);
      await _storage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
      await _storage.saveUserJson(jsonEncode(result.user.toJson()));
      return result;
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  Future<UserModel> register({
    required String email,
    required String password,
    required String firstNameAr,
    required String lastNameAr,
    required String firstNameEn,
    required String lastNameEn,
    String? phone,
    String? gender,
  }) async {
    try {
      final json = await _api.register(
        email: email,
        password: password,
        firstNameAr: firstNameAr,
        lastNameAr: lastNameAr,
        firstNameEn: firstNameEn,
        lastNameEn: lastNameEn,
        phone: phone,
        gender: gender,
      );
      return UserModel.fromJson(json);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  Future<void> forgotPassword(String email) async {
    try {
      await _api.forgotPassword(email);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  Future<void> verifyEmail({required String token, String? email}) async {
    try {
      await _api.verifyEmail(token: token, email: email);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  Future<void> resendVerification(String email) async {
    try {
      await _api.resendVerification(email);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    try {
      await _api.resetPassword(token: token, newPassword: newPassword);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  Future<AuthResultModel> loginWithGoogle(String idToken) async {
    try {
      final json = await _api.googleLogin(idToken);
      final result = AuthResultModel.fromJson(json);
      await _storage.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
      await _storage.saveUserJson(jsonEncode(result.user.toJson()));
      return result;
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  /// Best-effort server-side session revocation — the local session is
  /// always cleared even if the network call fails.
  Future<void> logout() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _api.logout(refreshToken);
      } on DioException catch (_) {}
    }
    await _storage.clear();
  }

  Future<UserModel?> getPersistedUser() async {
    final json = await _storage.getUserJson();
    if (json == null) return null;
    return UserModel.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  Future<bool> hasValidSession() async {
    final token = await _storage.getAccessToken();
    return token != null && token.isNotEmpty;
  }

  ApiException _asApiException(DioException e) {
    final error = e.error;
    if (error is ApiException) return error;
    return const ApiException(message: 'Unexpected error occurred. Please try again.', code: 'UNKNOWN_ERROR');
  }
}

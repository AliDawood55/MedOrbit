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
    } on FormatException {
      throw _invalidResponseException;
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
    } on FormatException {
      throw _invalidResponseException;
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
    } on FormatException {
      throw _invalidResponseException;
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

  /// Returns `null` if no session is cached, or if the cached JSON is
  /// corrupt/incompatible (e.g. changed shape across an app update) — the
  /// caller then treats this the same as "no persisted user" rather than
  /// crashing the splash screen on startup.
  Future<UserModel?> getPersistedUser() async {
    final json = await _storage.getUserJson();
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      return UserModel.fromJson(decoded);
    } on FormatException {
      return null;
    }
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

  /// A malformed `data` payload from an otherwise-successful auth response —
  /// not a `DioException`, so [_asApiException] never sees it.
  static const _invalidResponseException = ApiException(
    message: 'Unexpected response from server. Please try again.',
    code: 'INVALID_RESPONSE',
  );
}

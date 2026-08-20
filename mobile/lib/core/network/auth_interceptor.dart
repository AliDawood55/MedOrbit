import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/secure_storage_service.dart';

/// Injects the persisted JWT access token into every outgoing request.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._storage, this._refreshClient);

  final SecureStorageService _storage;
  final Dio _refreshClient;
  Completer<_RefreshResult?>? _refreshCompleter;

  static const _retryFlag = 'auth.refreshRetried';
  static const _skipAuthPaths = {
    '/auth/login',
    '/auth/register',
    '/auth/google',
    '/auth/logout',
    '/auth/forgot-password',
    '/auth/verify-email',
    '/auth/resend-verification',
    '/auth/reset-password',
    '/auth/refresh',
  };

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_shouldSkipAuth(options.path)) {
      final token = await _storage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options = err.requestOptions;
    if (response?.statusCode != 401 || _shouldSkipAuth(options.path) || options.extra[_retryFlag] == true) {
      handler.next(err);
      return;
    }

    final refreshed = await _refreshSession();
    if (refreshed == null) {
      handler.next(err);
      return;
    }

    options.headers['Authorization'] = 'Bearer ${refreshed.accessToken}';
    options.extra[_retryFlag] = true;

    try {
      final retryResponse = await _refreshClient.fetch(options);
      handler.resolve(retryResponse);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  bool _shouldSkipAuth(String path) => _skipAuthPaths.contains(path);

  Future<_RefreshResult?> _refreshSession() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<_RefreshResult?>();
    _refreshCompleter = completer;

    () async {
      try {
        final refreshToken = await _storage.getRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) {
          await _storage.clear();
          completer.complete(null);
          return;
        }

        final response = await _refreshClient.post(
          '/auth/refresh',
          data: {'refreshToken': refreshToken},
        );
        final data = _extractTokenPayload(response.data);
        final accessToken = data['accessToken'];
        final nextRefreshToken = data['refreshToken'];

        if (accessToken is! String || accessToken.isEmpty || nextRefreshToken is! String || nextRefreshToken.isEmpty) {
          await _storage.clear();
          completer.complete(null);
          return;
        }

        await _storage.saveTokens(accessToken: accessToken, refreshToken: nextRefreshToken);
        completer.complete(_RefreshResult(accessToken: accessToken, refreshToken: nextRefreshToken));
      } catch (_) {
        await _storage.clear();
        completer.complete(null);
      } finally {
        if (identical(_refreshCompleter, completer)) {
          _refreshCompleter = null;
        }
      }
    }();

    return completer.future;
  }

  Map<String, dynamic> _extractTokenPayload(Object? responseData) {
    if (responseData is Map<String, dynamic>) {
      final nested = responseData['data'];
      if (nested is Map<String, dynamic>) {
        return nested;
      }
      return responseData;
    }
    if (responseData is Map) {
      final map = Map<String, dynamic>.from(responseData);
      final nested = map['data'];
      if (nested is Map) {
        return Map<String, dynamic>.from(nested);
      }
      return map;
    }
    return const <String, dynamic>{};
  }
}

class _RefreshResult {
  const _RefreshResult({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;
}

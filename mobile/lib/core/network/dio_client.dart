import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/secure_storage_service.dart';
import 'auth_interceptor.dart';
import 'error_interceptor.dart';
import 'network_log_interceptor.dart';

/// Builds the configured [Dio] instances used across the app.
///
/// Plain `http://` is used deliberately in development — the dev backend has
/// no TLS. Dio itself never required HTTPS, but Android does: API 28+ blocks
/// cleartext traffic, which is why the dev LAN hosts are allowlisted in
/// `android/app/src/main/res/xml/network_security_config.xml`. Production
/// builds are expected to supply an HTTPS origin via `MEDORBIT_API_URL`.
class DioClient {
  DioClient(SecureStorageService storage) {
    refreshClient = Dio(_options());
    dio = Dio(_options());

    dio.interceptors.addAll([
      AuthInterceptor(storage, refreshClient),
      if (kDebugMode) NetworkLogInterceptor(),
      ErrorInterceptor(),
    ]);
  }

  static BaseOptions _options() {
    return BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      contentType: 'application/json',
      headers: {'Accept': 'application/json'},
    );
  }

  late final Dio dio;

  /// Interceptor-free client used by [AuthInterceptor] for `/auth/refresh` and
  /// for replaying the one retried request.
  ///
  /// Exposed so `ApiHostResolver` can repoint it too. It is a separate Dio, so
  /// updating only [dio] on a fallback left refresh talking to the compile-time
  /// primary host — every token refresh then failed on emulator/localhost.
  late final Dio refreshClient;
}

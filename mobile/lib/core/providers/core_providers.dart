import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/ai_health_client.dart';
import '../network/api_host_resolver.dart';
import '../network/dio_client.dart';
import '../network/error_interceptor.dart';
import '../network/network_log_interceptor.dart';
import '../storage/secure_storage_service.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) => SecureStorageService());

final dioClientProvider = Provider<DioClient>((ref) => DioClient(ref.watch(secureStorageProvider)));

final dioProvider = Provider<Dio>((ref) => ref.watch(dioClientProvider).dio);

/// Repoints both the main client and the auth refresh client, so a fallback
/// host doesn't leave `/auth/refresh` aimed at the compile-time primary.
final apiHostResolverProvider = Provider<ApiHostResolver>((ref) {
  final client = ref.watch(dioClientProvider);
  return ApiHostResolver(client.dio, mirrors: [client.refreshClient]);
});

/// Origin of whichever host actually resolved — use this (not
/// `AppConfig.originUrl`) when building absolute asset URLs, so images keep
/// working if the app fell back to the emulator/localhost host.
final activeOriginProvider = Provider<String>((ref) {
  return AppConfig.originOf(ref.watch(dioProvider).options.baseUrl);
});

/// Base URL of the Python AI service (port 8001), tracking whichever host
/// the API resolver settled on.
final aiBaseUrlProvider = Provider<String>((ref) {
  return AppConfig.aiBaseFrom(ref.watch(dioProvider).options.baseUrl);
});

/// Separate client for the AI service: different port, no `/api` prefix, and
/// no auth header.
///
/// Still used by the endpoints the AI service exposes directly (drug checks,
/// triage, health). The Virtual Doctor no longer uses it: those endpoints now
/// require an internal service credential a mobile app cannot hold, so they go
/// through the authenticated backend via [virtualDoctorDioProvider].
///
/// Timeouts are far longer than the REST API's because the final `/message`
/// turn runs LLM reasoning inline.
final aiDioProvider = Provider<Dio>((ref) {
  final aiBaseUrl = ref.watch(aiBaseUrlProvider);
  if (kDebugMode) debugPrint('[AI] base url: $aiBaseUrl');
  final dio = Dio(
    BaseOptions(
      baseUrl: aiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.aiMessageTimeout,
      sendTimeout: AppConfig.aiMessageTimeout,
      headers: {'Accept': 'application/json'},
    ),
  );
  dio.interceptors.addAll([
    if (kDebugMode) NetworkLogInterceptor(),
    ErrorInterceptor(),
  ]);
  return dio;
});

/// Dedicated client for the AI `GET /health` preflight.
///
/// Separate from [aiDioProvider] because that one carries a 120s receive budget
/// for the inline LLM reasoning turn. A reachability probe must stay short, and
/// bounding it here means no caller can accidentally inherit the long budget.
final aiHealthDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: ref.watch(aiBaseUrlProvider),
      connectTimeout: AppConfig.aiHealthTimeout,
      receiveTimeout: AppConfig.aiHealthTimeout,
      sendTimeout: AppConfig.aiHealthTimeout,
      headers: {'Accept': 'application/json'},
    ),
  );
});

final aiHealthClientProvider = Provider<AiHealthClient>(
  (ref) => AiHealthClient(ref.watch(aiHealthDioProvider)),
);

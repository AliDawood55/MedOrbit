import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../network/ai_health_client.dart';
import '../network/api_host_resolver.dart';
import '../network/dio_client.dart';
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

/// Dedicated short-timeout client for the backend health preflight.
///
/// Virtual Doctor calls travel through the authenticated backend gateway. A
/// backend health check is deliberately all the mobile client probes; raw AI
/// service health is internal operational data and is never exposed to apps.
final aiHealthDioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: ref.watch(dioProvider).options.baseUrl,
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

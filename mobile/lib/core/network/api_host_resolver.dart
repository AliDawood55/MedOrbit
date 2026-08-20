import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

/// Picks a reachable API host at startup and points the shared [Dio] at it.
///
/// Probes [AppConfig.baseUrlCandidates] in order against `GET /health` and
/// keeps the first that answers. If none respond, the primary host is left in
/// place so the real connection error surfaces on the first actual request
/// rather than being masked by a resolver failure.
class ApiHostResolver {
  ApiHostResolver(this._primary, {List<Dio> mirrors = const <Dio>[]})
      : _mirrors = List<Dio>.unmodifiable(mirrors);

  final Dio _primary;

  /// Other clients that must follow the resolved host. `AuthInterceptor`'s
  /// refresh client is a separate [Dio]; repointing only [_primary] left
  /// `/auth/refresh` aimed at the compile-time host, so every refresh failed
  /// whenever the app fell back to the emulator or localhost candidate.
  final List<Dio> _mirrors;

  bool _resolved = false;

  String get activeBaseUrl => _primary.options.baseUrl;

  Future<String> resolve() async {
    if (_resolved) return activeBaseUrl;

    for (final candidate in AppConfig.baseUrlCandidates) {
      if (await _probe(candidate)) {
        _apply(candidate);
        // Only latch once a host actually answered. Latching on entry meant a
        // startup with the backend still booting pinned the app to the primary
        // for the rest of the process with no way to re-resolve.
        _resolved = true;
        if (kDebugMode) debugPrint('[API] using host: $candidate');
        return candidate;
      }
    }

    if (kDebugMode) {
      debugPrint('[API] no candidate host responded; keeping ${AppConfig.baseUrl}');
    }
    return activeBaseUrl;
  }

  void _apply(String candidate) {
    _primary.options.baseUrl = candidate;
    for (final mirror in _mirrors) {
      mirror.options.baseUrl = candidate;
    }
  }

  /// Uses a bare Dio so the auth/error/logging interceptors don't run for
  /// what is only a reachability check.
  Future<bool> _probe(String candidate) async {
    final probe = Dio(
      BaseOptions(
        connectTimeout: AppConfig.hostProbeTimeout,
        receiveTimeout: AppConfig.hostProbeTimeout,
      ),
    );
    try {
      final response = await probe.get<dynamic>('$candidate/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      probe.close(force: true);
    }
  }
}

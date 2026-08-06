import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Outcome of an AI service reachability probe.
///
/// Deliberately coarse: this exists to pick a safe, non-technical message and
/// to decide whether an AI flow may start at all. Nothing here is shown to a
/// patient directly, and no host, port or response body is ever carried in it.
enum AiHealthStatus {
  /// `GET /health` answered 200.
  available,

  /// No route to the service — wrong host, firewall, service not running.
  unreachable,

  /// The service accepted or refused to answer within the probe budget.
  timedOut,

  /// Reachable but not healthy (non-200, or an unexpected transport failure).
  unhealthy,
}

/// Lightweight preflight against the AI service's `GET /health`.
///
/// The AI service is a separate process on its own port with no `/api` prefix
/// and no JWT, so this deliberately does not go through the backend REST
/// client. It exists so an unreachable AI host produces an honest "service
/// unavailable" message immediately, instead of a `connectionTimeout` surfacing
/// 15s into `/virtual-doctor/start` — after the patient has already been asked
/// for microphone access.
///
/// Not a substitute for the real request: a passing probe only means the
/// service answered, so callers still handle failures from the actual call.
class AiHealthClient {
  AiHealthClient(this._dio);

  final Dio _dio;

  AiHealthStatus? _cached;
  DateTime? _cachedAt;

  /// Probes the AI service, reusing a result newer than
  /// [AppConfig.aiHealthCacheTtl] so a double-tap or an immediate retry does
  /// not issue a second request.
  ///
  /// Pass [force] to bypass the cache.
  Future<AiHealthStatus> check({bool force = false}) async {
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (!force && cached != null && cachedAt != null) {
      if (DateTime.now().difference(cachedAt) < AppConfig.aiHealthCacheTtl) {
        return cached;
      }
    }

    final status = await _probe();
    _cached = status;
    _cachedAt = DateTime.now();
    return status;
  }

  /// Drops any cached result — used when a real AI call subsequently fails, so
  /// the next preflight re-probes rather than trusting a stale pass.
  void invalidate() {
    _cached = null;
    _cachedAt = null;
  }

  Future<AiHealthStatus> _probe() async {
    try {
      final response = await _dio.get<dynamic>(
        '/health',
        options: Options(
          connectTimeout: AppConfig.aiHealthTimeout,
          sendTimeout: AppConfig.aiHealthTimeout,
          receiveTimeout: AppConfig.aiHealthTimeout,
        ),
      );
      // The body is intentionally never read or logged — only the status line
      // decides, so a diagnostic payload can never reach a log or the UI.
      return response.statusCode == 200 ? AiHealthStatus.available : AiHealthStatus.unhealthy;
    } on DioException catch (e) {
      return _classify(e.type);
    } catch (_) {
      return AiHealthStatus.unhealthy;
    }
  }

  static AiHealthStatus _classify(DioExceptionType type) {
    return switch (type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout =>
        AiHealthStatus.timedOut,
      DioExceptionType.connectionError => AiHealthStatus.unreachable,
      _ => AiHealthStatus.unhealthy,
    };
  }
}

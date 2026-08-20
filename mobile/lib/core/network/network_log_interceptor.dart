import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug-only request/response/error metadata logger.
///
/// Request/response bodies, headers, query parameters, raw error messages, and
/// dynamic path values are intentionally never inspected. They can contain
/// credentials, medical content, transcripts, coordinates, report IDs, or
/// local file paths. Registered before [ErrorInterceptor] so failures are
/// still logged with their original Dio error type (`connectionError`,
/// `connectionTimeout`, …) before being normalized into an ApiException.
class NetworkLogInterceptor extends Interceptor {
  static const _startedAtKey = 'network.startedAtMicros';

  // Only known endpoint vocabulary is retained. Every other path segment is
  // replaced, which prevents IDs, names, tokens, addresses, and coordinates
  // from leaking while keeping routes such as /chat/message recognizable.
  static const _safePathSegments = {
    'api',
    'v1',
    'auth',
    'login',
    'logout',
    'refresh',
    'register',
    'verify',
    'forgot-password',
    'reset-password',
    'chat',
    'chatbot',
    'message',
    'messages',
    'virtual-doctor',
    'start',
    'session',
    'speak',
    'status',
    'warmup',
    'transcribe',
    'report',
    'reports',
    'download',
    'health',
    'triage',
    'clinics',
    'clinic',
    'doctors',
    'doctor',
    'pharmacies',
    'pharmacy',
    'appointments',
    'appointment',
    'search',
    'notifications',
    'notification',
    'read',
    'read-all',
  };

  NetworkLogInterceptor({void Function(String)? logger})
      : _logger = logger ?? _printDebugMessage;

  final void Function(String) _logger;

  static void _printDebugMessage(String message) => debugPrint(message);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startedAtKey] = DateTime.now().microsecondsSinceEpoch;
    if (options.extra['network.requestName'] == 'virtual_doctor.start') {
      _logger('[API]   operation=virtual_doctor.start origin=${options.uri.scheme}://${options.uri.host}:${options.uri.port}');
    }
    _logger('[API] → ${options.method.toUpperCase()} ${_safePath(options)}');
    _logger(
      '[API]   timeouts: connect=${_formatTimeout(options.connectTimeout)}, '
      'receive=${_formatTimeout(options.receiveTimeout)}, '
      'send=${_formatTimeout(options.sendTimeout)}',
    );
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final options = response.requestOptions;
    _logger(
      '[API] ← ${response.statusCode ?? 'unknown'} '
      '${options.method.toUpperCase()} ${_safePath(options)}'
      '${_durationSuffix(options)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final options = err.requestOptions;
    final statusCode = err.response?.statusCode;
    final status = statusCode == null ? '' : ' status=$statusCode';
    _logger(
      '[API] ✖ ${err.type.name} ${options.method.toUpperCase()} '
      '${_safePath(options)}$status category=${_errorCategory(err.type)}'
      '${_durationSuffix(options)}',
    );
    handler.next(err);
  }

  int? _elapsedMs(RequestOptions options) {
    final startedAt = options.extra[_startedAtKey];
    if (startedAt is! int) return null;
    return ((DateTime.now().microsecondsSinceEpoch - startedAt) / 1000).round();
  }

  String _durationSuffix(RequestOptions options) {
    final elapsedMs = _elapsedMs(options);
    return elapsedMs == null ? '' : ' ($elapsedMs ms)';
  }

  String _safePath(RequestOptions options) {
    final segments = options.uri.pathSegments;
    if (segments.isEmpty) return '/';

    return '/${segments.map((segment) {
      final normalized = segment.toLowerCase();
      return _safePathSegments.contains(normalized) ? normalized : ':value';
    }).join('/')}';
  }

  String _formatTimeout(Duration? timeout) {
    if (timeout == null) return 'none';
    return '${timeout.inMilliseconds}ms';
  }

  String _errorCategory(DioExceptionType type) {
    return switch (type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout =>
        'timeout',
      DioExceptionType.badResponse => 'http',
      DioExceptionType.cancel => 'cancelled',
      DioExceptionType.connectionError => 'connection',
      DioExceptionType.badCertificate => 'certificate',
      DioExceptionType.unknown => 'unknown',
    };
  }
}

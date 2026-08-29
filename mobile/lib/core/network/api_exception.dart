import 'package:dio/dio.dart';

/// Normalized error shape for every failure that can come out of the HTTP
/// layer, whether it originated from the backend's
/// `{ success: false, error: { code, message, details } }` envelope or from
/// Dio itself (timeout, no connection, etc).
class ApiException implements Exception {
  const ApiException({required this.message, required this.code, this.statusCode, this.details});

  final String message;
  final String code;
  final int? statusCode;
  final dynamic details;

  /// The transport could not be established at all.
  static const String codeConnectTimeout = 'CONNECT_TIMEOUT';

  /// The request body could not be uploaded in time.
  static const String codeSendTimeout = 'SEND_TIMEOUT';

  /// The request was accepted but no answer arrived in time — the one category
  /// that legitimately means "still working, just slow".
  static const String codeReceiveTimeout = 'RECEIVE_TIMEOUT';

  /// No route to the host: wrong address, firewall, or service not running.
  static const String codeServiceUnavailable = 'SERVICE_UNAVAILABLE';

  static const String codeHttpError = 'HTTP_ERROR';
  static const String codeCertificateError = 'CERTIFICATE_ERROR';
  static const String codeCancelled = 'CANCELLED';
  static const String codeUnknown = 'UNKNOWN_ERROR';

  /// Billing/entitlement codes from `backend/src/config/billing.js`'s
  /// `ERROR_CODES`. Shared here (rather than duplicated per feature) because
  /// both the chatbot and the Virtual Doctor gateway can return them, and
  /// callers must branch on these exact strings, never on `message`.
  static const String codeFreeQuotaExhausted = 'FREE_QUOTA_EXHAUSTED';
  static const String codeDuplicateInFlight = 'DUPLICATE_IN_FLIGHT';
  static const String codeVoiceCooldown = 'VOICE_COOLDOWN';
  static const String codeVoiceSessionActive = 'VOICE_SESSION_ACTIVE';
  static const String codeSubscriptionRequired = 'SUBSCRIPTION_REQUIRED';
  static const String codeSubscriptionInactive = 'SUBSCRIPTION_INACTIVE';
  static const String codeEntitlementUnavailable = 'ENTITLEMENT_UNAVAILABLE';

  /// True for any of the three timeout categories.
  ///
  /// Kept distinct from [codeServiceUnavailable] on purpose: "the AI is taking
  /// a while" and "we cannot reach the service" need different messages and
  /// different user expectations, and collapsing them into one `TIMEOUT` code
  /// is what made every failure look identical to the patient.
  bool get isTimeout =>
      code == codeConnectTimeout || code == codeSendTimeout || code == codeReceiveTimeout;

  factory ApiException.fromDioException(DioException e) {
    final response = e.response;
    final data = response?.data;

    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final errorBody = data['error'] as Map<String, dynamic>;
      return ApiException(
        message: errorBody['message'] as String? ?? 'Something went wrong',
        code: errorBody['code'] as String? ?? 'UNKNOWN_ERROR',
        statusCode: response?.statusCode,
        details: errorBody['details'],
      );
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return const ApiException(
          message: 'Could not reach the server in time. Please check your network and try again.',
          code: codeConnectTimeout,
        );
      case DioExceptionType.sendTimeout:
        return const ApiException(
          message: 'Sending the request took too long. Please try again.',
          code: codeSendTimeout,
        );
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiException(
          message: 'The response took longer than expected. Please try again.',
          code: codeReceiveTimeout,
        );
      case DioExceptionType.connectionError:
        return const ApiException(
          message: 'Could not reach the server. Please check your network connection.',
          code: codeServiceUnavailable,
        );
      case DioExceptionType.badCertificate:
        return const ApiException(
          message: 'The secure connection could not be verified.',
          code: codeCertificateError,
        );
      case DioExceptionType.badResponse:
        return ApiException(
          message: 'The server could not complete the request. Please try again.',
          code: codeHttpError,
          statusCode: response?.statusCode,
        );
      case DioExceptionType.cancel:
        return const ApiException(message: 'Request was cancelled.', code: codeCancelled);
      case DioExceptionType.unknown:
        return ApiException(
          message: 'Unexpected error occurred. Please try again.',
          code: codeUnknown,
          statusCode: response?.statusCode,
        );
    }
  }

  /// Normalizes anything the Dio layer can throw into an [ApiException].
  ///
  /// [ErrorInterceptor] rejects with a `DioException` that merely *carries* an
  /// ApiException in `.error`, so `on ApiException catch` never matches at a
  /// call site — every real failure silently became a generic one. Callers
  /// should use this instead of catching ApiException directly.
  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final inner = error.error;
      if (inner is ApiException) return inner;
      return ApiException.fromDioException(error);
    }
    // Never surface `error.toString()`. Screens render `message` directly, and
    // an arbitrary throwable can carry a file path, a payload fragment, or a
    // plugin's internal state.
    return const ApiException(
      message: 'Unexpected error occurred. Please try again.',
      code: codeUnknown,
    );
  }

  @override
  String toString() => 'ApiException($code): $message';
}

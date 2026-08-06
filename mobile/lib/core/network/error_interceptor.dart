import 'package:dio/dio.dart';

import 'api_exception.dart';

/// Converts every [DioException] into a normalized [ApiException] carried in
/// [DioException.error], so callers only ever need to catch one shape of error.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final apiException = ApiException.fromDioException(err);
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        type: err.type,
        error: apiException,
        stackTrace: err.stackTrace,
      ),
    );
  }
}

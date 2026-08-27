import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';

class ContactApi {
  ContactApi(this._dio);
  final Dio _dio;

  Future<void> submit({
    required String subject,
    required String message,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/contact',
      data: {'subject': subject, 'message': message},
    );
    final envelope = response.data;
    if (envelope == null) {
      throw const ApiException(
        message: 'Empty response from server.',
        code: 'EMPTY_RESPONSE',
      );
    }
    if (envelope['success'] == false) {
      throw const ApiException(
        message: 'Request failed.',
        code: 'BACKEND_FAILURE',
      );
    }
  }
}

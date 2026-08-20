import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/network_log_interceptor.dart';

void main() {
  late List<String> logs;
  late NetworkLogInterceptor interceptor;

  setUp(() {
    logs = [];
    interceptor = NetworkLogInterceptor(logger: logs.add);
  });

  RequestOptions request({
    String path = '/chat/message',
    String method = 'POST',
    Object? data,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? queryParameters,
  }) {
    return RequestOptions(
      path: path,
      baseUrl: 'https://api.example.test',
      method: method,
      data: data,
      headers: headers,
      queryParameters: queryParameters,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 45),
    );
  }

  String output() => logs.join('\n');

  test('suppresses tokens passwords OTP values and sensitive headers', () {
    final options = request(
      path: '/auth/login',
      headers: {
        'Authorization': 'Bearer jwt-access-secret',
        'Cookie': 'session=cookie-secret',
      },
      data: {
        'password': 'patient-password',
        'otp': '482911',
        'verificationCode': 'verification-secret',
        'refreshToken': 'refresh-secret',
        'accessToken': 'access-secret',
        'resetToken': 'reset-secret',
      },
    );

    interceptor.onRequest(options, _RecordingRequestHandler());

    expect(output(), contains('[API] → POST /auth/login'));
    for (final sensitiveValue in [
      'jwt-access-secret',
      'cookie-secret',
      'patient-password',
      '482911',
      'verification-secret',
      'refresh-secret',
      'access-secret',
      'reset-secret',
      'Authorization',
      'Cookie',
    ]) {
      expect(output(), isNot(contains(sensitiveValue)));
    }
  });

  test('suppresses chatbot message reply and metadata bodies', () {
    final options = request(
      data: {
        'message': 'I have severe chest pain',
        'metadata': {'patientName': 'Sensitive Patient'},
      },
    );
    interceptor.onRequest(options, _RecordingRequestHandler());

    final response = Response<dynamic>(
      requestOptions: options,
      statusCode: 200,
      data: {
        'reply': 'Sensitive medical reply',
        'metadata': {'intent': 'symptom_analysis'},
      },
    );
    interceptor.onResponse(response, _RecordingResponseHandler());

    expect(output(), isNot(contains('severe chest pain')));
    expect(output(), isNot(contains('Sensitive Patient')));
    expect(output(), isNot(contains('Sensitive medical reply')));
    expect(output(), isNot(contains('symptom_analysis')));
  });

  test('suppresses Virtual Doctor transcript profile and report data', () {
    final options = request(
      path: '/virtual-doctor/report/private-report-id/download',
      data: {
        'transcript': 'Private Virtual Doctor transcript',
        'sttText': 'Private speech-to-text result',
        'ttsText': 'Private text-to-speech input',
        'profile_snapshot': {'name': 'Patient Name', 'age': 42},
        'patient_profile': {'condition': 'private diagnosis'},
        'reportId': 'private-report-id',
        'downloadUrl': '/reports/private-report-id.pdf',
        'pdfPath': r'C:\patients\private-report.pdf',
      },
    );

    interceptor.onRequest(options, _RecordingRequestHandler());

    expect(
      output(),
      contains(
        '[API] → POST /virtual-doctor/report/:value/download',
      ),
    );
    for (final sensitiveValue in [
      'Private Virtual Doctor transcript',
      'Private speech-to-text result',
      'Private text-to-speech input',
      'Patient Name',
      'age',
      'private diagnosis',
      'private-report-id',
      'private-report.pdf',
    ]) {
      expect(output(), isNot(contains(sensitiveValue)));
    }
  });

  test('suppresses coordinates addresses and query parameters', () {
    final options = request(
      path: '/clinics/search',
      queryParameters: {
        'latitude': 32.2211,
        'longitude': 35.2544,
        'address': 'Private patient address',
      },
      data: {
        'latitude': 32.2211,
        'longitude': 35.2544,
        'address': 'Private patient address',
      },
    );

    interceptor.onRequest(options, _RecordingRequestHandler());

    expect(output(), contains('[API] → POST /clinics/search'));
    expect(output(), isNot(contains('32.2211')));
    expect(output(), isNot(contains('35.2544')));
    expect(output(), isNot(contains('Private patient address')));
    expect(output(), isNot(contains('latitude')));
    expect(output(), isNot(contains('longitude')));
  });

  test('suppresses FormData field values audio names and local file paths', () {
    final formData = FormData.fromMap({
      'patientName': 'Sensitive Patient',
      'audio': MultipartFile.fromString(
        'private audio bytes',
        filename: r'C:\recordings\patient-name.wav',
      ),
    });
    final options = request(path: '/virtual-doctor/transcribe', data: formData);

    interceptor.onRequest(options, _RecordingRequestHandler());

    expect(output(), contains('/virtual-doctor/transcribe'));
    expect(output(), isNot(contains('Sensitive Patient')));
    expect(output(), isNot(contains('private audio bytes')));
    expect(output(), isNot(contains('patient-name.wav')));
    expect(output(), isNot(contains(r'C:\recordings')));
  });

  test('tagging chat.message does not weaken body redaction', () {
    // `ChatbotApi.sendMessage` now sets `network.requestName` so its widened
    // AI timeout is identifiable in the log. The tag must not become a reason
    // to start describing the request.
    final options = request(
      headers: {'Authorization': 'Bearer jwt-access-secret'},
      data: {'message': 'I have severe chest pain', 'latitude': 32.2211},
    );
    options.extra['network.requestName'] = 'chat.message';

    interceptor.onRequest(options, _RecordingRequestHandler());

    expect(output(), contains('[API] → POST /chat/message'));
    expect(output(), isNot(contains('severe chest pain')));
    expect(output(), isNot(contains('32.2211')));
    expect(output(), isNot(contains('jwt-access-secret')));
    expect(output(), isNot(contains('192.168')));
  });

  test('logs the widened chat timeout so a slow AI turn is diagnosable', () {
    final options = RequestOptions(
      path: '/chat/message',
      baseUrl: 'https://api.example.test',
      method: 'POST',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 75),
    );

    interceptor.onRequest(options, _RecordingRequestHandler());

    expect(
      output(),
      contains('timeouts: connect=15000ms, receive=75000ms, send=30000ms'),
    );
  });

  test('does not inspect or crash on malformed unexpected bodies', () {
    final options = request(data: _ThrowingBody());
    final handler = _RecordingRequestHandler();

    expect(() => interceptor.onRequest(options, handler), returnsNormally);
    expect(handler.forwarded, same(options));
  });

  test('keeps method endpoint status duration and timeout metadata visible', () {
    final options = request();
    interceptor.onRequest(options, _RecordingRequestHandler());
    interceptor.onResponse(
      Response<dynamic>(requestOptions: options, statusCode: 201),
      _RecordingResponseHandler(),
    );

    expect(output(), contains('[API] → POST /chat/message'));
    expect(
      output(),
      contains(
        'timeouts: connect=15000ms, receive=30000ms, send=45000ms',
      ),
    );
    expect(output(), contains('[API] ← 201 POST /chat/message'));
    expect(output(), matches(RegExp(r'\(\d+ ms\)')));
  });

  test('forwards requests responses and errors without changing Dio objects', () {
    final options = request();
    final requestHandler = _RecordingRequestHandler();
    interceptor.onRequest(options, requestHandler);

    final response = Response<dynamic>(
      requestOptions: options,
      statusCode: 503,
      data: {'reply': 'private error response'},
    );
    final responseHandler = _RecordingResponseHandler();
    interceptor.onResponse(response, responseHandler);

    final error = DioException(
      requestOptions: options,
      response: response,
      type: DioExceptionType.receiveTimeout,
      message: 'private raw error with token-secret and patient details',
      error: {'transcript': 'private nested error body'},
    );
    final errorHandler = _RecordingErrorHandler();
    interceptor.onError(error, errorHandler);

    expect(requestHandler.forwarded, same(options));
    expect(responseHandler.forwarded, same(response));
    expect(errorHandler.forwarded, same(error));
    expect(
      output(),
      contains(
        '[API] ✖ receiveTimeout POST /chat/message status=503 '
        'category=timeout',
      ),
    );
    expect(output(), isNot(contains('private error response')));
    expect(output(), isNot(contains('token-secret')));
    expect(output(), isNot(contains('patient details')));
    expect(output(), isNot(contains('private nested error body')));
  });
}

class _RecordingRequestHandler extends RequestInterceptorHandler {
  RequestOptions? forwarded;

  @override
  void next(RequestOptions requestOptions) {
    forwarded = requestOptions;
  }
}

class _RecordingResponseHandler extends ResponseInterceptorHandler {
  Response<dynamic>? forwarded;

  @override
  void next(Response<dynamic> response) {
    forwarded = response;
  }
}

class _RecordingErrorHandler extends ErrorInterceptorHandler {
  DioException? forwarded;

  @override
  void next(DioException error) {
    forwarded = error;
  }
}

class _ThrowingBody {
  @override
  String toString() => throw const FormatException('malformed body');
}

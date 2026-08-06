import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/my_reports/data/my_reports_api.dart';
import 'package:mobile/features/my_reports/models/my_report_item.dart';

void main() {
  test('listReportSummaries() hits GET /reports/summaries and parses each row', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': [
          {
            'id': 'summary-1',
            'summary_ar': 'ملخص الحالة',
            'summary_en': 'Patient summary',
            'extracted_text_preview': 'Extracted report text...',
            'model_used': 'qwen2:7b',
            'source_file_type': 'text',
            'created_at': '2026-08-01T09:00:00.000Z',
          },
        ],
      }),
    ]);
    final api = MyReportsApi(fake.dio);

    final result = await api.listReportSummaries();

    expect(fake.requests.single.method, 'GET');
    expect(fake.requests.single.path, '/reports/summaries');
    expect(result, hasLength(1));
    final item = result.single;
    expect(item.id, 'summary-1');
    expect(item.type, MyReportType.reportSummary);
    expect(item.summaryAr, 'ملخص الحالة');
    expect(item.summaryEn, 'Patient summary');
    expect(item.extractedTextPreview, 'Extracted report text...');
    expect(item.modelUsed, 'qwen2:7b');
    expect(item.sourceFileType, 'text');
    expect(item.createdAt, DateTime.parse('2026-08-01T09:00:00.000Z'));
    expect(item.downloadUrl, isNull, reason: 'report_summarizations has no downloadable artifact');
    expect(item.status, isNull);
  });

  test('an empty list parses to an empty result, not an error', () async {
    final fake = _FakeDio([
      _ok({'success': true, 'data': <dynamic>[]}),
    ]);
    final api = MyReportsApi(fake.dio);

    final result = await api.listReportSummaries();

    expect(result, isEmpty);
  });

  test('throws INVALID_RESPONSE when data is not a list', () async {
    final fake = _FakeDio([
      _ok({'success': true, 'data': {'not': 'a list'}}),
    ]);
    final api = MyReportsApi(fake.dio);

    await expectLater(
      api.listReportSummaries(),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
    );
  });

  test('throws BACKEND_FAILURE on success:false without leaking the raw body', () async {
    final fake = _FakeDio([
      _ok({
        'success': false,
        'data': {'internal': 'details'},
      }),
    ]);
    final api = MyReportsApi(fake.dio);

    await expectLater(
      api.listReportSummaries(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'BACKEND_FAILURE')
            .having((e) => e.message, 'message', isNot(contains('internal'))),
      ),
    );
  });

  test('a 401 from the backend propagates untouched and normalizes to UNAUTHORIZED', () async {
    final fake = _FakeDio([
      _httpError(
        statusCode: 401,
        body: {
          'success': false,
          'error': {'code': 'UNAUTHORIZED', 'message': 'Access token required'},
        },
      ),
    ]);
    final api = MyReportsApi(fake.dio);

    final dioError = await _captureDioException(api.listReportSummaries());
    final normalized = ApiException.fromDioException(dioError);

    expect(normalized.code, 'UNAUTHORIZED');
  });

  test('a receive timeout propagates untouched and normalizes to codeReceiveTimeout', () async {
    final fake = _FakeDio([_timeout()]);
    final api = MyReportsApi(fake.dio);

    final dioError = await _captureDioException(api.listReportSummaries());

    expect(ApiException.fromDioException(dioError).code, ApiException.codeReceiveTimeout);
  });

  test('client does not print or manually log response bodies', () async {
    final fake = _FakeDio([
      _ok({
        'success': true,
        'data': [
          {
            'id': 'summary-1',
            'summary_ar': 'معلومات طبية خاصة',
            'summary_en': 'private medical summary',
            'extracted_text_preview': 'private extracted text',
            'model_used': 'qwen2:7b',
            'source_file_type': 'text',
            'created_at': '2026-08-01T09:00:00.000Z',
          },
        ],
      }),
    ]);
    final api = MyReportsApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      api.listReportSummaries,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

Future<DioException> _captureDioException(Future<Object?> future) async {
  try {
    await future;
  } on DioException catch (error) {
    return error;
  }
  fail('Expected a DioException to be thrown.');
}

class _QueuedResponse {
  const _QueuedResponse.ok(this.body) : error = null;
  const _QueuedResponse.error(this.error) : body = null;

  final Map<String, dynamic>? body;
  final DioException Function(RequestOptions options)? error;
}

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok(body);

_QueuedResponse _httpError({required int statusCode, required Map<String, dynamic> body}) {
  return _QueuedResponse.error(
    (options) => DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: statusCode,
        data: body,
      ),
    ),
  );
}

_QueuedResponse _timeout() {
  return _QueuedResponse.error(
    (options) => DioException(requestOptions: options, type: DioExceptionType.receiveTimeout),
  );
}

class _FakeDio {
  _FakeDio(List<_QueuedResponse> responses) : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(_RecordedRequest(method: options.method, path: options.path, data: options.data));
          final next = responses.removeAt(0);
          if (next.error != null) {
            handler.reject(next.error!(options));
          } else {
            handler.resolve(
              Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: next.body),
            );
          }
        },
      ),
    );
  }

  final Dio dio;
  final requests = <_RecordedRequest>[];
}

class _RecordedRequest {
  const _RecordedRequest({required this.method, required this.path, required this.data});

  final String method;
  final String path;
  final dynamic data;
}

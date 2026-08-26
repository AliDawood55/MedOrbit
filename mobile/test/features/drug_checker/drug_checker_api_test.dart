import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/drug_checker/data/drug_checker_api.dart';
import 'package:mobile/features/drug_checker/models/drug_check_result.dart';

Future<DioException> _captureDioException(Future<Object?> future) async {
  try {
    await future;
  } on DioException catch (error) {
    return error;
  }
  fail('Expected a DioException to be thrown.');
}

void main() {
  test('checkInteractions() POSTs the authenticated backend gateway with exactly { medication_names }', () async {
    final fake = _FakeDio([
      _ok({
        'has_interactions': true,
        'interaction_count': 1,
        'interactions': [
          {
            'drug_1': {'id': 'd1', 'name_en': 'Aspirin', 'name_ar': 'أسبرين'},
            'drug_2': {'id': 'd2', 'name_en': 'Warfarin', 'name_ar': 'وارفارين'},
            'severity': 'severe',
            'description': 'Severe - increases bleeding risk significantly',
          },
        ],
        'severity_summary': {'severe': 1},
      }),
    ]);
    final api = DrugCheckerApi(fake.dio);

    final result = await api.checkInteractions(['Aspirin', 'Warfarin']);

    expect(fake.requests.single.method, 'POST');
    expect(fake.requests.single.path, '/ai/drug-interactions');
    expect(fake.requests.single.data, {
      'medication_names': ['Aspirin', 'Warfarin'],
    });
    expect(result.hasInteractions, isTrue);
    expect(result.interactionCount, 1);
    expect(result.interactions.single.severity, DrugSeverity.severe);
    expect(result.interactions.single.drug1NameEn, 'Aspirin');
    expect(result.interactions.single.drug2NameEn, 'Warfarin');
    expect(result.interactions.single.description, 'Severe - increases bleeding risk significantly');
    expect(result.severitySummary, {'severe': 1});
  });

  test('parses a no-interactions result', () async {
    final fake = _FakeDio([
      _ok({
        'has_interactions': false,
        'interaction_count': 0,
        'interactions': <dynamic>[],
        'severity_summary': <String, dynamic>{},
      }),
    ]);
    final api = DrugCheckerApi(fake.dio);

    final result = await api.checkInteractions(['Paracetamol', 'Ibuprofen']);

    expect(result.hasInteractions, isFalse);
    expect(result.interactions, isEmpty);
  });

  test('an unrecognized severity falls back to unknown rather than throwing', () async {
    final fake = _FakeDio([
      _ok({
        'has_interactions': true,
        'interaction_count': 1,
        'interactions': [
          {
            'drug_1': {'name_en': 'A'},
            'drug_2': {'name_en': 'B'},
            'severity': 'something_new',
            'description': 'Unclassified interaction.',
          },
        ],
        'severity_summary': <String, dynamic>{},
      }),
    ]);
    final api = DrugCheckerApi(fake.dio);

    final result = await api.checkInteractions(['A', 'B']);

    expect(result.interactions.single.severity, DrugSeverity.unknown);
  });

  test('a FastAPI {"detail": ...} 500 body normalizes to a safe generic error with no raw text', () async {
    final fake = _FakeDio([
      _httpError(statusCode: 500, body: {'detail': 'Drug check failed: internal engine error'}),
    ]);
    final api = DrugCheckerApi(fake.dio);

    final dioError = await _captureDioException(api.checkInteractions(['Aspirin', 'Warfarin']));
    final normalized = ApiException.fromDioException(dioError);

    expect(normalized.code, ApiException.codeHttpError);
    expect(normalized.message, isNot(contains('Drug check failed')));
    expect(normalized.message, isNot(contains('internal engine error')));
  });

  test('a receive timeout propagates untouched and normalizes to codeReceiveTimeout', () async {
    final fake = _FakeDio([_timeout()]);
    final api = DrugCheckerApi(fake.dio);

    final dioError = await _captureDioException(api.checkInteractions(['Aspirin', 'Warfarin']));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeReceiveTimeout);
  });

  test('an unreachable service normalizes to codeServiceUnavailable', () async {
    final fake = _FakeDio([_connectionError()]);
    final api = DrugCheckerApi(fake.dio);

    final dioError = await _captureDioException(api.checkInteractions(['Aspirin', 'Warfarin']));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeServiceUnavailable);
  });

  test('client does not print or manually log request or response bodies', () async {
    final fake = _FakeDio([
      _ok({
        'has_interactions': true,
        'interaction_count': 1,
        'interactions': [
          {
            'drug_1': {'name_en': 'A private medication name'},
            'drug_2': {'name_en': 'Another private one'},
            'severity': 'mild',
            'description': 'Minor interaction.',
          },
        ],
        'severity_summary': {'mild': 1},
      }),
    ]);
    final api = DrugCheckerApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      () => api.checkInteractions(['A private medication name', 'Another private one']),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

class _QueuedResponse {
  const _QueuedResponse.ok(this.body) : error = null;
  const _QueuedResponse.error(this.error) : body = null;

  final Map<String, dynamic>? body;
  final DioException Function(RequestOptions options)? error;
}

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok({
      'success': true,
      'data': body,
    });

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

_QueuedResponse _connectionError() {
  return _QueuedResponse.error(
    (options) => DioException(requestOptions: options, type: DioExceptionType.connectionError),
  );
}

class _FakeDio {
  _FakeDio(List<_QueuedResponse> responses) : dio = Dio(BaseOptions(baseUrl: 'https://ai.example.test')) {
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

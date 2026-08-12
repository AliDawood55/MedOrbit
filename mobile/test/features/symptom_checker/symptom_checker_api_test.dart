import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/symptom_checker/data/symptom_checker_api.dart';
import 'package:mobile/features/symptom_checker/models/symptom_check_result.dart';

Future<DioException> _captureDioException(Future<Object?> future) async {
  try {
    await future;
  } on DioException catch (error) {
    return error;
  }
  fail('Expected a DioException to be thrown.');
}

void main() {
  test('checkSymptoms() POSTs /triage with exactly { symptoms }', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'triage-1',
        'symptoms': ['headache', 'fever'],
        'triage_level': 'routine',
        'recommended_specialty_id': 'sp-1',
        'recommended_specialty_name_en': 'General Practice',
        'recommended_specialty_name_ar': 'طب عام',
        'confidence_score': 0.42,
        'specialty_scores': {'General Practice': 4.2},
        'matched_keywords': ['headache'],
        'recommendations': 'See a general practitioner if symptoms persist.',
        'follow_up_action': 'book_appointment',
      }),
    ]);
    final api = SymptomCheckerApi(fake.dio);

    final result = await api.checkSymptoms(['headache', 'fever']);

    expect(fake.requests.single.method, 'POST');
    expect(fake.requests.single.path, '/ai/triage');
    expect(fake.requests.single.data, {
      'symptoms': ['headache', 'fever'],
    });
    expect(result.id, 'triage-1');
    expect(result.triageLevel, TriageLevel.routine);
    expect(result.recommendedSpecialtyNameEn, 'General Practice');
    expect(result.confidenceScore, 0.42);
    expect(result.recommendations, 'See a general practitioner if symptoms persist.');
  });

  test('parses an emergency result', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'triage-2',
        'symptoms': ['severe chest pain'],
        'triage_level': 'emergency',
        'recommended_specialty_id': null,
        'recommended_specialty_name_en': null,
        'recommended_specialty_name_ar': null,
        'confidence_score': 1.0,
        'specialty_scores': <String, dynamic>{},
        'matched_keywords': ['severe chest pain'],
        'recommendations': 'Emergency symptoms detected. Please go to the nearest emergency room immediately.',
        'follow_up_action': 'visit_emergency_immediately',
      }),
    ]);
    final api = SymptomCheckerApi(fake.dio);

    final result = await api.checkSymptoms(['severe chest pain']);

    expect(result.triageLevel, TriageLevel.emergency);
    expect(result.recommendedSpecialtyNameEn, isNull);
  });

  test('an unrecognized triage_level falls back to routine rather than throwing', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'triage-3',
        'symptoms': ['cough'],
        'triage_level': 'something_new',
        'confidence_score': 0.2,
        'recommendations': 'General guidance.',
        'follow_up_action': 'book_appointment',
      }),
    ]);
    final api = SymptomCheckerApi(fake.dio);

    final result = await api.checkSymptoms(['cough']);

    expect(result.triageLevel, TriageLevel.routine);
  });

  test('a FastAPI {"detail": ...} 500 body normalizes to a safe generic error with no raw text', () async {
    final fake = _FakeDio([
      _httpError(statusCode: 500, body: {'detail': 'Triage failed: internal engine error'}),
    ]);
    final api = SymptomCheckerApi(fake.dio);

    final dioError = await _captureDioException(api.checkSymptoms(['headache']));
    final normalized = ApiException.fromDioException(dioError);

    expect(normalized.code, ApiException.codeHttpError);
    expect(normalized.message, isNot(contains('Triage failed')));
    expect(normalized.message, isNot(contains('internal engine error')));
  });

  test('a receive timeout propagates untouched and normalizes to codeReceiveTimeout', () async {
    final fake = _FakeDio([_timeout()]);
    final api = SymptomCheckerApi(fake.dio);

    final dioError = await _captureDioException(api.checkSymptoms(['headache']));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeReceiveTimeout);
  });

  test('an unreachable service normalizes to codeServiceUnavailable', () async {
    final fake = _FakeDio([_connectionError()]);
    final api = SymptomCheckerApi(fake.dio);

    final dioError = await _captureDioException(api.checkSymptoms(['headache']));

    expect(ApiException.fromDioException(dioError).code, ApiException.codeServiceUnavailable);
  });

  test('client does not print or manually log request or response bodies', () async {
    final fake = _FakeDio([
      _ok({
        'id': 'triage-4',
        'symptoms': ['a private symptom description'],
        'triage_level': 'routine',
        'confidence_score': 0.1,
        'recommendations': 'General guidance.',
        'follow_up_action': 'book_appointment',
      }),
    ]);
    final api = SymptomCheckerApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      () => api.checkSymptoms(['a private symptom description']),
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

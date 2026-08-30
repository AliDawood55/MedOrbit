import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';

void main() {
  test(
    'start uses authenticated gateway identity and parses resumed session',
    () async {
      final harness = _DioHarness([
        {
          'success': true,
          'data': {
            'session_id': 'existing-session',
            'reply': '',
            'phase': 'assessment',
            'language': 'ar',
            'resumed': true,
            'entitlement_source': 'free_active_session',
            'messages': [
              {'role': 'assistant', 'text': 'Previous question'},
              {'role': 'user', 'text': 'Previous answer'},
            ],
          },
        },
      ]);

      final result = await VirtualDoctorApi(harness.dio).start(language: 'ar');

      expect(harness.requests.single.method, 'POST');
      expect(harness.requests.single.path, '/virtual-doctor/start');
      expect(harness.requests.single.data, {'language': 'ar'});
      expect(
        (harness.requests.single.data as Map).keys,
        isNot(contains('user_id')),
      );
      expect(
        (harness.requests.single.data as Map).keys,
        isNot(contains('is_pro')),
      );
      expect(result.resumed, isTrue);
      expect(result.sessionId, 'existing-session');
      expect(result.messages, hasLength(2));
    },
  );

  test(
    'manual finalization is scoped only by the controller-owned session ID',
    () async {
      final harness = _DioHarness([
        {'success': true, 'data': <String, dynamic>{}},
      ]);

      await VirtualDoctorApi(harness.dio).endSession('session-1');

      expect(harness.requests.single.method, 'POST');
      expect(
        harness.requests.single.path,
        '/virtual-doctor/session/session-1/end',
      );
      expect(harness.requests.single.data, isNull);
    },
  );
}

class _DioHarness {
  _DioHarness(List<Map<String, dynamic>> responses)
    : dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(
            _Request(
              method: options.method,
              path: options.path,
              data: options.data,
            ),
          );
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: 200,
              data: responses.removeAt(0),
            ),
          );
        },
      ),
    );
  }

  final Dio dio;
  final requests = <_Request>[];
}

class _Request {
  const _Request({
    required this.method,
    required this.path,
    required this.data,
  });

  final String method;
  final String path;
  final Object? data;
}

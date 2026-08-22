import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/prescriptions/data/prescriptions_api.dart';

void main() {
  group('PrescriptionsApi.list', () {
    test('parses a normal envelope', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {
              'id': '1',
              'prescription_number': 'RX-1',
              'prescription_date': '2026-08-01',
              'status': 'active',
              'items': const <Map<String, dynamic>>[],
            },
          ],
        }),
      );
      final api = PrescriptionsApi(fake.dio);

      final prescriptions = await api.list();

      expect(prescriptions, hasLength(1));
      expect(prescriptions.single.prescriptionNumber, 'RX-1');
    });

    test('throws ApiException(INVALID_RESPONSE) when data is not a list', () async {
      final fake = _FakeDio(_ok({'data': {'not': 'a list'}}));
      final api = PrescriptionsApi(fake.dio);

      await expectLater(
        api.list(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('throws ApiException(INVALID_RESPONSE) instead of returning an empty history for a malformed envelope', () async {
      final fake = _FakeDio(_ok({}));
      final api = PrescriptionsApi(fake.dio);

      await expectLater(
        api.list(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('fails the whole fetch on a malformed entry rather than silently dropping it', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {
              'id': '1',
              'prescription_number': 'RX-1',
              'prescription_date': '2026-08-01',
              'status': 'active',
            },
            42,
          ],
        }),
      );
      final api = PrescriptionsApi(fake.dio);

      await expectLater(
        api.list(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });
  });
}

class _QueuedResponse {
  const _QueuedResponse.ok(this.body);
  final Map<String, dynamic> body;
}

_QueuedResponse _ok(Map<String, dynamic> body) => _QueuedResponse.ok(body);

class _FakeDio {
  _FakeDio(_QueuedResponse response) : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response<Map<String, dynamic>>(requestOptions: options, statusCode: 200, data: response.body));
        },
      ),
    );
  }

  final Dio dio;
}

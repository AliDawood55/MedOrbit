import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/network/error_interceptor.dart';
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

  group('PrescriptionsApi.downloadPdf', () {
    final validPdfBytes = [...'%PDF-1.4 fake pdf body'.codeUnits];

    test('requests GET /prescriptions/:id/pdf as bytes and returns valid PDF bytes', () async {
      final fake = _FakeBytesDio(data: validPdfBytes);
      final api = PrescriptionsApi(fake.dio);

      final bytes = await api.downloadPdf('rx-1');

      expect(bytes, validPdfBytes);
      expect(fake.lastRequest?.path, '/prescriptions/rx-1/pdf');
      expect(fake.lastRequest?.responseType, ResponseType.bytes);
    });

    test('throws INVALID_RESPONSE for an empty body', () async {
      final fake = _FakeBytesDio(data: const []);
      final api = PrescriptionsApi(fake.dio);

      await expectLater(
        api.downloadPdf('rx-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('throws INVALID_RESPONSE for a non-PDF content type', () async {
      final fake = _FakeBytesDio(
        data: validPdfBytes,
        headers: {
          'content-type': ['application/json'],
        },
      );
      final api = PrescriptionsApi(fake.dio);

      await expectLater(
        api.downloadPdf('rx-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('throws INVALID_RESPONSE when bytes do not start with the PDF signature', () async {
      final fake = _FakeBytesDio(data: 'not a pdf'.codeUnits);
      final api = PrescriptionsApi(fake.dio);

      await expectLater(
        api.downloadPdf('rx-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('propagates a normalized ApiException on a server error', () async {
      final fake = _FakeBytesDio(statusCode: 404);
      final api = PrescriptionsApi(fake.dio);

      // ErrorInterceptor carries the normalized ApiException inside the
      // rejected DioException's `.error` (see api_exception.dart) rather than
      // throwing it directly — ApiException.from() is how real callers unwrap it.
      try {
        await api.downloadPdf('rx-1');
        fail('expected downloadPdf to throw');
      } catch (e) {
        expect(ApiException.from(e).statusCode, 404);
      }
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

/// A fake Dio for [PrescriptionsApi.downloadPdf], which requests
/// `responseType: bytes`. Records the last request so tests can assert the
/// path/response type actually sent, and routes non-2xx status codes through
/// [ErrorInterceptor] the same way the real client does.
class _FakeBytesDio {
  _FakeBytesDio({
    int statusCode = 200,
    List<int>? data,
    Map<String, List<String>>? headers,
  }) : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    // ErrorInterceptor must be added before the responder below: Dio walks
    // the error chain back through interceptors already entered on the
    // request side, so one added after the interceptor that rejects never
    // sees the error.
    dio.interceptors.add(ErrorInterceptor());
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          lastRequest = options;
          if (statusCode >= 200 && statusCode < 300) {
            handler.resolve(
              Response<List<int>>(
                requestOptions: options,
                statusCode: statusCode,
                data: data,
                headers: Headers.fromMap(
                  headers ??
                      {
                        'content-type': ['application/pdf'],
                      },
                ),
              ),
            );
          } else {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: statusCode),
                type: DioExceptionType.badResponse,
              ),
              true,
            );
          }
        },
      ),
    );
  }

  final Dio dio;
  RequestOptions? lastRequest;
}

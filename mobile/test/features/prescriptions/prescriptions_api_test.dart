import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/prescriptions/data/prescriptions_api.dart';

void main() {
  test(
    'downloads a prescription PDF through the authenticated API path',
    () async {
      final fake = _FakeDio([37, 80, 68, 70]);
      final bytes = await PrescriptionsApi(
        fake.dio,
      ).downloadPdf('prescription-1');
      expect(fake.path, '/prescriptions/prescription-1/pdf');
      expect(bytes, [37, 80, 68, 70]);
      expect(fake.responseType, ResponseType.bytes);
    },
  );
}

class _FakeDio {
  _FakeDio(this.body) : dio = Dio() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.path;
          responseType = options.responseType;
          handler.resolve(
            Response<List<int>>(
              requestOptions: options,
              statusCode: 200,
              data: body,
            ),
          );
        },
      ),
    );
  }
  final List<int> body;
  final Dio dio;
  String? path;
  ResponseType? responseType;
}

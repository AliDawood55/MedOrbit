import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/contact/data/contact_api.dart';

void main() {
  test(
    'submits only subject and message using the authenticated contact endpoint',
    () async {
      final fake = _FakeDio({
        'success': true,
        'data': {'id': 'contact-1'},
      });
      await ContactApi(fake.dio).submit(
        subject: 'Help with appointment',
        message: 'Please contact me about my booking.',
      );
      expect(fake.path, '/contact');
      expect(fake.data, {
        'subject': 'Help with appointment',
        'message': 'Please contact me about my booking.',
      });
    },
  );
}

class _FakeDio {
  _FakeDio(this.body) : dio = Dio() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.path;
          data = options.data;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: body,
            ),
          );
        },
      ),
    );
  }
  final Map<String, dynamic> body;
  final Dio dio;
  String? path;
  Object? data;
}

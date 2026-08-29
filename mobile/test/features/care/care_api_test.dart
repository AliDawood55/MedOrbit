import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/care/data/care_api.dart';

void main() {
  group('CareApi.myDoctors', () {
    test('parses a normal envelope', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {'id': 'doctor-1', 'first_name_en': 'Ahmad', 'last_name_en': 'Mahmoud'},
          ],
        }),
      );
      final api = CareApi(fake.dio);

      final doctors = await api.myDoctors();

      expect(doctors, hasLength(1));
      expect(doctors.single.id, 'doctor-1');
    });

    test('an empty list is a legitimate "no active doctors" response', () async {
      final fake = _FakeDio(_ok({'data': <Map<String, dynamic>>[]}));
      final api = CareApi(fake.dio);

      final doctors = await api.myDoctors();

      expect(doctors, isEmpty);
    });

    test('throws ApiException(INVALID_RESPONSE) when data is not a list', () async {
      final fake = _FakeDio(_ok({'data': {'not': 'a list'}}));
      final api = CareApi(fake.dio);

      await expectLater(
        api.myDoctors(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('throws ApiException(INVALID_RESPONSE) when data is entirely missing', () async {
      final fake = _FakeDio(_ok({}));
      final api = CareApi(fake.dio);

      await expectLater(
        api.myDoctors(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('fails the whole fetch on a malformed entry rather than dropping it', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {'id': 'doctor-1'},
            'not-an-object',
          ],
        }),
      );
      final api = CareApi(fake.dio);

      await expectLater(
        api.myDoctors(),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('a well-formed entry missing the required UUID throws FormatException', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {'email': 'doc@example.com'},
          ],
        }),
      );
      final api = CareApi(fake.dio);

      await expectLater(api.myDoctors(), throwsA(isA<FormatException>()));
    });
  });

  group('CareApi.sharedNotes', () {
    test('parses a normal envelope', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {'id': 'note-1', 'clinical_notes': 'Doing well.'},
          ],
        }),
      );
      final api = CareApi(fake.dio);

      final notes = await api.sharedNotes('doctor-1');

      expect(notes, hasLength(1));
      expect(notes.single.clinicalNotes, 'Doing well.');
    });

    test('an empty list is legitimate "no shared notes"', () async {
      final fake = _FakeDio(_ok({'data': <Map<String, dynamic>>[]}));
      final api = CareApi(fake.dio);

      final notes = await api.sharedNotes('doctor-1');

      expect(notes, isEmpty);
    });

    test('throws ApiException(INVALID_RESPONSE) for a malformed envelope, never []', () async {
      final fake = _FakeDio(_ok({'data': 'not-a-list'}));
      final api = CareApi(fake.dio);

      await expectLater(
        api.sharedNotes('doctor-1'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE')),
      );
    });

    test('a malformed note entry fails the fetch rather than disappearing silently', () async {
      final fake = _FakeDio(
        _ok({
          'data': [
            {'id': 'note-1'},
            {'record_type': 'consultation'}, // missing id
          ],
        }),
      );
      final api = CareApi(fake.dio);

      await expectLater(api.sharedNotes('doctor-1'), throwsA(isA<FormatException>()));
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

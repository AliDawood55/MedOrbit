import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/models/auth_result_model.dart';

Map<String, dynamic> _validJson() => {
  'user': {'id': 'u-1', 'email': 'a@b.com', 'role': 'patient', 'name': 'Alex'},
  'accessToken': 'access-token-value',
  'refreshToken': 'refresh-token-value',
};

void main() {
  group('AuthResultModel.fromJson', () {
    test('maps a normal payload exactly', () {
      final result = AuthResultModel.fromJson(_validJson());

      expect(result.user.id, 'u-1');
      expect(result.accessToken, 'access-token-value');
      expect(result.refreshToken, 'refresh-token-value');
    });

    test('throws FormatException, not a TypeError, when user is missing', () {
      final json = _validJson()..remove('user');

      expect(() => AuthResultModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when user is the wrong shape', () {
      final json = _validJson()..['user'] = 'not-an-object';

      expect(() => AuthResultModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing access token rather than defaulting to empty string', () {
      final json = _validJson()..remove('accessToken');

      expect(() => AuthResultModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing refresh token', () {
      final json = _validJson()..remove('refreshToken');

      expect(() => AuthResultModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a numeric access token instead of silently stringifying it', () {
      final json = _validJson()..['accessToken'] = 123456;

      expect(() => AuthResultModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for an empty-string access token', () {
      final json = _validJson()..['accessToken'] = '';

      expect(() => AuthResultModel.fromJson(json), throwsA(isA<FormatException>()));
    });
  });
}

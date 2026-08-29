import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/common/data/admin_response.dart';
import 'package:mobile/features/admin/common/models/admin_parsing.dart';

void main() {
  group('adminEnvelopeData', () {
    test('unwraps a successful envelope', () {
      expect(
        adminEnvelopeData({'success': true, 'data': 42}),
        42,
      );
    });

    test('a non-map body is an invalid response', () {
      expect(
        () => adminEnvelopeData('not json'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('an envelope without success:true is an invalid response', () {
      expect(
        () => adminEnvelopeData({'data': <String, dynamic>{}}),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('success:false carries the server code but not its message', () {
      Object? thrown;
      try {
        adminEnvelopeData({
          'success': false,
          'error': {
            'code': 'INVITATION_EXISTS',
            'message': 'An active invitation already exists for a@b.test',
          },
        });
      } catch (error) {
        thrown = error;
      }

      final failure = thrown as ApiException;
      expect(failure.code, 'INVITATION_EXISTS');
      // The backend quotes account emails in admin error text; it must never
      // reach a rendered string.
      expect(failure.message.contains('a@b.test'), isFalse);
    });

    test('success:false without a usable code falls back to BACKEND_FAILURE', () {
      expect(
        () => adminEnvelopeData({'success': false, 'error': 'boom'}),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'BACKEND_FAILURE'),
        ),
      );
    });
  });

  group('adminEnvelopeObject / adminEnvelopeList', () {
    test('object and list shapes are parsed', () {
      expect(
        adminEnvelopeObject({
          'success': true,
          'data': {'id': 'a'},
        }),
        {'id': 'a'},
      );
      expect(
        adminEnvelopeList({
          'success': true,
          'data': [
            {'id': 'a'},
            {'id': 'b'},
          ],
        }).length,
        2,
      );
    });

    test('a list containing a non-object entry fails the whole read', () {
      // An operational queue must never be silently shortened: an admin acting
      // on "everything pending" has to see all of it or none of it.
      expect(
        () => adminEnvelopeList({
          'success': true,
          'data': [
            {'id': 'a'},
            'oops',
          ],
        }),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('a list where an object was expected is an invalid response', () {
      expect(
        () => adminEnvelopeObject({'success': true, 'data': <dynamic>[]}),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => adminEnvelopeList({'success': true, 'data': <String, dynamic>{}}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('admin scalar parsing', () {
    test('accepts the string form Postgres sends for uncast COUNT(*)', () {
      expect(adminInt('32'), 32);
      expect(adminInt(32), 32);
      expect(adminInt(32.0), 32);
      expect(adminOptionalDouble('4.50'), 4.5);
    });

    test('never invents a number from unparseable input', () {
      expect(adminOptionalInt('twelve'), isNull);
      expect(adminOptionalInt(null), isNull);
      expect(adminOptionalInt(true), isNull);
      expect(adminInt('twelve'), 0);
      expect(adminOptionalDouble('n/a'), isNull);
    });

    test('a missing boolean never reads as true', () {
      expect(adminBool(null), isFalse);
      expect(adminBool('yes'), isFalse);
      expect(adminBool(1), isFalse);
      expect(adminBool(true), isTrue);
      expect(adminBool('true'), isTrue);
      expect(adminBool('f'), isFalse);
    });

    test('required strings fail loudly rather than coercing', () {
      expect(
        () => adminRequireString({'id': 7}, 'id'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => adminRequireString({'id': '  '}, 'id'),
        throwsA(isA<FormatException>()),
      );
      expect(adminRequireString({'id': 'abc'}, 'id'), 'abc');
    });

    test('optional strings drop blanks, numbers and structures', () {
      expect(adminOptionalString({'a': '  x '}, 'a'), 'x');
      expect(adminOptionalString({'a': '   '}, 'a'), isNull);
      expect(adminOptionalString({'a': 3}, 'a'), isNull);
      expect(adminOptionalString({'a': <String>[]}, 'a'), isNull);
      expect(adminOptionalString(const {}, 'a'), isNull);
    });

    test('dates parse from ISO strings only', () {
      expect(
        adminRequireDate({'at': '2026-03-04T10:00:00Z'}, 'at'),
        DateTime.utc(2026, 3, 4, 10),
      );
      expect(adminOptionalDate(1700000000), isNull);
      expect(
        () => adminRequireDate({'at': 'not-a-date'}, 'at'),
        throwsA(isA<FormatException>()),
      );
    });

    test('name joining skips blanks on either side', () {
      expect(adminJoinName('Lina', 'Haddad'), 'Lina Haddad');
      expect(adminJoinName(null, 'Haddad'), 'Haddad');
      expect(adminJoinName('  ', '  '), '');
    });
  });
}

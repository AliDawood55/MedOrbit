import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/models/user_model.dart';

void main() {
  group('UserModel.fromJson', () {
    test('maps a normal payload exactly', () {
      final user = UserModel.fromJson({
        'id': 'u-1',
        'email': 'patient@example.com',
        'role': 'patient',
        'name': 'Alex Doe',
      });

      expect(user.id, 'u-1');
      expect(user.email, 'patient@example.com');
      expect(user.role, 'patient');
      expect(user.name, 'Alex Doe');
    });

    test('tolerates a null/missing name', () {
      final withNullName = UserModel.fromJson({'id': 'u-1', 'email': 'a@b.com', 'role': 'patient', 'name': null});
      final withoutName = UserModel.fromJson({'id': 'u-1', 'email': 'a@b.com', 'role': 'patient'});

      expect(withNullName.name, isNull);
      expect(withoutName.name, isNull);
    });

    // `id` is a Postgres UUID column (`db/01_base_tables.sql`'s `users`
    // table) — the contract never allows a numeric id, so unlike
    // appointment/prescription scalar ids, a number here must fail rather
    // than being silently coerced into a string that looks plausible.
    test('throws FormatException for a numeric id instead of coercing it to a string', () {
      expect(
        () => UserModel.fromJson({'id': 12345, 'email': 'a@b.com', 'role': 'patient'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException, not a TypeError, for a null id', () {
      expect(
        () => UserModel.fromJson({'id': null, 'email': 'a@b.com', 'role': 'patient'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException for a missing email', () {
      expect(
        () => UserModel.fromJson({'id': 'u-1', 'role': 'patient'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when email is a numeric value instead of coercing it to a string', () {
      expect(
        () => UserModel.fromJson({'id': 'u-1', 'email': 12345, 'role': 'patient'}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when role is a boolean instead of coercing it to a string', () {
      expect(
        () => UserModel.fromJson({'id': 'u-1', 'email': 'a@b.com', 'role': true}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when role is a structured Map instead of a scalar', () {
      expect(
        () => UserModel.fromJson({'id': 'u-1', 'email': 'a@b.com', 'role': {'nested': 'object'}}),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when email is a List', () {
      expect(
        () => UserModel.fromJson({'id': 'u-1', 'email': ['a@b.com'], 'role': 'patient'}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

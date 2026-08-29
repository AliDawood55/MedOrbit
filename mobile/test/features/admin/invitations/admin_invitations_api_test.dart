import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/invitations/data/admin_invitations_api.dart';
import 'package:mobile/features/admin/invitations/models/admin_invitation.dart';

import '../admin_test_support.dart';

Map<String, dynamic> _invitation({
  String id = 'inv-1',
  String status = 'pending',
  String expiresAt = '2026-03-01T09:00:00Z',
}) => {
  'id': id,
  'email': 'invited@example.test',
  'status': status,
  'expires_at': expiresAt,
  'accepted_at': null,
  'accepted_by_user_id': null,
  'revoked_at': null,
  'revoked_by_user_id': null,
  'invited_by_user_id': 'super-1',
  'created_at': '2026-02-22T09:00:00Z',
  'updated_at': '2026-02-22T09:00:00Z',
};

void main() {
  test('uses the exact invitation routes, methods and payloads', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_invitation()],
      })
      ..enqueue({
        'success': true,
        'data': {
          'invitation': _invitation(),
          'delivery': 'sent',
          'acceptance_url':
              'https://app.example.test/admin-invitation-accept.html?token=abc123',
        },
      })
      ..enqueue({'success': true, 'data': _invitation(status: 'revoked')})
      ..enqueue({'success': true, 'data': <String, dynamic>{}});

    final api = AdminInvitationsApi(dio.dio);
    await api.list();
    await api.create('  Invited@Example.test ');
    await api.revoke('inv-1');
    await api.accept('abc123');

    expect(dio.paths, [
      '/admin/invitations',
      '/admin/invitations',
      '/admin/invitations/inv-1',
      '/admin/invitations/accept',
    ]);
    expect(dio.methods, ['GET', 'POST', 'DELETE', 'POST']);
    // The service normalizes the email server-side; sending it normalized
    // keeps the client's own duplicate detection honest.
    expect(dio.bodies[1], {'email': 'invited@example.test'});
    expect(dio.bodies[3], {'token': 'abc123'});
  });

  test('the creation response carries the one-time link and delivery state', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {
          'invitation': _invitation(),
          'delivery': 'manual',
          'acceptance_url':
              'https://app.example.test/admin-invitation-accept.html?token=abc123',
        },
      });

    final creation = await AdminInvitationsApi(dio.dio).create('a@b.test');

    expect(creation.delivered, isFalse);
    expect(creation.acceptanceUrl, contains('token=abc123'));
    expect(creation.invitation.email, 'invited@example.test');
  });

  test('a duplicate invitation surfaces INVITATION_EXISTS only', () async {
    final dio = RecordingDio()..enqueueFailure(409, 'INVITATION_EXISTS');

    try {
      await AdminInvitationsApi(dio.dio).create('a@b.test');
      fail('expected a failure');
    } catch (error) {
      expect(ApiException.from(error).code, 'INVITATION_EXISTS');
    }
  });

  test('an ordinary admin calling a super-admin route gets FORBIDDEN', () async {
    final dio = RecordingDio()..enqueueFailure(403, 'FORBIDDEN');

    try {
      await AdminInvitationsApi(dio.dio).list();
      fail('expected a failure');
    } catch (error) {
      expect(ApiException.from(error).code, 'FORBIDDEN');
    }
  });

  group('AdminInvitation', () {
    test('parses each lifecycle status', () {
      for (final entry in {
        'pending': AdminInvitationStatus.pending,
        'accepted': AdminInvitationStatus.accepted,
        'revoked': AdminInvitationStatus.revoked,
        'expired': AdminInvitationStatus.expired,
        'weird': AdminInvitationStatus.unknown,
      }.entries) {
        expect(
          AdminInvitation.fromJson(_invitation(status: entry.key)).status,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('a pending row past its expiry reads as expired for the viewer', () {
      // The service expires rows lazily, so the column can still say pending
      // while acceptInvitation would answer INVITATION_EXPIRED.
      final invitation = AdminInvitation.fromJson(
        _invitation(expiresAt: '2026-02-23T09:00:00Z'),
      );

      expect(invitation.isExpiredAt(DateTime.utc(2026, 2, 24)), isTrue);
      expect(invitation.isExpiredAt(DateTime.utc(2026, 2, 22)), isFalse);
      // It is still revocable: the stored status is what the endpoint checks.
      expect(invitation.isRevocable, isTrue);
    });

    test('only a pending invitation is revocable', () {
      for (final status in ['accepted', 'revoked', 'expired']) {
        expect(
          AdminInvitation.fromJson(_invitation(status: status)).isRevocable,
          isFalse,
          reason: status,
        );
      }
    });

    test('a row missing its email fails rather than rendering blank', () {
      final row = _invitation()..remove('email');
      expect(
        () => AdminInvitation.fromJson(row),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('adminInvitationTokenFromInput', () {
    test('extracts the token from the emailed acceptance link', () {
      expect(
        adminInvitationTokenFromInput(
          ' https://app.example.test/admin-invitation-accept.html?token=abc-123_XY ',
        ),
        'abc-123_XY',
      );
    });

    test('extracts a token that a mail client moved into the fragment', () {
      expect(
        adminInvitationTokenFromInput(
          'https://app.example.test/accept#/page?token=abc123',
        ),
        'abc123',
      );
    });

    test('accepts a bare base64url token', () {
      expect(
        adminInvitationTokenFromInput('  Ab3-_xYzAb3-_xYz  '),
        'Ab3-_xYz Ab3-_xYz'.replaceAll(' ', ''),
      );
    });

    test('rejects empty, truncated and non-token input', () {
      expect(adminInvitationTokenFromInput(''), isNull);
      expect(adminInvitationTokenFromInput('   '), isNull);
      expect(adminInvitationTokenFromInput('short'), isNull);
      expect(adminInvitationTokenFromInput('has spaces in it here'), isNull);
      expect(
        adminInvitationTokenFromInput('https://app.example.test/accept?x=1'),
        isNull,
      );
    });
  });
}

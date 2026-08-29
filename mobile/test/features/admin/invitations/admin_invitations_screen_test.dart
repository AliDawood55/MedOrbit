import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/invitations/data/admin_invitations_api.dart';
import 'package:mobile/features/admin/invitations/models/admin_invitation.dart';
import 'package:mobile/features/admin/invitations/providers/admin_invitations_provider.dart';
import 'package:mobile/features/admin/invitations/screens/admin_invitations_screen.dart';

import '../admin_test_support.dart';

const String _link =
    'https://app.example.test/admin-invitation-accept.html?token=abc123';

AdminInvitation _invitation({
  String id = 'inv-1',
  String status = 'pending',
  String email = 'invited@example.test',
}) => AdminInvitation.fromJson({
  'id': id,
  'email': email,
  'status': status,
  'expires_at': '2099-03-01T09:00:00Z',
  'created_at': '2026-02-22T09:00:00Z',
});

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'super_admin',
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 2200),
}) => pumpAdminScreen(
  tester,
  screen: const AdminInvitationsScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminInvitationsApiProvider.overrideWithValue(api)],
);

void main() {
  testWidgets('an ordinary admin is refused and nothing is fetched', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'admin');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(find.text(en.adminSuperAdminOnlyTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-invitation-email')), findsNothing);
    expect(api.listCalls, 0);
  });

  testWidgets('a patient gets the general restricted state', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'patient');

    expect(find.text(en.adminRestrictedTitle), findsOneWidget);
    expect(api.listCalls, 0);
  });

  testWidgets('a super admin sees the form and the registry', (tester) async {
    await _pump(tester, api: _FakeApi()..invitations = [_invitation()]);

    expect(find.byKey(const ValueKey('admin-invitation-email')), findsOneWidget);
    expect(find.text('invited@example.test'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-invitation-revoke-inv-1')),
      findsOneWidget,
    );
  });

  testWidgets('an empty registry shows the empty state', (tester) async {
    await _pump(tester, api: _FakeApi());

    expect(
      find.byKey(const ValueKey('admin-invitations-empty')),
      findsOneWidget,
    );
  });

  testWidgets('a load failure shows safe copy and Retry reloads', (
    tester,
  ) async {
    final api = _FakeApi()
      ..listError = const ApiException(
        message: 'raw backend detail',
        code: 'FORBIDDEN',
      );
    await _pump(tester, api: api);

    expect(find.text(en.adminError('FORBIDDEN')), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);

    api.listError = null;
    api.invitations = [_invitation()];
    await tapByKey(tester, const ValueKey('admin-invitations-retry'));
    await tester.pump();
    await tester.pump();

    expect(api.listCalls, 2);
    expect(find.text('invited@example.test'), findsOneWidget);
  });

  testWidgets('an invalid email is rejected before any request is sent', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-email')),
      'not-an-email',
    );
    await tapByKey(tester, const ValueKey('admin-invitation-submit'));
    await tester.pumpAndSettle();

    expect(find.text(en.invalidEmail), findsOneWidget);
    expect(api.createCalls, 0);
  });

  testWidgets('creating shows the one-time link and can copy it', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final api = _FakeApi();
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-email')),
      'invited@example.test',
    );
    await tapByKey(tester, const ValueKey('admin-invitation-submit'));
    await tester.pumpAndSettle();

    expect(api.createCalls, 1);
    expect(api.lastEmail, 'invited@example.test');
    expect(find.text(_link), findsOneWidget);
    expect(find.text(en.adminInvitationCreatedManual), findsWidgets);

    await tapByKey(tester, const ValueKey('admin-invitation-copy'));
    await tester.pumpAndSettle();
    expect(copied, [_link]);

    await tapByKey(tester, const ValueKey('admin-invitation-hide-link'));
    await tester.pumpAndSettle();
    expect(find.text(_link), findsNothing);
  });

  testWidgets('a duplicate invitation shows mapped copy, not the raw message', (
    tester,
  ) async {
    final api = _FakeApi()
      ..createError = const ApiException(
        message: 'An active invitation already exists for invited@example.test',
        code: 'INVITATION_EXISTS',
      );
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-email')),
      'invited@example.test',
    );
    await tapByKey(tester, const ValueKey('admin-invitation-submit'));
    await tester.pumpAndSettle();

    expect(find.text(en.adminError('INVITATION_EXISTS')), findsOneWidget);
    expect(
      find.text('An active invitation already exists for invited@example.test'),
      findsNothing,
    );
  });

  testWidgets('revoking is confirmed before the request is sent', (
    tester,
  ) async {
    final api = _FakeApi()..invitations = [_invitation()];
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-invitation-revoke-inv-1'));
    await tester.pumpAndSettle();
    expect(
      find.text(en.adminInvitationRevokeTitle('invited@example.test')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, en.cancel));
    await tester.pumpAndSettle();
    expect(api.revokeCalls, 0);

    await tapByKey(tester, const ValueKey('admin-invitation-revoke-inv-1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-invitation-revoke-confirm')),
    );
    await tester.pumpAndSettle();

    expect(api.revokeCalls, 1);
    expect(find.text(en.adminInvitationRevokedSuccess), findsOneWidget);
    expect(find.text(en.adminInvitationStatusRevoked), findsOneWidget);
  });

  testWidgets('a second revoke tap while one is in flight is dropped', (
    tester,
  ) async {
    final api = _FakeApi()
      ..invitations = [_invitation()]
      ..revokeGate = Completer<AdminInvitation>();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-invitation-revoke-inv-1'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-invitation-revoke-confirm')),
    );
    await tester.pump();

    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('admin-invitation-revoke-inv-1')),
          )
          .onPressed,
      isNull,
    );
    expect(api.revokeCalls, 1);
  });

  testWidgets('an expired-by-time pending row is labelled expired', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()
        ..invitations = [
          AdminInvitation.fromJson({
            'id': 'inv-2',
            'email': 'stale@example.test',
            'status': 'pending',
            'expires_at': '2020-01-01T00:00:00Z',
            'created_at': '2019-12-25T00:00:00Z',
          }),
        ],
    );

    expect(find.text(en.adminInvitationStatusExpired), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..invitations = [_invitation()],
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 3000),
    );

    expect(find.text(ar.adminInvitationsTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

class _FakeApi extends AdminInvitationsApi {
  _FakeApi() : super(Dio());

  List<AdminInvitation> invitations = const [];
  Object? listError;
  Object? createError;
  Completer<AdminInvitation>? revokeGate;

  int listCalls = 0;
  int createCalls = 0;
  int revokeCalls = 0;
  String? lastEmail;

  @override
  Future<List<AdminInvitation>> list() {
    listCalls++;
    if (listError != null) return Future.error(listError!);
    return Future.value(invitations);
  }

  @override
  Future<AdminInvitationCreation> create(String email) {
    createCalls++;
    lastEmail = email.trim().toLowerCase();
    if (createError != null) return Future.error(createError!);
    invitations = [...invitations, _invitation(id: 'inv-new', email: lastEmail!)];
    return Future.value(
      AdminInvitationCreation(
        invitation: _invitation(id: 'inv-new', email: lastEmail!),
        delivered: false,
        acceptanceUrl: _link,
      ),
    );
  }

  @override
  Future<AdminInvitation> revoke(String invitationId) {
    revokeCalls++;
    if (revokeGate != null) return revokeGate!.future;
    return Future.value(_invitation(id: invitationId, status: 'revoked'));
  }
}

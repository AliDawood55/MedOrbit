import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/invitations/data/admin_invitations_api.dart';
import 'package:mobile/features/admin/invitations/models/admin_invitation.dart';
import 'package:mobile/features/admin/invitations/providers/admin_invitations_provider.dart';
import 'package:mobile/features/admin/invitations/screens/admin_invitation_accept_screen.dart';

import '../admin_test_support.dart';

const String _link =
    'https://app.example.test/admin-invitation-accept.html?token=abc-123_XYZ';

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'patient',
  String? initialToken,
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 1400),
}) => pumpAdminScreen(
  tester,
  screen: AdminInvitationAcceptScreen(initialToken: initialToken),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminInvitationsApiProvider.overrideWithValue(api)],
);

void main() {
  testWidgets('a patient — the normal invitee — gets the acceptance form', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi());

    expect(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      findsOneWidget,
    );
    expect(find.text(en.adminInvitationAcceptTokenHelper), findsOneWidget);
  });

  testWidgets('a doctor may also accept an invitation', (tester) async {
    await _pump(tester, api: _FakeApi(), role: 'doctor');

    expect(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      findsOneWidget,
    );
  });

  testWidgets('an account that is already an administrator has nothing to do', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'admin');

    expect(
      find.byKey(const ValueKey('admin-invitation-already-admin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      findsNothing,
    );
    expect(api.acceptCalls, 0);
  });

  testWidgets('an empty field is rejected before any request', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    expect(find.text(en.adminInvitationAcceptTokenRequired), findsOneWidget);
    expect(api.acceptCalls, 0);
  });

  testWidgets('unparseable input never reaches the network', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      'this is not a token',
    );
    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    expect(api.acceptCalls, 0);
    expect(find.text(en.adminError('INVALID_INVITATION')), findsOneWidget);
  });

  testWidgets('a pasted acceptance link sends only the token', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      _link,
    );
    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    expect(api.acceptCalls, 1);
    expect(api.lastToken, 'abc-123_XYZ');
    expect(find.text(en.adminInvitationAcceptSuccessTitle), findsOneWidget);
    expect(find.text(en.adminInvitationAcceptSuccessBody), findsOneWidget);
  });

  testWidgets('a bare token supplied on the route is pre-filled and sent', (
    tester,
  ) async {
    // A real token is `randomBytes(32).toString('base64url')` — 43 chars.
    const bareToken = 'Ab3-_xYz0123456789Ab3-_xYz0123456789Ab3-_xY';
    final api = _FakeApi();
    await _pump(tester, api: api, initialToken: bareToken);

    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    expect(api.lastToken, bareToken);
  });

  testWidgets('a truncated paste is refused before any request', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api, initialToken: 'abc-123');

    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    expect(api.acceptCalls, 0);
    expect(find.text(en.adminError('INVALID_INVITATION')), findsOneWidget);
  });

  testWidgets('an account mismatch shows mapped copy, not the raw message', (
    tester,
  ) async {
    final api = _FakeApi()
      ..acceptError = const ApiException(
        message: 'Invitation cannot be accepted by invited@example.test',
        code: 'INVITATION_ACCOUNT_MISMATCH',
      );
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      _link,
    );
    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    expect(
      find.text(en.adminError('INVITATION_ACCOUNT_MISMATCH')),
      findsOneWidget,
    );
    expect(find.textContaining('invited@example.test'), findsNothing);
    expect(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      findsOneWidget,
    );
  });

  testWidgets('an expired invitation is reported as expired', (tester) async {
    final api = _FakeApi()
      ..acceptError = const ApiException(
        message: 'Invitation has expired',
        code: 'INVITATION_EXPIRED',
      );
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      _link,
    );
    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    expect(find.text(en.adminError('INVITATION_EXPIRED')), findsOneWidget);
  });

  testWidgets('a second submit while one is in flight is dropped', (
    tester,
  ) async {
    final api = _FakeApi()..gate = Completer<void>();
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      _link,
    );
    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pump();

    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pump();

    expect(api.acceptCalls, 1);
  });

  testWidgets('after accepting, signing out returns to login', (tester) async {
    await _pump(tester, api: _FakeApi());

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      _link,
    );
    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pumpAndSettle();

    await tapByKey(tester, const ValueKey('admin-invitation-accept-sign-out'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login')), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi(),
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 1800),
    );

    expect(find.text(ar.adminInvitationAcceptTitle), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during an in-flight accept does not throw', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = _FakeApi()..gate = gate;
    await _pump(tester, api: api);

    await tester.enterText(
      find.byKey(const ValueKey('admin-invitation-accept-token')),
      _link,
    );
    await tapByKey(tester, const ValueKey('admin-invitation-accept-submit'));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _FakeApi extends AdminInvitationsApi {
  _FakeApi() : super(Dio());

  Object? acceptError;
  Completer<void>? gate;

  int acceptCalls = 0;
  String? lastToken;

  @override
  Future<List<AdminInvitation>> list() async => const [];

  @override
  Future<void> accept(String token) {
    acceptCalls++;
    lastToken = token;
    if (gate != null) return gate!.future;
    if (acceptError != null) return Future.error(acceptError!);
    return Future.value();
  }
}

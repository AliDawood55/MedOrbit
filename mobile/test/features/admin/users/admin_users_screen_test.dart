import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/users/data/admin_users_api.dart';
import 'package:mobile/features/admin/users/models/admin_user.dart';
import 'package:mobile/features/admin/users/providers/admin_users_provider.dart';
import 'package:mobile/features/admin/users/screens/admin_users_screen.dart';

import '../admin_test_support.dart';

AdminUser _user(
  String id, {
  bool active = true,
  String role = 'patient',
  String first = 'Lina',
}) => AdminUser.fromJson({
  'id': id,
  'email': '$id@example.test',
  'role': role,
  'is_active': active,
  'email_verified': true,
  'first_name_en': first,
  'last_name_en': 'Haddad',
});

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'admin',
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 1600),
}) => pumpAdminScreen(
  tester,
  screen: const AdminUsersScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminUsersApiProvider.overrideWithValue(api)],
);

void main() {
  testWidgets('a patient never sees the screen or triggers a request', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'patient');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(find.text(en.adminRestrictedTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-users-search')), findsNothing);
    expect(api.listCalls, 0);
  });

  testWidgets('a doctor is refused just like a patient', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'doctor');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(api.listCalls, 0);
  });

  testWidgets('shows a loading state before the first response', (tester) async {
    final api = _FakeApi()..gate = Completer<List<AdminUser>>();
    await _pump(tester, api: api);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-users-empty')), findsNothing);
  });

  testWidgets('a first-load failure shows safe copy and Retry reloads', (
    tester,
  ) async {
    final api = _FakeApi()
      ..listError = const ApiException(
        message: 'raw backend detail',
        code: 'FORBIDDEN',
      );
    await _pump(tester, api: api);

    expect(find.text(en.adminLoadErrorTitle), findsOneWidget);
    expect(find.text(en.adminError('FORBIDDEN')), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);

    api.listError = null;
    api.users = [_user('a')];
    await tapByKey(tester, const ValueKey('admin-users-retry'));
    await tester.pump();
    await tester.pump();

    expect(api.listCalls, 2);
    expect(find.text('Lina Haddad'), findsOneWidget);
  });

  testWidgets('an empty result shows the empty state', (tester) async {
    await _pump(tester, api: _FakeApi());

    expect(find.byKey(const ValueKey('admin-users-empty')), findsOneWidget);
    expect(find.text(en.adminUsersEmptyTitle), findsOneWidget);
  });

  testWidgets('renders role, status and verification badges per account', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..users = [_user('a', active: false)],
    );

    expect(find.text(en.rolePatient), findsOneWidget);
    expect(find.text(en.adminUsersStatusInactive), findsOneWidget);
    expect(find.text(en.adminUsersVerified), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-user-reactivate-a')),
      findsOneWidget,
    );
  });

  testWidgets('the actor\'s own account is protected, not actionable', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..users = [_user(adminActorId, role: 'admin')],
    );

    expect(find.text(en.adminUsersCurrentAccount), findsOneWidget);
    expect(
      find.byKey(ValueKey('admin-user-deactivate-$adminActorId')),
      findsNothing,
    );
  });

  testWidgets('an admin cannot act on another admin account', (tester) async {
    await _pump(tester, api: _FakeApi()..users = [_user('a', role: 'admin')]);

    expect(find.text(en.adminUsersProtectedAccount), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-user-deactivate-a')), findsNothing);
  });

  testWidgets('a super admin can act on an admin account', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()..users = [_user('a', role: 'admin')],
      role: 'super_admin',
    );

    expect(find.text(en.adminUsersProtectedAccount), findsNothing);
    expect(
      find.byKey(const ValueKey('admin-user-deactivate-a')),
      findsOneWidget,
    );
  });

  testWidgets('a super_admin account is protected even from a super admin', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..users = [_user('a', role: 'super_admin')],
      role: 'super_admin',
    );

    expect(find.text(en.adminUsersProtectedAccount), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-user-deactivate-a')), findsNothing);
  });

  testWidgets('deactivation is confirmed before the request is sent', (
    tester,
  ) async {
    final api = _FakeApi()..users = [_user('a')];
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-user-deactivate-a'));
    await tester.pumpAndSettle();
    expect(
      find.text(en.adminUsersConfirmDeactivateTitle('Lina Haddad')),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, en.cancel));
    await tester.pumpAndSettle();
    expect(api.mutationCalls, 0);

    await tapByKey(tester, const ValueKey('admin-user-deactivate-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-user-action-confirm')));
    await tester.pumpAndSettle();

    expect(api.mutationCalls, 1);
    expect(api.deactivated, ['a']);
    expect(find.text(en.adminUsersDeactivateSuccess), findsOneWidget);
    expect(find.text(en.adminUsersStatusInactive), findsOneWidget);
  });

  testWidgets('a failed mutation shows mapped copy, never the raw message', (
    tester,
  ) async {
    final api = _FakeApi()
      ..users = [_user('a')]
      ..mutationError = const ApiException(
        message: 'Administrators cannot modify their own security state',
        code: 'FORBIDDEN',
      );
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-user-deactivate-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-user-action-confirm')));
    await tester.pumpAndSettle();

    expect(find.text(en.adminError('FORBIDDEN')), findsOneWidget);
    expect(
      find.textContaining('cannot modify their own security state'),
      findsNothing,
    );
  });

  testWidgets('the action button is disabled while a mutation is in flight', (
    tester,
  ) async {
    final api = _FakeApi()
      ..users = [_user('a')]
      ..mutationGate = Completer<AdminUserStateUpdate>();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-user-deactivate-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-user-action-confirm')));
    await tester.pump();

    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('admin-user-deactivate-a')),
    );
    expect(button.onPressed, isNull);
    expect(api.mutationCalls, 1);
  });

  testWidgets('typing filters through one debounced request', (tester) async {
    final api = _FakeApi()..users = [_user('a')];
    await _pump(tester, api: api);
    expect(api.listCalls, 1);

    await tester.enterText(
      find.byKey(const ValueKey('admin-users-search')),
      'lin',
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.listCalls, 1);

    await tester.pump(adminUsersSearchDebounce);
    await tester.pump();
    expect(api.listCalls, 2);
    expect(api.lastSearch, 'lin');
  });

  testWidgets('the filter sheet applies the role filter the backend accepts', (
    tester,
  ) async {
    final api = _FakeApi()..users = [_user('a')];
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-users-filters'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('admin-users-role-doctor')));
    await tester.pumpAndSettle();

    expect(api.lastRole, AdminUserRole.doctor);
    expect(api.listCalls, 2);
  });

  testWidgets('the role-change note explains why no role control is offered', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi()..users = [_user('a')]);

    expect(find.text(en.adminUsersRoleChangeNote), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL without overflow', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()..users = [_user('a', role: 'super_admin')],
      isArabic: true,
    );

    expect(find.text(ar.adminUsersTitle), findsWidgets);
    expect(find.text(ar.roleSuperAdmin), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(AdminUsersScreen))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('survives a 320 px viewport at 1.6x text scale', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()..users = [_user('a'), _user('b', active: false)],
      textScale: 1.6,
      size: const Size(320, 2400),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(AdminUsersScreen), findsOneWidget);
  });

  testWidgets('disposing during an in-flight mutation does not throw', (
    tester,
  ) async {
    final gate = Completer<AdminUserStateUpdate>();
    final api = _FakeApi()
      ..users = [_user('a')]
      ..mutationGate = gate;
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-user-deactivate-a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-user-action-confirm')));
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    gate.complete(
      AdminUserStateUpdate.fromJson({
        'id': 'a',
        'is_active': false,
        'email_verified': true,
      }),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _FakeApi extends AdminUsersApi {
  _FakeApi() : super(Dio());

  List<AdminUser> users = const [];
  Object? listError;
  Completer<List<AdminUser>>? gate;
  Object? mutationError;
  Completer<AdminUserStateUpdate>? mutationGate;

  int listCalls = 0;
  int mutationCalls = 0;
  String? lastSearch;
  AdminUserRole? lastRole;
  final deactivated = <String>[];

  @override
  Future<List<AdminUser>> list({
    String? search,
    AdminUserRole? role,
    bool? active,
  }) {
    listCalls++;
    lastSearch = search;
    lastRole = role;
    if (gate != null) return gate!.future;
    if (listError != null) return Future.error(listError!);
    return Future.value(users);
  }

  @override
  Future<AdminUserStateUpdate> deactivate(String userId) {
    mutationCalls++;
    deactivated.add(userId);
    return _respond(userId, active: false);
  }

  @override
  Future<AdminUserStateUpdate> reactivate(String userId) {
    mutationCalls++;
    return _respond(userId, active: true);
  }

  Future<AdminUserStateUpdate> _respond(String id, {required bool active}) {
    if (mutationGate != null) return mutationGate!.future;
    if (mutationError != null) return Future.error(mutationError!);
    return Future.value(
      AdminUserStateUpdate.fromJson({
        'id': id,
        'is_active': active,
        'email_verified': true,
      }),
    );
  }
}

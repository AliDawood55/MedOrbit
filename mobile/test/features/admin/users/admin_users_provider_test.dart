import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/users/data/admin_users_api.dart';
import 'package:mobile/features/admin/users/models/admin_user.dart';
import 'package:mobile/features/admin/users/providers/admin_users_provider.dart';

AdminUser _user(String id, {bool active = true, String role = 'patient'}) =>
    AdminUser.fromJson({
      'id': id,
      'email': '$id@example.test',
      'role': role,
      'is_active': active,
      'email_verified': true,
      'first_name_en': 'Name',
      'last_name_en': id,
    });

AdminUserStateUpdate _update(String id, {required bool active}) =>
    AdminUserStateUpdate.fromJson({
      'id': id,
      'is_active': active,
      'email_verified': true,
    });

void main() {
  test('loads on construction and records the result', () async {
    final api = _FakeApi()..users = [_user('a'), _user('b')];
    final controller = AdminUsersController(api);
    addTearDown(controller.dispose);

    await pumpEventQueue();
    expect(controller.state.users.length, 2);
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.hasLoadedOnce, isTrue);
    expect(api.listCalls, 1);
  });

  test('a first-load failure keeps hasLoadedOnce false and stores the code', () async {
    final api = _FakeApi()
      ..listError = const ApiException(
        message: 'raw backend detail',
        code: 'FORBIDDEN',
      );
    final controller = AdminUsersController(api);
    addTearDown(controller.dispose);

    await pumpEventQueue();
    expect(controller.state.errorCode, 'FORBIDDEN');
    expect(controller.state.hasLoadedOnce, isFalse);
    expect(controller.state.users, isEmpty);
  });

  test('search is debounced into a single request', () async {
    final api = _FakeApi();
    final controller = AdminUsersController(
      api,
      searchDebounce: const Duration(milliseconds: 20),
    );
    addTearDown(controller.dispose);
    await pumpEventQueue();
    expect(api.listCalls, 1);

    controller.setSearch('l');
    controller.setSearch('li');
    controller.setSearch('lin');
    // The field stays responsive immediately even though no request is out.
    expect(controller.state.search, 'lin');
    expect(api.listCalls, 1);

    await Future<void>.delayed(const Duration(milliseconds: 40));
    await pumpEventQueue();
    expect(api.listCalls, 2);
    expect(api.lastSearch, 'lin');
  });

  test('changing a filter loads immediately and cancels a pending search', () async {
    final api = _FakeApi();
    final controller = AdminUsersController(
      api,
      searchDebounce: const Duration(milliseconds: 50),
    );
    addTearDown(controller.dispose);
    await pumpEventQueue();

    controller.setSearch('x');
    controller.setRole(AdminUserRole.doctor);
    await pumpEventQueue();

    expect(api.listCalls, 2);
    expect(api.lastRole, AdminUserRole.doctor);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pumpEventQueue();
    // The debounced search timer was cancelled by the filter load.
    expect(api.listCalls, 2);
  });

  test('a slow earlier response never overwrites a newer one', () async {
    final api = _FakeApi();
    final slow = Completer<List<AdminUser>>();
    api.gate = slow;

    final controller = AdminUsersController(api);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    api.gate = null;
    api.users = [_user('fresh')];
    controller.setActive(true);
    await pumpEventQueue();
    expect(controller.state.users.single.id, 'fresh');

    slow.complete([_user('stale')]);
    await pumpEventQueue();
    expect(controller.state.users.single.id, 'fresh');
  });

  test('clearFilters resets every filter and reloads', () async {
    final api = _FakeApi();
    final controller = AdminUsersController(api);
    addTearDown(controller.dispose);
    await pumpEventQueue();

    controller.setRole(AdminUserRole.admin);
    controller.setActive(false);
    await pumpEventQueue();
    expect(controller.state.hasActiveFilters, isTrue);

    controller.clearFilters();
    await pumpEventQueue();
    expect(controller.state.role, isNull);
    expect(controller.state.active, isNull);
    expect(controller.state.search, '');
    expect(controller.state.hasActiveFilters, isFalse);
  });

  group('activation', () {
    test('merges the partial response without blanking the profile name', () async {
      final api = _FakeApi()..users = [_user('a')];
      final controller = AdminUsersController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final ok = await controller.setUserActive(
        controller.state.users.single,
        activate: false,
      );

      expect(ok, isTrue);
      expect(api.deactivated, ['a']);
      expect(controller.state.users.single.isActive, isFalse);
      // SAFE_USER_COLUMNS carries no profile names; the cached row keeps them.
      expect(controller.state.users.single.displayName, 'Name a');
      expect(controller.state.pendingUserIds, isEmpty);
    });

    test('a second tap while the first call is in flight is dropped', () async {
      final api = _FakeApi()..users = [_user('a')];
      final gate = Completer<AdminUserStateUpdate>();
      api.mutationGate = gate;

      final controller = AdminUsersController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final user = controller.state.users.single;
      final first = controller.setUserActive(user, activate: false);
      await pumpEventQueue();
      expect(controller.state.pendingUserIds, {'a'});

      final second = await controller.setUserActive(user, activate: false);
      expect(second, isFalse);
      expect(api.mutationCalls, 1);

      gate.complete(_update('a', active: false));
      expect(await first, isTrue);
      expect(api.mutationCalls, 1);
    });

    test('a failure records the code, clears pending, and leaves the row alone', () async {
      final api = _FakeApi()
        ..users = [_user('a')]
        ..mutationError = const ApiException(
          message: 'Only a super admin can modify an admin account',
          code: 'FORBIDDEN',
        );
      final controller = AdminUsersController(api);
      addTearDown(controller.dispose);
      await pumpEventQueue();

      final ok = await controller.setUserActive(
        controller.state.users.single,
        activate: false,
      );

      expect(ok, isFalse);
      expect(controller.state.actionErrorCode, 'FORBIDDEN');
      expect(controller.state.users.single.isActive, isTrue);
      expect(controller.state.pendingUserIds, isEmpty);

      controller.clearActionError();
      expect(controller.state.actionErrorCode, isNull);
    });

    test('completing after disposal does not throw', () async {
      final api = _FakeApi()..users = [_user('a')];
      final gate = Completer<AdminUserStateUpdate>();
      api.mutationGate = gate;

      final controller = AdminUsersController(api);
      await pumpEventQueue();
      final pending = controller.setUserActive(
        controller.state.users.single,
        activate: false,
      );
      controller.dispose();

      gate.complete(_update('a', active: false));
      await expectLater(pending, completion(isTrue));
    });

    test('a load completing after disposal does not throw', () async {
      final api = _FakeApi();
      final gate = Completer<List<AdminUser>>();
      api.gate = gate;

      final controller = AdminUsersController(api);
      controller.dispose();
      gate.complete([_user('a')]);
      await pumpEventQueue();
      // Reaching here without a StateNotifier "used after dispose" error is
      // the assertion.
      expect(true, isTrue);
    });
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
  bool? lastActive;
  final deactivated = <String>[];
  final reactivated = <String>[];

  @override
  Future<List<AdminUser>> list({
    String? search,
    AdminUserRole? role,
    bool? active,
  }) {
    listCalls++;
    lastSearch = search;
    lastRole = role;
    lastActive = active;
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
    reactivated.add(userId);
    return _respond(userId, active: true);
  }

  Future<AdminUserStateUpdate> _respond(String id, {required bool active}) {
    if (mutationGate != null) return mutationGate!.future;
    if (mutationError != null) return Future.error(mutationError!);
    return Future.value(_update(id, active: active));
  }
}

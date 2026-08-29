import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/common/providers/admin_access_provider.dart';
import 'package:mobile/features/admin/users/data/admin_users_api.dart';
import 'package:mobile/features/admin/users/models/admin_user.dart';

import '../admin_test_support.dart';

Map<String, dynamic> _row({
  String id = 'user-1',
  String role = 'patient',
  bool isActive = true,
  bool emailVerified = true,
}) => {
  'id': id,
  'email': 'p@example.test',
  'role': role,
  'is_active': isActive,
  'email_verified': emailVerified,
  'authorization_version': 3,
  'first_name_en': 'Lina',
  'last_name_en': 'Haddad',
  'phone': '0599000000',
  'city': 'Nablus',
};

void main() {
  test('list sends only the three filters the backend implements', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_row()],
      })
      ..enqueue({'success': true, 'data': <dynamic>[]});

    final api = AdminUsersApi(dio.dio);
    await api.list();
    await api.list(search: '  lina ', role: AdminUserRole.doctor, active: false);

    expect(dio.paths, ['/admin/users', '/admin/users']);
    expect(dio.methods, ['GET', 'GET']);
    expect(dio.queries.first, isEmpty);
    expect(dio.queries[1], {
      'search': 'lina',
      'role': 'doctor',
      // The backend compares `active === 'true'`, so a JSON boolean would
      // silently filter to inactive accounts.
      'active': 'false',
    });
  });

  test('a blank search is omitted rather than sent as an empty filter', () async {
    final dio = RecordingDio()..enqueue({'success': true, 'data': <dynamic>[]});
    await AdminUsersApi(dio.dio).list(search: '   ');
    expect(dio.queries.single, isEmpty);
  });

  test('super_admin maps to the wire value the select submits', () {
    expect(adminUserRoleWireValue(AdminUserRole.superAdmin), 'super_admin');
    expect(adminUserRoleWireValue(AdminUserRole.patient), 'patient');
    expect(adminUserRoleWireValue(null), isNull);
    expect(adminUserRoleWireValue(AdminUserRole.unknown), isNull);
  });

  test('parses a row, including the English-only name projection', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_row(role: 'super_admin', isActive: false)],
      });

    final users = await AdminUsersApi(dio.dio).list();
    expect(users.single.role, AdminUserRole.superAdmin);
    expect(users.single.roleValue, 'super_admin');
    expect(users.single.isActive, isFalse);
    expect(users.single.displayName, 'Lina Haddad');
    expect(users.single.city, 'Nablus');
  });

  test('an unrecognized role keeps its raw value instead of becoming patient', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_row(role: 'auditor')],
      });

    final user = (await AdminUsersApi(dio.dio).list()).single;
    expect(user.role, AdminUserRole.unknown);
    expect(user.roleValue, 'auditor');
  });

  test('a row without an email falls back to the address for display', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [
          {
            'id': 'u2',
            'email': 'anon@example.test',
            'role': 'patient',
            'is_active': true,
            'email_verified': false,
          },
        ],
      });

    final user = (await AdminUsersApi(dio.dio).list()).single;
    expect(user.displayName, 'anon@example.test');
    expect(user.emailVerified, isFalse);
  });

  test('a malformed row fails the read', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [
          {'email': 'x@y.test', 'role': 'patient'},
        ],
      });

    await expectLater(AdminUsersApi(dio.dio).list(), throwsA(anything));
  });

  test('activation uses PUT with an empty body on the exact paths', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': {
          'id': 'user-1',
          'email': 'p@example.test',
          'role': 'patient',
          'is_active': false,
          'email_verified': true,
        },
      })
      ..enqueue({
        'success': true,
        'data': {
          'id': 'user-1',
          'email': 'p@example.test',
          'role': 'patient',
          'is_active': true,
          'email_verified': true,
        },
      });

    final api = AdminUsersApi(dio.dio);
    final deactivated = await api.deactivate('user-1');
    final reactivated = await api.reactivate('user-1');

    expect(dio.paths, [
      '/admin/users/user-1/deactivate',
      '/admin/users/user-1/reactivate',
    ]);
    expect(dio.methods, ['PUT', 'PUT']);
    expect(dio.bodies, [<String, dynamic>{}, <String, dynamic>{}]);
    expect(deactivated.isActive, isFalse);
    expect(reactivated.isActive, isTrue);
  });

  test('a forbidden mutation surfaces the server code only', () async {
    final dio = RecordingDio()..enqueueFailure(403, 'FORBIDDEN');

    try {
      await AdminUsersApi(dio.dio).deactivate('user-1');
      fail('expected a failure');
    } catch (error) {
      expect(ApiException.from(error).code, 'FORBIDDEN');
    }
  });

  group('adminUserAction mirrors the backend mutationBlocked rules', () {
    AdminUser user({
      String id = 'other',
      String role = 'patient',
      bool active = true,
    }) => AdminUser.fromJson(_row(id: id, role: role, isActive: active));

    test('the actor may never change their own state', () {
      expect(
        adminUserAction(
          user: user(id: 'me'),
          actorId: 'me',
          access: AdminAccess.superAdmin,
        ),
        AdminUserAction.blockedSelfAccount,
      );
    });

    test('a super admin target is protected from everyone', () {
      for (final access in [AdminAccess.admin, AdminAccess.superAdmin]) {
        expect(
          adminUserAction(
            user: user(role: 'super_admin'),
            actorId: 'me',
            access: access,
          ),
          AdminUserAction.blockedProtectedAccount,
          reason: '$access',
        );
      }
    });

    test('an admin target is editable only by a super admin', () {
      expect(
        adminUserAction(
          user: user(role: 'admin'),
          actorId: 'me',
          access: AdminAccess.admin,
        ),
        AdminUserAction.blockedProtectedAccount,
      );
      expect(
        adminUserAction(
          user: user(role: 'admin'),
          actorId: 'me',
          access: AdminAccess.superAdmin,
        ),
        AdminUserAction.deactivate,
      );
    });

    test('an ordinary account offers the opposite of its current state', () {
      expect(
        adminUserAction(
          user: user(),
          actorId: 'me',
          access: AdminAccess.admin,
        ),
        AdminUserAction.deactivate,
      );
      expect(
        adminUserAction(
          user: user(active: false),
          actorId: 'me',
          access: AdminAccess.admin,
        ),
        AdminUserAction.reactivate,
      );
    });
  });
}

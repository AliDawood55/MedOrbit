import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/admin/common/providers/admin_access_provider.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';

void main() {
  group('adminAccessFor', () {
    test('maps the two administrator roles apart, never together', () {
      expect(
        adminAccessFor(status: AuthStatus.authenticated, role: 'admin'),
        AdminAccess.admin,
      );
      expect(
        adminAccessFor(status: AuthStatus.authenticated, role: 'super_admin'),
        AdminAccess.superAdmin,
      );
      expect(AdminAccess.admin.canUseAdminTools, isTrue);
      expect(AdminAccess.admin.canUseSuperAdminTools, isFalse);
      expect(AdminAccess.superAdmin.canUseAdminTools, isTrue);
      expect(AdminAccess.superAdmin.canUseSuperAdminTools, isTrue);
    });

    test('every non-administrator role resolves to none', () {
      for (final role in ['patient', 'doctor', '', 'administrator', 'root']) {
        expect(
          adminAccessFor(status: AuthStatus.authenticated, role: role),
          AdminAccess.none,
          reason: role,
        );
      }
      expect(
        adminAccessFor(status: AuthStatus.authenticated, role: null),
        AdminAccess.none,
      );
    });

    test('role matching is case and whitespace tolerant', () {
      expect(
        adminAccessFor(status: AuthStatus.authenticated, role: ' Admin '),
        AdminAccess.admin,
      );
      expect(
        adminAccessFor(status: AuthStatus.authenticated, role: 'SUPER_ADMIN'),
        AdminAccess.superAdmin,
      );
    });

    test('an unresolved session is unknown, not denied', () {
      // Denying here would tell a real administrator on a cold start that they
      // are not authorized; granting would leak a frame of admin data.
      expect(
        adminAccessFor(status: AuthStatus.unknown, role: 'super_admin'),
        AdminAccess.unknown,
      );
      expect(AdminAccess.unknown.canUseAdminTools, isFalse);
      expect(AdminAccess.unknown.isDeniedDefinitively, isFalse);
    });

    test('a cleared session denies even when a stale role is passed', () {
      expect(
        adminAccessFor(status: AuthStatus.unauthenticated, role: 'super_admin'),
        AdminAccess.none,
      );
      expect(AdminAccess.none.isDeniedDefinitively, isTrue);
    });
  });
}

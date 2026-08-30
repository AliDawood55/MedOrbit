import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/routes/app_router.dart';
import 'package:mobile/routes/route_paths.dart';

/// Route-level authorization for the administration area.
///
/// The rule is tested directly rather than through a pumped tree: it decides
/// whether an admin screen is ever built at all, and asserting it in isolation
/// keeps these expectations independent of every screen's dependencies.
void main() {
  const adminOnly = [
    RoutePaths.adminDashboard,
    RoutePaths.adminAnalytics,
    RoutePaths.adminUsers,
    RoutePaths.adminDoctorApplications,
    RoutePaths.adminContactMessages,
    RoutePaths.adminModeration,
    RoutePaths.adminAuditLogs,
  ];

  group('isAdministrationLocation', () {
    test('covers every listed admin route', () {
      for (final route in [...adminOnly, RoutePaths.adminInvitations]) {
        expect(isAdministrationLocation(route), isTrue, reason: route);
      }
    });

    test('covers parameterized detail locations', () {
      expect(
        isAdministrationLocation(
          RoutePaths.adminDoctorApplicationDetailPath('app-1'),
        ),
        isTrue,
      );
    });

    test('does not capture unrelated routes that merely start with admin', () {
      expect(isAdministrationLocation('/administration'), isFalse);
      expect(isAdministrationLocation(RoutePaths.home), isFalse);
      expect(isAdministrationLocation(RoutePaths.doctorApplication), isFalse);
    });
  });

  group('session gate', () {
    test('an unauthenticated visitor is sent to login from every admin route', () {
      for (final route in [
        ...adminOnly,
        RoutePaths.adminInvitations,
        RoutePaths.adminInvitationAccept,
        RoutePaths.adminDoctorApplicationDetailPath('app-1'),
      ]) {
        expect(
          sessionRedirect(AuthStatus.unauthenticated, route),
          RoutePaths.login,
          reason: route,
        );
      }
    });

    test('an admin destination survives the login round trip', () {
      final loginLocation = sessionRedirect(
        AuthStatus.unauthenticated,
        RoutePaths.adminUsers,
        fullLocation: RoutePaths.adminUsers,
      );
      expect(
        intendedDestinationFromLoginUri(Uri.parse(loginLocation!)),
        RoutePaths.adminUsers,
      );
    });
  });

  group('adminRedirect', () {
    test('an administrator reaches every admin route except invitations', () {
      for (final route in adminOnly) {
        expect(
          adminRedirect(AuthStatus.authenticated, 'admin', route),
          isNull,
          reason: route,
        );
      }
      expect(
        adminRedirect(
          AuthStatus.authenticated,
          'admin',
          RoutePaths.adminDoctorApplicationDetailPath('app-1'),
        ),
        isNull,
      );
    });

    test('invitations are super-admin only, not "admin or super_admin"', () {
      expect(
        adminRedirect(
          AuthStatus.authenticated,
          'admin',
          RoutePaths.adminInvitations,
        ),
        RoutePaths.home,
      );
      expect(
        adminRedirect(
          AuthStatus.authenticated,
          'super_admin',
          RoutePaths.adminInvitations,
        ),
        isNull,
      );
    });

    test('a super admin reaches every ordinary admin route too', () {
      for (final route in adminOnly) {
        expect(
          adminRedirect(AuthStatus.authenticated, 'super_admin', route),
          isNull,
          reason: route,
        );
      }
    });

    test('patients and doctors are turned away from every admin route', () {
      for (final role in ['patient', 'doctor', null]) {
        for (final route in [...adminOnly, RoutePaths.adminInvitations]) {
          expect(
            adminRedirect(AuthStatus.authenticated, role, route),
            RoutePaths.home,
            reason: '$role → $route',
          );
        }
      }
    });

    test('the acceptance screen is never administrator-gated', () {
      // The account accepting an invitation is still a patient at that moment.
      for (final role in ['patient', 'doctor', 'admin', 'super_admin']) {
        expect(
          adminRedirect(
            AuthStatus.authenticated,
            role,
            RoutePaths.adminInvitationAccept,
          ),
          isNull,
          reason: role,
        );
      }
    });

    test('never fires on non-admin locations', () {
      for (final route in [
        RoutePaths.home,
        RoutePaths.records,
        RoutePaths.login,
        RoutePaths.doctorApplication,
      ]) {
        expect(
          adminRedirect(AuthStatus.authenticated, 'patient', route),
          isNull,
          reason: route,
        );
      }
    });

    test('defers to the session gate while the status is not authenticated', () {
      // `unknown` is the splash bootstrap window; `unauthenticated` already has
      // a login redirect from sessionRedirect.
      expect(
        adminRedirect(AuthStatus.unknown, null, RoutePaths.adminUsers),
        isNull,
      );
      expect(
        adminRedirect(AuthStatus.unauthenticated, null, RoutePaths.adminUsers),
        isNull,
      );
    });
  });

  group('route sets', () {
    test('superAdminRoutes is exactly the invitation registry', () {
      expect(superAdminRoutes, {RoutePaths.adminInvitations});
    });

    test('every admin route is also session protected', () {
      for (final route in adminRoutes) {
        expect(isProtectedLocation(route), isTrue, reason: route);
      }
      expect(isProtectedLocation(RoutePaths.adminInvitationAccept), isTrue);
    });
  });
}

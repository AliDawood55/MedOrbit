import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/routes/app_router.dart';
import 'package:mobile/routes/route_paths.dart';

/// Covers the redirect rule directly rather than through a pumped widget tree.
/// The rule is the whole behaviour, and testing it in isolation keeps these
/// assertions independent of every screen's plugin dependencies.
void main() {
  const protected = [
    RoutePaths.home,
    RoutePaths.records,
    RoutePaths.prescriptions,
    RoutePaths.appointments,
    RoutePaths.appointmentBooking,
    RoutePaths.feedback,
    RoutePaths.notifications,
    RoutePaths.profile,
    RoutePaths.symptomChecker,
    RoutePaths.drugChecker,
    RoutePaths.reportSummarizer,
    RoutePaths.myReports,
    RoutePaths.myDoctors,
    RoutePaths.savedPlaces,
    RoutePaths.contact,
    RoutePaths.myDoctor,
  ];

  const public = [
    RoutePaths.splash,
    RoutePaths.login,
    RoutePaths.register,
    RoutePaths.forgotPassword,
    RoutePaths.verifyCode,
    RoutePaths.resetPassword,
    RoutePaths.clinics,
    RoutePaths.doctors,
    RoutePaths.chatbot,
    RoutePaths.conversations,
    RoutePaths.virtualDoctor,
    RoutePaths.mapFoundation,
  ];

  group('unauthenticated', () {
    test('every patient-data route redirects to login', () {
      for (final route in protected) {
        expect(
          sessionRedirect(AuthStatus.unauthenticated, route),
          RoutePaths.login,
          reason: '$route should not render without a session',
        );
      }
    });

    test('public routes stay reachable', () {
      for (final route in public) {
        expect(
          sessionRedirect(AuthStatus.unauthenticated, route),
          isNull,
          reason: '$route is public and must not be gated',
        );
      }
    });

    test('discovery detail routes stay public', () {
      expect(
        sessionRedirect(AuthStatus.unauthenticated, '/clinics/abc'),
        isNull,
      );
      expect(
        sessionRedirect(AuthStatus.unauthenticated, '/doctors/abc'),
        isNull,
      );
      expect(
        sessionRedirect(
          AuthStatus.unauthenticated,
          '/chatbot/conversations/abc',
        ),
        isNull,
      );
    });
  });

  group('authenticated', () {
    test('nothing is redirected', () {
      for (final route in [...protected, ...public]) {
        expect(
          sessionRedirect(AuthStatus.authenticated, route),
          isNull,
          reason: route,
        );
      }
    });
  });

  group('unknown status', () {
    test('never redirects, so the splash bootstrap is not interrupted', () {
      // `unknown` is the window where the splash screen is still reading
      // persisted tokens. Redirecting here would bounce an already-signed-in
      // patient to the login screen on every cold start.
      for (final route in [...protected, ...public]) {
        expect(
          sessionRedirect(AuthStatus.unknown, route),
          isNull,
          reason: route,
        );
      }
    });
  });

  group('session expiry', () {
    test(
      'a route that was allowed becomes a redirect once the session clears',
      () {
        // The transition a failed token refresh produces: the patient is sitting
        // on a records screen and the refresh fails underneath them.
        expect(
          sessionRedirect(AuthStatus.authenticated, RoutePaths.records),
          isNull,
        );
        expect(
          sessionRedirect(AuthStatus.unauthenticated, RoutePaths.records),
          RoutePaths.login,
        );
      },
    );

    test(
      'the login target is never itself protected, so redirects cannot loop',
      () {
        expect(protectedRoutes.contains(RoutePaths.login), isFalse);
        expect(
          sessionRedirect(AuthStatus.unauthenticated, RoutePaths.login),
          isNull,
        );
      },
    );
  });

  group('protected set', () {
    test(
      'covers exactly the patient-data routes: the five shell branches plus booking, notifications, profile, symptom checker, drug checker, report summarizer, my reports, my doctors, saved places, contact, and my doctor',
      () {
        expect(protectedRoutes, protected.toSet());
      },
    );

    test('excludes every public route', () {
      for (final route in public) {
        expect(protectedRoutes.contains(route), isFalse, reason: route);
      }
    });
  });
}

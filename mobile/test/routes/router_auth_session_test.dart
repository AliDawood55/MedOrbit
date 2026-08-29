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
    RoutePaths.doctorApplication,
    RoutePaths.billing,
    RoutePaths.subscription,
    RoutePaths.billingHistory,
    RoutePaths.billingSandbox,
    RoutePaths.chatbot,
    RoutePaths.conversations,
    RoutePaths.chatbotConversation,
    RoutePaths.virtualDoctor,
    RoutePaths.messages,
    RoutePaths.messagesNew,
    RoutePaths.messageThread,
    RoutePaths.doctorWorkspace,
    RoutePaths.doctorProfessionalProfile,
    RoutePaths.doctorSchedule,
    RoutePaths.doctorPatients,
    RoutePaths.doctorPatient,
    RoutePaths.doctorPosts,
    // Administration surfaces are session-protected too; the role gate on top
    // of that lives in `adminRedirect` and is covered by its own suite.
    RoutePaths.adminDashboard,
    RoutePaths.adminAnalytics,
    RoutePaths.adminUsers,
    RoutePaths.adminDoctorApplications,
    RoutePaths.adminContactMessages,
    RoutePaths.adminModeration,
    RoutePaths.adminAuditLogs,
    RoutePaths.adminInvitations,
    RoutePaths.adminInvitationAccept,
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

    test(
      'discovery detail routes stay public while conversation details are protected',
      () {
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
          RoutePaths.login,
        );
      },
    );

    test('dynamic sandbox checkout path is protected', () {
      expect(
        sessionRedirect(
          AuthStatus.unauthenticated,
          RoutePaths.billingSandboxPath('checkout-token'),
        ),
        RoutePaths.login,
      );
    });

    test('dynamic direct-message routes never expose private data', () {
      const thread = '/messages/123e4567-e89b-42d3-a456-426614174000';
      expect(
        sessionRedirect(
          AuthStatus.unauthenticated,
          thread,
          fullLocation: '$thread?from=notification',
        ),
        '/login?redirect=%2Fmessages%2F123e4567-e89b-42d3-a456-426614174000%3Ffrom%3Dnotification',
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

    test('preserves a protected intended destination and its query', () {
      const destination = '${RoutePaths.appointmentBooking}?doctorId=doctor-1';
      final loginLocation = sessionRedirect(
        AuthStatus.unauthenticated,
        RoutePaths.appointmentBooking,
        fullLocation: destination,
      );

      expect(loginLocation, isNotNull);
      expect(
        intendedDestinationFromLoginUri(Uri.parse(loginLocation!)),
        destination,
      );
    });

    test('rejects external and public post-login destinations', () {
      expect(
        intendedDestinationFromLoginUri(
          Uri.parse('/login?redirect=https%3A%2F%2Fexample.com'),
        ),
        isNull,
      );
      expect(
        intendedDestinationFromLoginUri(
          Uri.parse(
            '/login?redirect=${Uri.encodeQueryComponent(RoutePaths.doctors)}',
          ),
        ),
        isNull,
      );
    });

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

  group('doctor application route', () {
    test('is protected: unauthenticated access redirects to login', () {
      expect(
        sessionRedirect(
          AuthStatus.unauthenticated,
          RoutePaths.doctorApplication,
        ),
        RoutePaths.login,
      );
      expect(protectedRoutes.contains(RoutePaths.doctorApplication), isTrue);
    });

    test('redirect preserves the intended doctor-application destination', () {
      final loginLocation = sessionRedirect(
        AuthStatus.unauthenticated,
        RoutePaths.doctorApplication,
        fullLocation: RoutePaths.doctorApplication,
      );
      expect(loginLocation, isNotNull);
      expect(
        intendedDestinationFromLoginUri(Uri.parse(loginLocation!)),
        RoutePaths.doctorApplication,
      );
    });

    test('authenticated access is not redirected away', () {
      expect(
        sessionRedirect(AuthStatus.authenticated, RoutePaths.doctorApplication),
        isNull,
      );
      expect(
        sessionRedirect(AuthStatus.unknown, RoutePaths.doctorApplication),
        isNull,
      );
    });
  });

  group('protected set', () {
    test(
      'covers patient data, billing, AI, messaging, Doctor Workspace, and administration routes',
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

  group('direct messaging route parsing', () {
    test('accepts UUID conversation identifiers and rejects unsafe values', () {
      const id = '123e4567-e89b-42d3-a456-426614174000';
      expect(validMessageConversationId(id), id);
      expect(validMessageConversationId('../records'), isNull);
      expect(validMessageConversationId('not-a-uuid'), isNull);
    });
  });

  group('doctor workspace routing', () {
    test('dynamic patient files are protected and preserve destination', () {
      const destination =
          '/doctor/patients/11111111-1111-4111-8111-111111111111';
      final login = sessionRedirect(
        AuthStatus.unauthenticated,
        destination,
        fullLocation: destination,
      );
      expect(login, isNotNull);
      expect(intendedDestinationFromLoginUri(Uri.parse(login!)), destination);
    });

    test('non-doctor authenticated roles are redirected away', () {
      expect(
        doctorRoleRedirect(
          AuthStatus.authenticated,
          'patient',
          RoutePaths.doctorWorkspace,
        ),
        RoutePaths.home,
      );
      expect(
        doctorRoleRedirect(
          AuthStatus.authenticated,
          'admin',
          RoutePaths.doctorPatients,
        ),
        RoutePaths.home,
      );
    });

    test('doctor role remains on doctor routes', () {
      expect(
        doctorRoleRedirect(
          AuthStatus.authenticated,
          'doctor',
          RoutePaths.doctorSchedule,
        ),
        isNull,
      );
    });

    test('UUID validation rejects malformed patient ids', () {
      expect(isValidUuid('11111111-1111-4111-8111-111111111111'), isTrue);
      expect(isValidUuid('../patient-1'), isFalse);
      expect(isValidUuid(''), isFalse);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/features/auth/providers/app_role_capabilities_provider.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/home/screens/home_screen.dart';
import 'package:mobile/features/home/screens/services_hub_screen.dart';
import 'package:mobile/features/social/localization/social_strings.dart';
import 'package:mobile/features/social/social_access.dart';
import 'package:mobile/routes/app_router.dart';
import 'package:mobile/routes/main_shell.dart';
import 'package:mobile/routes/route_paths.dart';

void main() {
  const sharedPrimary = [
    RoutePaths.home,
    RoutePaths.socialFeed,
    RoutePaths.discover,
    RoutePaths.services,
    RoutePaths.profile,
  ];

  test('every authenticated role keeps the shared product navigation', () {
    expect(primaryNavigationRoutes, sharedPrimary);
    for (final role in ['patient', 'doctor', 'admin', 'super_admin']) {
      final capabilities = AppRoleCapabilities.fromRole(role);
      expect(capabilities.canUseSharedHome, isTrue, reason: role);
      expect(capabilities.canUseSocialFeed, isTrue, reason: role);
      expect(capabilities.canUsePublicDiscovery, isTrue, reason: role);
      expect(capabilities.canUseBilling, isTrue, reason: role);
      expect(capabilities.canUseNotifications, isTrue, reason: role);
      expect(capabilities.canUseAiChat, isTrue, reason: role);
    }
  });

  group('Feed presentation matrix', () {
    for (final role in ['patient', 'doctor', 'admin', 'super_admin']) {
      test('$role sees Feed in primary navigation and shared Home', () {
        final capabilities = AppRoleCapabilities.fromRole(role);
        expect(capabilities.canUseSocialFeed, isTrue);
        expect(primaryNavigationRoutes, contains(RoutePaths.socialFeed));
        expect(homeShowsSocialFeedAction(capabilities), isTrue);
        expect(
          capabilityRedirect(
            AuthStatus.authenticated,
            role,
            RoutePaths.socialFeed,
          ),
          isNull,
        );
      });
    }

    test('doctor My Posts callback targets existing Doctor Posts', () {
      final capabilities = AppRoleCapabilities.fromRole('doctor');
      expect(socialMyPostsRouteFor(capabilities), RoutePaths.doctorPosts);
      expect(socialComposerAvailableForRole('doctor'), isTrue);
    });

    test('patient and administrator Feed stays consumption-only', () {
      for (final role in ['patient', 'admin', 'super_admin']) {
        final capabilities = AppRoleCapabilities.fromRole(role);
        expect(socialComposerAvailableForRole(role), isFalse, reason: role);
        expect(socialMyPostsRouteFor(capabilities), isNull, reason: role);
      }
    });

    testWidgets('five destinations fit at 320px with 2x text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              bottomNavigationBar: MedOrbitNavigationBar(
                strings: const AppStrings(false),
                socialStrings: const SocialStrings(false),
                selectedIndex: 1,
                onDestinationSelected: (_) {},
              ),
            ),
          ),
        ),
      );

      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigation.labelBehavior,
        NavigationDestinationLabelBehavior.onlyShowSelected,
      );
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.text('Health Feed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('patient receives care tools without doctor or admin tools', () {
    final capabilities = AppRoleCapabilities.fromRole('patient');
    final routes = serviceRoutesFor(capabilities);
    expect(capabilities.canUseCareMessages, isTrue);
    expect(capabilities.canUseConsumerAi, isTrue);
    expect(capabilities.canUsePatientCare, isTrue);
    expect(
      routes,
      containsAll([
        RoutePaths.messages,
        RoutePaths.appointments,
        RoutePaths.records,
        RoutePaths.prescriptions,
        RoutePaths.doctorApplication,
      ]),
    );
    expect(routes, isNot(contains(RoutePaths.doctorWorkspace)));
    expect(routes, isNot(contains(RoutePaths.adminDashboard)));
  });

  test('doctor receives additive workspace and common care services', () {
    final capabilities = AppRoleCapabilities.fromRole('doctor');
    final routes = serviceRoutesFor(capabilities);
    expect(capabilities.canUseCareMessages, isTrue);
    expect(capabilities.canUseConsumerAi, isTrue);
    expect(capabilities.canUseDoctorWorkspace, isTrue);
    expect(capabilities.canCreateDoctorPosts, isTrue);
    expect(
      routes,
      containsAll([
        RoutePaths.messages,
        RoutePaths.chatbot,
        RoutePaths.doctorWorkspace,
        RoutePaths.doctorSchedule,
        RoutePaths.doctorAppointments,
        RoutePaths.doctorPatients,
        RoutePaths.doctorPosts,
      ]),
    );
    expect(routes, isNot(contains(RoutePaths.records)));
    expect(routes, isNot(contains(RoutePaths.prescriptions)));
    expect(routes, isNot(contains(RoutePaths.adminDashboard)));
  });

  test('admin receives operations and primary chat without clinical tools', () {
    final capabilities = AppRoleCapabilities.fromRole('admin');
    final routes = serviceRoutesFor(capabilities);
    expect(capabilities.canUseAdminTools, isTrue);
    expect(capabilities.canUseSuperAdminTools, isFalse);
    expect(
      routes,
      containsAll([
        RoutePaths.billing,
        RoutePaths.chatbot,
        RoutePaths.adminDashboard,
        RoutePaths.adminAnalytics,
        RoutePaths.adminUsers,
        RoutePaths.adminModeration,
      ]),
    );
    expect(routes, isNot(contains(RoutePaths.messages)));
    expect(routes, isNot(contains(RoutePaths.virtualDoctor)));
    expect(routes, isNot(contains(RoutePaths.appointments)));
    expect(routes, isNot(contains(RoutePaths.doctorWorkspace)));
    expect(routes, isNot(contains(RoutePaths.adminInvitations)));
  });

  test('super admin adds invitations to the admin matrix', () {
    final capabilities = AppRoleCapabilities.fromRole('super_admin');
    final routes = serviceRoutesFor(capabilities);
    expect(capabilities.canUseAdminTools, isTrue);
    expect(capabilities.canUseSuperAdminTools, isTrue);
    expect(routes, contains(RoutePaths.adminInvitations));
  });

  test('account switches keep Feed and remove stale role-only actions', () {
    final patient = serviceRoutesFor(AppRoleCapabilities.fromRole('patient'));
    final doctor = serviceRoutesFor(AppRoleCapabilities.fromRole('doctor'));
    final admin = serviceRoutesFor(AppRoleCapabilities.fromRole('admin'));
    final patientAgain = serviceRoutesFor(
      AppRoleCapabilities.fromRole('patient'),
    );

    expect(patient, contains(RoutePaths.records));
    expect(doctor, isNot(contains(RoutePaths.records)));
    expect(doctor, contains(RoutePaths.doctorPosts));
    expect(admin, isNot(contains(RoutePaths.doctorPosts)));
    expect(admin, contains(RoutePaths.adminUsers));
    expect(patientAgain, isNot(contains(RoutePaths.adminUsers)));
    expect(patientAgain, contains(RoutePaths.records));
    for (final role in ['patient', 'doctor', 'admin', 'patient']) {
      final capabilities = AppRoleCapabilities.fromRole(role);
      expect(homeShowsSocialFeedAction(capabilities), isTrue, reason: role);
      expect(primaryNavigationRoutes, contains(RoutePaths.socialFeed));
    }
    expect(
      socialMyPostsRouteFor(AppRoleCapabilities.fromRole('doctor')),
      RoutePaths.doctorPosts,
    );
    expect(
      socialMyPostsRouteFor(AppRoleCapabilities.fromRole('admin')),
      isNull,
    );
    expect(
      socialMyPostsRouteFor(AppRoleCapabilities.fromRole('patient')),
      isNull,
    );
  });

  group('presentation route guards', () {
    test('clinical patient routes reject doctor and admin accounts', () {
      expect(
        capabilityRedirect(
          AuthStatus.authenticated,
          'doctor',
          RoutePaths.records,
        ),
        RoutePaths.home,
      );
      expect(
        capabilityRedirect(
          AuthStatus.authenticated,
          'admin',
          RoutePaths.appointments,
        ),
        RoutePaths.home,
      );
      expect(
        capabilityRedirect(
          AuthStatus.authenticated,
          'patient',
          RoutePaths.records,
        ),
        isNull,
      );
    });

    test('admin gets primary chat but not care messaging or AI tools', () {
      expect(
        capabilityRedirect(
          AuthStatus.authenticated,
          'admin',
          RoutePaths.messages,
        ),
        RoutePaths.home,
      );
      expect(
        capabilityRedirect(
          AuthStatus.authenticated,
          'super_admin',
          RoutePaths.chatbot,
        ),
        isNull,
      );
      expect(
        capabilityRedirect(
          AuthStatus.authenticated,
          'super_admin',
          RoutePaths.virtualDoctor,
        ),
        RoutePaths.home,
      );
    });

    test('shared discovery stays role-neutral', () {
      for (final role in ['patient', 'doctor', 'admin', 'super_admin']) {
        expect(
          capabilityRedirect(
            AuthStatus.authenticated,
            role,
            RoutePaths.discover,
          ),
          isNull,
        );
      }
    });
  });
}

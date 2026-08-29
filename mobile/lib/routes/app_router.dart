import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/analytics/screens/admin_analytics_screen.dart';
import '../features/admin/audit/screens/admin_audit_log_screen.dart';
import '../features/admin/common/providers/admin_access_provider.dart';
import '../features/admin/contact/screens/admin_contact_inbox_screen.dart';
import '../features/admin/dashboard/screens/admin_dashboard_screen.dart';
import '../features/admin/doctor_applications/screens/admin_application_review_screen.dart';
import '../features/admin/doctor_applications/screens/admin_doctor_applications_screen.dart';
import '../features/admin/invitations/screens/admin_invitation_accept_screen.dart';
import '../features/admin/invitations/screens/admin_invitations_screen.dart';
import '../features/admin/moderation/screens/admin_moderation_screen.dart';
import '../features/admin/users/screens/admin_users_screen.dart';
import '../features/appointments/screens/appointments_screen.dart';
import '../features/appointments/screens/book_appointment_screen.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/care/screens/my_doctor_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/auth/screens/verify_code_screen.dart';
import '../features/billing/screens/billing_history_screen.dart';
import '../features/billing/screens/billing_screen.dart';
import '../features/billing/screens/sandbox_checkout_screen.dart';
import '../features/billing/screens/subscription_screen.dart';
import '../features/discovery/screens/clinic_detail_screen.dart';
import '../features/discovery/screens/clinic_discovery_screen.dart';
import '../features/discovery/screens/doctor_detail_screen.dart';
import '../features/discovery/screens/doctor_directory_screen.dart';
import '../features/chatbot/screens/chatbot_screen.dart';
import '../features/contact/screens/contact_screen.dart';
import '../features/chatbot/screens/conversations_screen.dart';
import '../features/discovery/screens/map_foundation_screen.dart';
import '../features/doctor_application/screens/doctor_application_screen.dart';
import '../features/drug_checker/screens/drug_checker_screen.dart';
import '../features/doctor_workspace/screens/doctor_appointments_screen.dart';
import '../features/doctor_workspace/screens/doctor_patient_detail_screen.dart';
import '../features/doctor_workspace/screens/doctor_patients_screen.dart';
import '../features/doctor_workspace/screens/doctor_posts_screen.dart';
import '../features/doctor_workspace/screens/doctor_profile_screen.dart';
import '../features/doctor_workspace/screens/doctor_records_screen.dart';
import '../features/doctor_workspace/screens/doctor_schedule_screen.dart';
import '../features/doctor_workspace/screens/doctor_workspace_screen.dart';
import '../features/feedback/screens/feedback_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/my_reports/screens/my_reports_screen.dart';
import '../features/messaging/screens/message_thread_screen.dart';
import '../features/messaging/screens/messaging_inbox_screen.dart';
import '../features/messaging/screens/new_message_screen.dart';
import '../features/my_doctors/models/patient_doctor_models.dart';
import '../features/my_doctors/screens/my_doctors_screen.dart';
import '../features/my_doctors/screens/shared_doctor_notes_screen.dart';
import '../features/notifications/screens/notifications_screen.dart';
import '../features/prescriptions/screens/prescriptions_screen.dart';
import '../features/profile/screens/profile_screen.dart';
import '../features/records/screens/records_screen.dart';
import '../features/report_summarizer/screens/report_summarizer_screen.dart';
import '../features/splash/screens/splash_screen.dart';
import '../features/saved_places/screens/saved_places_screen.dart';
import '../features/symptom_checker/screens/symptom_checker_screen.dart';
import '../features/virtual_doctor/screens/virtual_doctor_screen.dart';
import 'main_shell.dart';
import 'route_paths.dart';

/// Administration destinations that require an `admin` or `super_admin`
/// session, mirroring the backend's `authorizeAdmin` guard.
const Set<String> adminRoutes = {
  RoutePaths.adminDashboard,
  RoutePaths.adminAnalytics,
  RoutePaths.adminUsers,
  RoutePaths.adminDoctorApplications,
  RoutePaths.adminContactMessages,
  RoutePaths.adminModeration,
  RoutePaths.adminAuditLogs,
  RoutePaths.adminInvitations,
};

/// The subset the backend protects with `authorizeSuperAdmin`. A plain `admin`
/// is turned away from these, not merely from seeing their navigation entry.
const Set<String> superAdminRoutes = {RoutePaths.adminInvitations};

const Set<String> protectedRoutes = {
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
  ...adminRoutes,
  // Session-protected but deliberately not administrator-gated: the account
  // accepting an invitation is still a patient or doctor at that point.
  RoutePaths.adminInvitationAccept,
};

/// True for every location inside the administration area, including
/// parameterized detail routes such as `/admin/doctor-applications/<id>`
/// which cannot be listed as literal members of [adminRoutes].
bool isAdministrationLocation(String location) =>
    location == RoutePaths.adminDashboard ||
    location.startsWith('${RoutePaths.adminDashboard}/');

bool _isSuperAdminLocation(String location) =>
    superAdminRoutes.contains(location) ||
    superAdminRoutes.any(
      (route) => location.startsWith('$route/'),
    );

bool isProtectedLocation(String location) {
  if (protectedRoutes.contains(location) ||
      isAdministrationLocation(location)) {
    return true;
  }
  return location.startsWith('${RoutePaths.conversations}/') ||
      location.startsWith('/billing/sandbox/') ||
      location.startsWith('${RoutePaths.messages}/') ||
      location.startsWith('${RoutePaths.doctorPatients}/');
}

bool isValidUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
).hasMatch(value);

String? doctorRoleRedirect(AuthStatus status, String? role, String location) {
  if (status == AuthStatus.authenticated &&
      location.startsWith('/doctor/') &&
      role?.trim().toLowerCase() != 'doctor') {
    return RoutePaths.home;
  }
  return null;
}

String? sessionRedirect(
  AuthStatus status,
  String location, {
  String? fullLocation,
}) {
  if (status != AuthStatus.unauthenticated) return null;
  if (!isProtectedLocation(location)) return null;
  if (fullLocation == null) return RoutePaths.login;
  return Uri(
    path: RoutePaths.login,
    queryParameters: {'redirect': fullLocation},
  ).toString();
}

/// Role gate for the administration area, applied by the router **before** an
/// admin screen is built — so an unauthorized account never renders a frame of
/// administration data on its way to being redirected.
///
/// Returns `null` (allow) while the session status is still `unknown`: that is
/// the splash bootstrap window, where redirecting would bounce a signed-in
/// administrator on every cold start. The screen's own [AdminGate] holds the
/// line during that window by rendering a neutral placeholder rather than
/// data, and the backend refuses every request regardless.
///
/// Authorization is derived from the canonical auth state on each call; it is
/// never cached or stored separately.
String? adminRedirect(AuthStatus status, String? role, String location) {
  if (!isAdministrationLocation(location)) return null;
  if (location == RoutePaths.adminInvitationAccept) return null;
  // `unauthenticated` is [sessionRedirect]'s to answer, `unknown` is nobody's.
  if (status != AuthStatus.authenticated) return null;

  final access = adminAccessFor(status: status, role: role);
  final allowed = _isSuperAdminLocation(location)
      ? access.canUseSuperAdminTools
      : access.canUseAdminTools;
  return allowed ? null : RoutePaths.home;
}

/// Accepts only an in-app protected route captured by [sessionRedirect].
/// This prevents the Login screen from becoming an open redirect.
String? intendedDestinationFromLoginUri(Uri uri) {
  final raw = uri.queryParameters['redirect'];
  if (raw == null || raw.isEmpty) return null;
  final destination = Uri.tryParse(raw);
  if (destination == null ||
      destination.hasScheme ||
      destination.hasAuthority ||
      !isProtectedLocation(destination.path)) {
    return null;
  }
  return destination.toString();
}

class AuthRouterRefresh extends ChangeNotifier {
  AuthRouterRefresh(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.status != next.status ||
          previous?.user?.id != next.user?.id ||
          previous?.user?.role != next.user?.role) {
        notifyListeners();
      }
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = AuthRouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final session = sessionRedirect(
        auth.status,
        state.matchedLocation,
        fullLocation: state.uri.toString(),
      );
      if (session != null) return session;
      return doctorRoleRedirect(auth.status, auth.user?.role, state.uri.path) ??
          adminRedirect(auth.status, auth.user?.role, state.matchedLocation);
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => LoginScreen(
          intendedDestination: intendedDestinationFromLoginUri(state.uri),
        ),
      ),
      GoRoute(
        path: RoutePaths.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: RoutePaths.verifyCode,
        builder: (context, state) => VerifyCodeScreen(
          initialToken: state.uri.queryParameters['token'],
          initialEmail: state.uri.queryParameters['email'],
        ),
      ),
      GoRoute(
        path: RoutePaths.resetPassword,
        builder: (context, state) => ResetPasswordScreen(
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: RoutePaths.virtualDoctor,
        builder: (context, state) => const VirtualDoctorScreen(),
      ),
      GoRoute(
        path: RoutePaths.billing,
        builder: (context, state) => const BillingScreen(),
      ),
      GoRoute(
        path: RoutePaths.subscription,
        builder: (context, state) => const SubscriptionScreen(),
      ),
      GoRoute(
        path: RoutePaths.billingHistory,
        builder: (context, state) => const BillingHistoryScreen(),
      ),
      GoRoute(
        path: RoutePaths.billingSandbox,
        builder: (context, state) =>
            SandboxCheckoutScreen(token: state.pathParameters['token'] ?? ''),
      ),
      GoRoute(
        path: RoutePaths.chatbot,
        builder: (context, state) => const ChatbotScreen(),
      ),
      GoRoute(
        path: RoutePaths.conversations,
        builder: (context, state) => const ConversationsScreen(),
      ),
      GoRoute(
        path: RoutePaths.messages,
        builder: (context, state) => const MessagingInboxScreen(),
      ),
      GoRoute(
        path: RoutePaths.messagesNew,
        builder: (context, state) => NewMessageScreen(
          initialCounterpartId: validMessageConversationId(
            state.uri.queryParameters['counterpart'],
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.messageThread,
        redirect: (context, state) =>
            validMessageConversationId(state.pathParameters['id']) == null
            ? RoutePaths.messages
            : null,
        builder: (context, state) => MessageThreadScreen(
          conversationId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: RoutePaths.chatbotConversation,
        builder: (context, state) =>
            ChatbotScreen(conversationId: state.pathParameters['id']),
      ),
      GoRoute(
        path: RoutePaths.mapFoundation,
        builder: (context, state) => const MapFoundationScreen(),
      ),
      GoRoute(
        path: RoutePaths.clinics,
        builder: (context, state) => const ClinicDiscoveryScreen(),
      ),
      GoRoute(
        path: RoutePaths.doctors,
        builder: (context, state) => DoctorDirectoryScreen(
          initialSearch: state.uri.queryParameters['search'],
          initialSpecialty: state.uri.queryParameters['specialty'],
        ),
      ),
      GoRoute(
        path: RoutePaths.clinicDetail,
        builder: (context, state) =>
            ClinicDetailScreen(clinicId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: RoutePaths.doctorDetail,
        builder: (context, state) =>
            DoctorDetailScreen(doctorId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: RoutePaths.appointmentBooking,
        builder: (context, state) => BookAppointmentScreen(
          doctorId: state.uri.queryParameters['doctorId'],
        ),
      ),
      GoRoute(
        path: RoutePaths.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: RoutePaths.profile,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: RoutePaths.symptomChecker,
        builder: (context, state) => const SymptomCheckerScreen(),
      ),
      GoRoute(
        path: RoutePaths.drugChecker,
        builder: (context, state) => const DrugCheckerScreen(),
      ),
      GoRoute(
        path: RoutePaths.reportSummarizer,
        builder: (context, state) => const ReportSummarizerScreen(),
      ),
      GoRoute(
        path: RoutePaths.myReports,
        builder: (context, state) => const MyReportsScreen(),
      ),
      GoRoute(
        path: RoutePaths.myDoctors,
        builder: (context, state) => const MyDoctorsScreen(),
      ),
      GoRoute(
        path: RoutePaths.savedPlaces,
        builder: (context, state) => const SavedPlacesScreen(),
      ),
      GoRoute(
        path: RoutePaths.contact,
        builder: (context, state) => const ContactScreen(),
      ),
      GoRoute(
        path: RoutePaths.sharedDoctorNotes,
        builder: (context, state) => SharedDoctorNotesScreen(
          doctorId: state.pathParameters['id'] ?? '',
          doctor: state.extra is PatientDoctor
              ? state.extra as PatientDoctor
              : null,
        ),
      ),
      GoRoute(
        path: RoutePaths.myDoctor,
        builder: (context, state) => const MyDoctorScreen(),
      ),
      GoRoute(
        path: RoutePaths.doctorApplication,
        builder: (context, state) => const DoctorApplicationScreen(),
      ),
      GoRoute(
        path: RoutePaths.doctorWorkspace,
        builder: (context, state) => const DoctorWorkspaceScreen(),
      ),
      GoRoute(
        path: RoutePaths.doctorProfessionalProfile,
        builder: (context, state) => const DoctorProfileScreen(),
      ),
      GoRoute(
        path: RoutePaths.doctorSchedule,
        builder: (context, state) => const DoctorScheduleScreen(),
      ),
      GoRoute(
        path: RoutePaths.doctorPatients,
        builder: (context, state) => const DoctorPatientsScreen(),
      ),
      GoRoute(
        path: RoutePaths.doctorPatient,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return isValidUuid(id)
              ? DoctorPatientDetailScreen(patientId: id)
              : const DoctorPatientsScreen();
        },
      ),
      GoRoute(
        path: RoutePaths.doctorPosts,
        builder: (context, state) => const DoctorPostsScreen(),
      ),
      // ── Administration ─────────────────────────────────────────────────
      GoRoute(
        path: RoutePaths.adminDashboard,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminAnalytics,
        builder: (context, state) => const AdminAnalyticsScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminUsers,
        builder: (context, state) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminDoctorApplications,
        builder: (context, state) => const AdminDoctorApplicationsScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminDoctorApplicationDetail,
        builder: (context, state) => AdminApplicationReviewScreen(
          applicationId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: RoutePaths.adminContactMessages,
        builder: (context, state) => const AdminContactInboxScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminModeration,
        builder: (context, state) => const AdminModerationScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminAuditLogs,
        builder: (context, state) => const AdminAuditLogScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminInvitations,
        builder: (context, state) => const AdminInvitationsScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminInvitationAccept,
        builder: (context, state) => AdminInvitationAcceptScreen(
          initialToken: state.uri.queryParameters['token'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.home,
                builder: (context, state) {
                  final role = ref
                      .read(authControllerProvider)
                      .user
                      ?.role
                      .toLowerCase();
                  if (role == 'doctor') {
                    return const DoctorWorkspaceScreen();
                  }
                  if (role == 'admin' || role == 'super_admin') {
                    return const AdminDashboardScreen();
                  }
                  return const HomeScreen();
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.records,
                builder: (context, state) =>
                    ref.read(authControllerProvider).user?.role.toLowerCase() ==
                        'doctor'
                    ? const DoctorRecordsScreen()
                    : const RecordsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.prescriptions,
                builder: (context, state) =>
                    ref.read(authControllerProvider).user?.role.toLowerCase() ==
                        'doctor'
                    ? const DoctorPatientsScreen()
                    : const PrescriptionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.appointments,
                builder: (context, state) =>
                    ref.read(authControllerProvider).user?.role.toLowerCase() ==
                        'doctor'
                    ? const DoctorAppointmentsScreen()
                    : const AppointmentsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.feedback,
                builder: (context, state) => const FeedbackScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

String? validMessageConversationId(String? value) {
  final candidate = value?.trim() ?? '';
  return RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(candidate)
      ? candidate
      : null;
}

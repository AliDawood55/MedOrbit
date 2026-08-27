import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/appointments/screens/appointments_screen.dart';
import '../features/admin/management/screens/admin_management_screen.dart';
import '../features/doctor_workspace/screens/doctor_patients_screen.dart';
import '../features/appointments/screens/book_appointment_screen.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/auth/screens/verify_code_screen.dart';
import '../features/discovery/screens/clinic_detail_screen.dart';
import '../features/discovery/screens/clinic_discovery_screen.dart';
import '../features/discovery/screens/doctor_detail_screen.dart';
import '../features/discovery/screens/doctor_directory_screen.dart';
import '../features/chatbot/screens/chatbot_screen.dart';
import '../features/contact/screens/contact_screen.dart';
import '../features/chatbot/screens/conversations_screen.dart';
import '../features/discovery/screens/map_foundation_screen.dart';
import '../features/drug_checker/screens/drug_checker_screen.dart';
import '../features/feedback/screens/feedback_screen.dart';
import '../features/home/screens/home_screen.dart';
import '../features/my_reports/screens/my_reports_screen.dart';
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

/// Routes that render data belonging to the signed-in patient.
///
/// Everything else — auth, clinic/doctor discovery, chatbot and Virtual Doctor
/// — is public on mobile exactly as it is on the web, and is deliberately left
/// reachable without a session. Symptom Checker, Drug Checker, and Report
/// Summarizer are a special case: their AI-service calls (`/triage`,
/// `/drug-interactions`, `/summarize`) need no auth either (same as
/// Chatbot/Virtual Doctor), but all three are gated behind login anyway as a
/// deliberate product decision, not a contract requirement. My Reports is
/// gated for a real reason instead: its backend endpoint
/// (`GET /api/reports/summaries`) requires a bearer token and filters by the
/// authenticated user, so an unauthenticated request would 401 regardless.
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
  RoutePaths.adminManagement,
  RoutePaths.doctorPatients,
};

/// Redirect target for [location], or null to allow it.
///
/// Split out from the router so it can be unit-tested without pumping a widget
/// tree. `AuthStatus.unknown` never redirects: that is the splash screen still
/// reading persisted tokens, and bouncing to /login there would break the
/// normal launch of an already-signed-in patient.
String? sessionRedirect(AuthStatus status, String location) {
  if (status != AuthStatus.unauthenticated) return null;
  return protectedRoutes.contains(location) ? RoutePaths.login : null;
}

/// Bridges the auth [StateNotifier] to GoRouter, which needs a [Listenable].
///
/// Only status transitions matter here — notifying on every `AuthState` change
/// would re-run redirects on unrelated updates such as `isSubmitting`.
class AuthRouterRefresh extends ChangeNotifier {
  AuthRouterRefresh(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.status != next.status) notifyListeners();
    });
  }
}

/// The app's router.
///
/// A provider rather than a bare global so it can watch auth state. Kept as a
/// plain (never invalidated) `Provider`, so the `GoRouter` is built once and
/// navigation state survives the rebuilds `MedOrbitApp` performs on a locale
/// change.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = AuthRouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: refresh,
    redirect: (context, state) => sessionRedirect(
      ref.read(authControllerProvider).status,
      state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        builder: (context, state) => const LoginScreen(),
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
        path: RoutePaths.chatbot,
        builder: (context, state) => const ChatbotScreen(),
      ),
      GoRoute(
        path: RoutePaths.conversations,
        builder: (context, state) => const ConversationsScreen(),
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
        builder: (context, state) => const DoctorDirectoryScreen(),
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
        path: RoutePaths.doctorPatients,
        builder: (context, state) => const DoctorPatientsScreen(),
      ),
      GoRoute(
        path: RoutePaths.adminManagement,
        builder: (context, state) =>
            AdminManagementScreen(initialTab: state.uri.queryParameters['tab']),
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.records,
                builder: (context, state) => const RecordsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.prescriptions,
                builder: (context, state) => const PrescriptionsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.appointments,
                builder: (context, state) => const AppointmentsScreen(),
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

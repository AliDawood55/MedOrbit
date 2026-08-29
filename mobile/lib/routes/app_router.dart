import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
};

bool isProtectedLocation(String location) {
  if (protectedRoutes.contains(location)) return true;
  return location.startsWith('${RoutePaths.conversations}/') ||
      location.startsWith('/billing/sandbox/');
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
      if (previous?.status != next.status) notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = AuthRouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: RoutePaths.splash,
    refreshListenable: refresh,
    redirect: (context, state) => sessionRedirect(
      ref.read(authControllerProvider).status,
      state.matchedLocation,
      fullLocation: state.uri.toString(),
    ),
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

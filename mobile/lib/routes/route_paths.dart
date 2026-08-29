class RoutePaths {
  RoutePaths._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String verifyCode = '/verify-code';
  static const String resetPassword = '/reset-password';
  static const String home = '/home';
  static const String records = '/records';
  static const String prescriptions = '/prescriptions';
  static const String appointments = '/appointments';
  static const String appointmentBooking = '/appointments/book';
  static const String feedback = '/feedback';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String symptomChecker = '/symptom-checker';
  static const String drugChecker = '/drug-checker';
  static const String reportSummarizer = '/report-summarizer';
  static const String myReports = '/my-reports';
  static const String myDoctors = '/my-doctors';
  static const String sharedDoctorNotes = '/my-doctors/:id/notes';
  static const String savedPlaces = '/saved-places';
  static const String contact = '/contact';
  static const String myDoctor = '/my-doctor';
  static const String doctorApplication = '/doctor-application';
  static const String virtualDoctor = '/virtual-doctor';
  static const String mapFoundation = '/map-foundation';
  static const String clinics = '/clinics';
  static const String clinicDetail = '/clinics/:id';
  static const String doctors = '/doctors';
  static const String doctorDetail = '/doctors/:id';
  static const String chatbot = '/chatbot';
  static const String conversations = '/chatbot/conversations';
  static const String chatbotConversation = '/chatbot/conversations/:id';
  static const String billing = '/billing';
  static const String subscription = '/billing/subscription';
  static const String billingHistory = '/billing/history';
  static const String billingSandbox = '/billing/sandbox/:token';

  // Direct Messaging / Care Messages
  static const String messages = '/messages';
  static const String messagesNew = '/messages/new';
  static const String messageThread = '/messages/:id';

  // Doctor Workspace. Kept additive to minimize shared-route collisions.
  static const String doctorWorkspace = '/doctor/workspace';
  static const String doctorProfessionalProfile = '/doctor/profile';
  static const String doctorSchedule = '/doctor/schedule';
  static const String doctorPatients = '/doctor/patients';
  static const String doctorPatient = '/doctor/patients/:id';
  static const String doctorPosts = '/doctor/posts';

  static String clinicDetailPath(String id) =>
      '/clinics/${Uri.encodeComponent(id)}';
  static String doctorDetailPath(String id) =>
      '/doctors/${Uri.encodeComponent(id)}';
  static String chatbotConversationPath(String id) =>
      '/chatbot/conversations/${Uri.encodeComponent(id)}';
  static String billingSandboxPath(String token) =>
      '/billing/sandbox/${Uri.encodeComponent(token)}';
  static String sharedDoctorNotesPath(String id) =>
      '/my-doctors/${Uri.encodeComponent(id)}/notes';
  static String messageThreadPath(String id) =>
      '/messages/${Uri.encodeComponent(id)}';
  static String newMessagePath(String counterpartId) =>
      '$messagesNew?counterpart=${Uri.encodeQueryComponent(counterpartId)}';
  static String doctorPatientPath(String id) =>
      '/doctor/patients/${Uri.encodeComponent(id)}';

  static String appointmentBookingPath({String? doctorId}) {
    if (doctorId == null || doctorId.isEmpty) return appointmentBooking;
    return '$appointmentBooking?doctorId=${Uri.encodeQueryComponent(doctorId)}';
  }
}

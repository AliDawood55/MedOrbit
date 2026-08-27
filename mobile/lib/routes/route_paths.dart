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
  static const String adminManagement = '/admin/management';
  static const String doctorPatients = '/doctor/patients';
  static const String virtualDoctor = '/virtual-doctor';
  static const String mapFoundation = '/map-foundation';
  static const String clinics = '/clinics';
  static const String clinicDetail = '/clinics/:id';
  static const String doctors = '/doctors';
  static const String doctorDetail = '/doctors/:id';
  static const String chatbot = '/chatbot';
  static const String conversations = '/chatbot/conversations';
  static const String chatbotConversation = '/chatbot/conversations/:id';

  static String clinicDetailPath(String id) =>
      '/clinics/${Uri.encodeComponent(id)}';
  static String doctorDetailPath(String id) =>
      '/doctors/${Uri.encodeComponent(id)}';
  static String chatbotConversationPath(String id) =>
      '/chatbot/conversations/${Uri.encodeComponent(id)}';
  static String sharedDoctorNotesPath(String id) =>
      '/my-doctors/${Uri.encodeComponent(id)}/notes';

  /// Opens a focused section of the operational console. The base path remains
  /// one protected route; this query parameter only chooses its initial tab.
  static String adminManagementPath({
    String? tab,
    String? role,
    String? metric,
  }) {
    final query = <String, String>{
      if (tab != null && tab.isNotEmpty) 'tab': tab,
      if (role != null && role.isNotEmpty) 'role': role,
      if (metric != null && metric.isNotEmpty) 'metric': metric,
    };
    if (query.isEmpty) return adminManagement;
    return '$adminManagement?${Uri(queryParameters: query).query}';
  }

  static String appointmentBookingPath({String? doctorId}) {
    if (doctorId == null || doctorId.isEmpty) return appointmentBooking;
    return '$appointmentBooking?doctorId=${Uri.encodeQueryComponent(doctorId)}';
  }
}

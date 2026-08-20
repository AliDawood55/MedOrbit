import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/locale/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/appointments/providers/appointments_provider.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/chatbot/providers/chatbot_provider.dart';
import 'features/chatbot/providers/conversations_provider.dart';
import 'features/drug_checker/providers/drug_checker_provider.dart';
import 'features/home/providers/user_provider.dart';
import 'features/my_reports/providers/my_reports_provider.dart';
import 'features/notifications/providers/notifications_provider.dart';
import 'features/prescriptions/providers/prescriptions_provider.dart';
import 'features/profile/providers/profile_provider.dart';
import 'features/records/providers/records_provider.dart';
import 'features/report_summarizer/providers/report_summarizer_provider.dart';
import 'features/symptom_checker/providers/symptom_checker_provider.dart';
import 'routes/app_router.dart';

void main() {
  runApp(const ProviderScope(child: MedOrbitApp()));
}

class MedOrbitApp extends ConsumerWidget {
  const MedOrbitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeControllerProvider);
    final isArabic = locale.languageCode == 'ar';
    final themeMode = ref.watch(themeControllerProvider);

    _clearPatientDataOnSessionEnd(ref);

    return MaterialApp.router(
      title: 'MedOrbit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(isArabic: isArabic),
      darkTheme: AppTheme.dark(isArabic: isArabic),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }

  /// Drops every cached patient-scoped provider the moment the session ends.
  ///
  /// The router redirects away from protected routes, but that alone leaves the
  /// previous patient's records, prescriptions, appointments, notifications,
  /// profile, symptom checker, drug checker, report summarizer input/result,
  /// my reports list, and conversations sitting in memory — and rendered for
  /// a frame on the way out. Covers both explicit logout and an expiry
  /// detected by a failed token refresh, since both land on the same status
  /// transition.
  void _clearPatientDataOnSessionEnd(WidgetRef ref) {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.status != AuthStatus.authenticated ||
          next.status != AuthStatus.unauthenticated) {
        return;
      }
      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(recordsTimelineProvider);
      ref.invalidate(prescriptionsListProvider);
      ref.invalidate(appointmentsControllerProvider);
      ref.invalidate(chatbotControllerProvider);
      ref.invalidate(conversationsControllerProvider);
      ref.invalidate(notificationsControllerProvider);
      ref.invalidate(profileControllerProvider);
      ref.invalidate(symptomCheckerControllerProvider);
      ref.invalidate(drugCheckerControllerProvider);
      ref.invalidate(reportSummarizerControllerProvider);
      ref.invalidate(myReportsControllerProvider);
    });
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/analytics/screens/admin_analytics_screen.dart';
import 'package:mobile/features/admin/analytics/widgets/admin_breakdown_list.dart';
import 'package:mobile/features/admin/analytics/widgets/admin_trend_bars.dart';
import 'package:mobile/features/admin/common/utils/admin_formatting.dart';
import 'package:mobile/features/admin/dashboard/models/admin_dashboard_stats.dart';
import 'package:mobile/features/admin/dashboard/providers/admin_dashboard_provider.dart';

import '../admin_test_support.dart';

Map<String, dynamic> _series(List<String> labels, List<int> counts) => {
  'data': {'labels': labels, 'counts': counts},
};

Map<String, dynamic> _statsPayload({
  Object? usersByRole,
  Object? appointmentsOverTime,
  Object? topSpecialties,
  Object? triageLevels,
  Object? clinicTypes,
  Object? conversationsPerWeek,
}) => {
  'users': {'total': '32', 'patients': '28', 'doctors': '4'},
  'appointments': {
    'total': '11',
    'completed': '6',
    'scheduled': '3',
    'cancelled': '2',
  },
  'medical_records': {'total': '2'},
  'prescriptions': {'total': '4'},
  'ratings': {'average': '4.50'},
  'analytics': {
    'usersByRole':
        usersByRole ??
        _series(['patient', 'doctor', 'super_admin'], [28, 4, 1]),
    'appointmentsOverTime':
        appointmentsOverTime ??
        _series(['2026-01-05', '2026-01-12', '2026-01-19'], [1, 4, 6]),
    'topSpecialties':
        topSpecialties ??
        {
          'data': {
            'items': [
              {'nameAr': 'طب القلب', 'nameEn': 'Cardiology', 'count': 7},
            ],
          },
        },
    'conversationsPerWeek':
        conversationsPerWeek ?? _series(['2026-01-05', '2026-01-12'], [2, 5]),
    'triageLevels':
        triageLevels ?? _series(['emergency', 'routine'], [1, 8]),
    'clinicTypes': clinicTypes ?? _series(['clinic', 'pharmacy'], [3, 2]),
  },
};

Future<void> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? payload,
  Object? error,
  Completer<AdminDashboardStats>? gate,
  String role = 'admin',
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 4000),
}) => pumpAdminScreen(
  tester,
  screen: const AdminAnalyticsScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [
    adminDashboardStatsProvider.overrideWith((ref) {
      if (gate != null) return gate.future;
      if (error != null) return Future.error(error);
      return Future.value(
        AdminDashboardStats.fromJson(payload ?? _statsPayload()),
      );
    }),
  ],
);

void main() {
  testWidgets('a patient is refused', (tester) async {
    await _pump(tester, role: 'patient');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(find.byType(AdminTrendBars), findsNothing);
  });

  testWidgets('shows a loading state before the payload arrives', (
    tester,
  ) async {
    await _pump(tester, gate: Completer<AdminDashboardStats>());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a load failure shows safe copy and Retry', (tester) async {
    await _pump(
      tester,
      error: const ApiException(
        message: 'raw backend detail',
        code: 'FORBIDDEN',
      ),
    );

    expect(find.text(en.adminLoadErrorTitle), findsOneWidget);
    expect(find.text(en.adminError('FORBIDDEN')), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);
    expect(find.byKey(const ValueKey('admin-analytics-retry')), findsOneWidget);
  });

  testWidgets('renders every KPI the endpoint returns', (tester) async {
    await _pump(tester);

    for (final label in [
      en.adminStatsUsers,
      en.adminStatsPatients,
      en.adminStatsDoctors,
      en.adminStatsAppointments,
      en.adminStatsAppointmentsCompleted,
      en.adminStatsAppointmentsScheduled,
      en.adminStatsAppointmentsCancelled,
      en.adminStatsRecords,
      en.adminStatsPrescriptions,
      en.adminStatsRating,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text(adminIsolate('4.50')), findsOneWidget);
    expect(find.text(adminIsolate('32')), findsOneWidget);
  });

  testWidgets('renders the two trends and the four breakdowns', (tester) async {
    await _pump(tester);

    expect(find.text(en.adminAnalyticsAppointmentsOverTime), findsOneWidget);
    expect(find.text(en.adminAnalyticsConversationsPerWeek), findsOneWidget);
    expect(find.text(en.adminAnalyticsUsersByRole), findsOneWidget);
    expect(find.text(en.adminAnalyticsTopSpecialties), findsOneWidget);
    expect(find.text(en.adminAnalyticsTriageLevels), findsOneWidget);
    expect(find.text(en.adminAnalyticsClinicTypes), findsOneWidget);

    expect(find.byType(AdminTrendBars), findsNWidgets(2));
    expect(find.byType(AdminBreakdownList), findsNWidgets(4));
  });

  testWidgets('breakdown labels are localized, never raw enum values', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text(en.rolePatient), findsOneWidget);
    expect(find.text(en.roleSuperAdmin), findsOneWidget);
    expect(find.text(en.adminTriageLabel('emergency')), findsOneWidget);
    expect(find.text(en.adminClinicTypeLabel('pharmacy')), findsOneWidget);
    expect(find.text('super_admin'), findsNothing);
    expect(find.text('vaccination_center'), findsNothing);
  });

  testWidgets('a section the server could not compute says so on its own', (
    tester,
  ) async {
    await _pump(
      tester,
      payload: _statsPayload(triageLevels: {'error': true}),
    );

    expect(find.text(en.adminAnalyticsSectionUnavailable), findsOneWidget);
    // The other five still render.
    expect(find.byType(AdminBreakdownList), findsNWidgets(3));
  });

  testWidgets('an all-zero series reads as awaiting data, not as broken', (
    tester,
  ) async {
    await _pump(
      tester,
      payload: _statsPayload(
        conversationsPerWeek: _series(['2026-01-05', '2026-01-12'], [0, 0]),
      ),
    );

    expect(find.text(en.adminAnalyticsAwaitingData), findsOneWidget);
    expect(find.byType(AdminTrendBars), findsOneWidget);
  });

  testWidgets('with no analytics at all, one honest notice replaces six cards', (
    tester,
  ) async {
    final payload = _statsPayload()..remove('analytics');
    await _pump(tester, payload: payload);

    expect(find.text(en.adminAnalyticsAllUnavailableTitle), findsOneWidget);
    expect(find.text(en.adminAnalyticsAllUnavailableHint), findsOneWidget);
    expect(find.byType(AdminTrendBars), findsNothing);
    expect(find.byType(AdminBreakdownList), findsNothing);
  });

  testWidgets('bars carry an accessible per-bucket label', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      find.bySemanticsLabel(
        '${en.adminAnalyticsWeekOf(adminFormatShortDay('2026-01-19', isArabic: false))}: 6',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 6000),
    );

    expect(find.text(ar.adminAnalyticsTitle), findsWidgets);
    expect(find.text('طب القلب'), findsOneWidget);
    expect(find.text(ar.rolePatient), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

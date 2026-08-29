import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/common/utils/admin_formatting.dart';
import 'package:mobile/features/admin/dashboard/models/admin_dashboard_stats.dart';
import 'package:mobile/features/admin/dashboard/providers/admin_dashboard_provider.dart';
import 'package:mobile/features/admin/dashboard/screens/admin_dashboard_screen.dart';
import 'package:mobile/features/home/data/user_api.dart';
import 'package:mobile/features/home/models/user_profile_model.dart';
import 'package:mobile/features/home/providers/user_provider.dart';
import 'package:mobile/routes/route_paths.dart';

import '../admin_test_support.dart';

final Map<String, dynamic> _statsPayload = {
  'users': {'total': '32', 'patients': '28', 'doctors': '4'},
  'appointments': {'total': '11'},
  'medical_records': {'total': '2'},
  'prescriptions': {'total': '4'},
  'ratings': {'average': '4.5'},
};

UserProfileModel _profile(String role) => UserProfileModel.fromJson({
  'id': adminActorId,
  'email': 'operator@medorbit.test',
  'role': role,
  'first_name_en': 'Sara',
  'last_name_en': 'Nasser',
  'first_name_ar': 'سارة',
  'last_name_ar': 'ناصر',
});

Future<void> _pump(
  WidgetTester tester, {
  String role = 'admin',
  Object? statsError,
  Completer<AdminDashboardStats>? statsGate,
  Object? profileError,
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 3000),
}) => pumpAdminScreen(
  tester,
  screen: const AdminDashboardScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [
    userApiProvider.overrideWithValue(_FakeUserApi(role, profileError)),
    adminDashboardStatsProvider.overrideWith((ref) {
      if (statsGate != null) return statsGate.future;
      if (statsError != null) return Future.error(statsError);
      return Future.value(AdminDashboardStats.fromJson(_statsPayload));
    }),
  ],
  extraRoutes: [
    for (final path in [
      RoutePaths.adminUsers,
      RoutePaths.adminDoctorApplications,
      RoutePaths.adminContactMessages,
      RoutePaths.adminModeration,
      RoutePaths.adminInvitations,
      RoutePaths.adminAnalytics,
      RoutePaths.adminAuditLogs,
    ])
      GoRoute(
        path: path,
        builder: (_, _) => Scaffold(body: Text(path, key: ValueKey(path))),
      ),
  ],
);

void main() {
  testWidgets('a patient is refused the hub', (tester) async {
    await _pump(tester, role: 'patient');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-tool-users')), findsNothing);
  });

  testWidgets('an administrator sees identity, KPIs and the tool list', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Sara Nasser', findRichText: true), findsNothing);
    expect(find.textContaining('Sara Nasser'), findsOneWidget);
    expect(find.text(en.roleAdmin), findsOneWidget);
    expect(find.text(en.adminStatsUsers), findsOneWidget);
    expect(find.text(adminIsolate('32')), findsOneWidget);

    for (final key in [
      'admin-tool-users',
      'admin-tool-applications',
      'admin-tool-contact',
      'admin-tool-moderation',
      'admin-tool-analytics',
      'admin-tool-audit',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('the invitation tool is hidden from an ordinary admin', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const ValueKey('admin-tool-invitations')), findsNothing);
  });

  testWidgets('a super admin sees the invitation tool and the super badge', (
    tester,
  ) async {
    await _pump(tester, role: 'super_admin');

    expect(
      find.byKey(const ValueKey('admin-tool-invitations')),
      findsOneWidget,
    );
    expect(find.text(en.roleSuperAdmin), findsOneWidget);
  });

  testWidgets('each tool opens its own route', (tester) async {
    await _pump(tester);

    await tapByKey(tester, const ValueKey('admin-tool-users'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(RoutePaths.adminUsers)), findsOneWidget);
  });

  testWidgets('a stats failure degrades to a retryable card, not a blank hub', (
    tester,
  ) async {
    await _pump(
      tester,
      statsError: const ApiException(
        message: 'raw backend detail',
        code: 'INTERNAL_ERROR',
      ),
    );

    expect(
      find.byKey(const ValueKey('admin-dashboard-stats-error')),
      findsOneWidget,
    );
    expect(find.text(en.adminError('INTERNAL_ERROR')), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);
    // The tools are still usable while the numbers are not.
    expect(find.byKey(const ValueKey('admin-tool-users')), findsOneWidget);
  });

  testWidgets('a profile failure degrades to a retryable header', (
    tester,
  ) async {
    await _pump(
      tester,
      profileError: const ApiException(
        message: 'raw backend detail',
        code: 'INTERNAL_ERROR',
      ),
    );

    expect(find.byKey(const ValueKey('admin-identity-retry')), findsOneWidget);
    expect(find.text(en.profileLoadErrorTitle), findsOneWidget);
    expect(find.byKey(const ValueKey('admin-tool-users')), findsOneWidget);
  });

  testWidgets('stats are still loading without blocking the tools', (
    tester,
  ) async {
    await _pump(tester, statsGate: Completer<AdminDashboardStats>());

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.byKey(const ValueKey('admin-tool-users')), findsOneWidget);
  });

  testWidgets('an administrator is never offered patient tools', (
    tester,
  ) async {
    await _pump(tester);

    // Patient-only sections of the ordinary Home screen. (`navPrescriptions`
    // is deliberately not asserted here: it is the same word as the
    // `adminStatsPrescriptions` KPI label, which an administrator does see.)
    for (final label in [
      en.upcomingAppointmentsTitle,
      en.recentPrescriptionsTitle,
      en.recentMedicalRecordsTitle,
      en.quickActionsTitle,
      en.dashboardSearchLabel,
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });

  testWidgets('logging out returns to login', (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip(en.logoutTooltip));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login')), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      role: 'super_admin',
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 5000),
    );

    expect(find.text(ar.adminToolsTitle), findsOneWidget);
    expect(find.textContaining('سارة ناصر'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeUserApi extends UserApi {
  _FakeUserApi(this._role, this._error) : super(Dio());

  final String _role;
  final Object? _error;

  @override
  Future<UserProfileModel> getMe() {
    if (_error != null) return Future.error(_error);
    return Future.value(_profile(_role));
  }
}

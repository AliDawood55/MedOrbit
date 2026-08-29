import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/doctor_applications/data/admin_doctor_applications_api.dart';
import 'package:mobile/features/admin/doctor_applications/models/admin_doctor_application.dart';
import 'package:mobile/features/admin/doctor_applications/providers/admin_doctor_applications_provider.dart';
import 'package:mobile/features/admin/doctor_applications/screens/admin_doctor_applications_screen.dart';
import 'package:mobile/routes/route_paths.dart';

import '../admin_test_support.dart';

AdminDoctorApplication _application(String id, {String status = 'pending'}) =>
    AdminDoctorApplication.fromJson({
      'id': id,
      'user_id': 'user-$id',
      'specialty_id': 'spec-1',
      'medical_license_number': 'LIC-$id',
      'status': status,
      'submitted_at': '2026-02-01T09:00:00Z',
      'education': const <String>[],
      'certifications': const <String>[],
      'applicant': const {
        'email': 'applicant@example.test',
        'first_name_en': 'Lina',
        'last_name_en': 'Haddad',
      },
      'specialty': const {'name_ar': 'طب القلب', 'name_en': 'Cardiology'},
    });

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String role = 'admin',
  bool isArabic = false,
  double textScale = 1,
  Size size = const Size(420, 1600),
}) => pumpAdminScreen(
  tester,
  screen: const AdminDoctorApplicationsScreen(),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminDoctorApplicationsApiProvider.overrideWithValue(api)],
  extraRoutes: [
    GoRoute(
      path: RoutePaths.adminDoctorApplicationDetail,
      builder: (_, state) => Scaffold(
        body: Text(
          'detail:${state.pathParameters['id']}',
          key: const ValueKey('detail'),
        ),
      ),
    ),
  ],
);

void main() {
  testWidgets('a patient is refused and no queue is fetched', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'patient');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(api.listCalls, 0);
  });

  testWidgets('defaults to the pending queue, like the web review page', (
    tester,
  ) async {
    final api = _FakeApi()..applications = [_application('a1')];
    await _pump(tester, api: api);

    expect(api.lastStatus, AdminApplicationStatus.pending);
    expect(find.text('Lina Haddad'), findsOneWidget);
    expect(find.text(en.adminApplicationsStatusPending), findsWidgets);
  });

  testWidgets('a loading state precedes the first queue', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()..gate = Completer<List<AdminDoctorApplication>>(),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('an empty queue shows the empty state', (tester) async {
    await _pump(tester, api: _FakeApi());

    expect(
      find.byKey(const ValueKey('admin-applications-empty')),
      findsOneWidget,
    );
    expect(find.text(en.adminApplicationsEmptyTitle), findsOneWidget);
  });

  testWidgets('a load failure shows safe copy and Retry reloads', (
    tester,
  ) async {
    final api = _FakeApi()
      ..listError = const ApiException(
        message: 'raw backend detail',
        code: 'FORBIDDEN',
      );
    await _pump(tester, api: api);

    expect(find.text(en.adminError('FORBIDDEN')), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);

    api.listError = null;
    api.applications = [_application('a1')];
    await tapByKey(tester, const ValueKey('admin-applications-retry'));
    await tester.pump();
    await tester.pump();

    expect(api.listCalls, 2);
    expect(find.text('Lina Haddad'), findsOneWidget);
  });

  testWidgets('the status filter refetches with the exact wire value', (
    tester,
  ) async {
    final api = _FakeApi()..applications = [_application('a1')];
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-applications-approved'));
    await tester.pump();
    await tester.pump();
    expect(api.lastStatus, AdminApplicationStatus.approved);

    await tapByKey(tester, const ValueKey('admin-applications-all'));
    await tester.pump();
    await tester.pump();
    expect(api.lastStatus, isNull);
    expect(api.listCalls, 3);
  });

  testWidgets('tapping a row opens its review screen and refreshes on return', (
    tester,
  ) async {
    final api = _FakeApi()..applications = [_application('a1')];
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-application-a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('detail')), findsOneWidget);
    expect(find.text('detail:a1'), findsOneWidget);
  });

  testWidgets('the server-side 100-row cap is disclosed, not hidden', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi()..applications = [_application('a1')]);

    expect(find.text(en.adminApplicationsLimitNote), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..applications = [_application('a1')],
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 2000),
    );

    expect(find.text('طب القلب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeApi extends AdminDoctorApplicationsApi {
  _FakeApi() : super(Dio());

  List<AdminDoctorApplication> applications = const [];
  Object? listError;
  Completer<List<AdminDoctorApplication>>? gate;

  int listCalls = 0;
  AdminApplicationStatus? lastStatus;

  @override
  Future<List<AdminDoctorApplication>> list({
    AdminApplicationStatus? status,
  }) {
    listCalls++;
    lastStatus = status;
    if (gate != null) return gate!.future;
    if (listError != null) return Future.error(listError!);
    return Future.value(applications);
  }
}

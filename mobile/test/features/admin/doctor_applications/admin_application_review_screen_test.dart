import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/doctor_applications/data/admin_doctor_applications_api.dart';
import 'package:mobile/features/admin/doctor_applications/models/admin_doctor_application.dart';
import 'package:mobile/features/admin/doctor_applications/providers/admin_doctor_applications_provider.dart';
import 'package:mobile/features/admin/doctor_applications/screens/admin_application_review_screen.dart';

import '../admin_test_support.dart';

AdminDoctorApplication _application({
  String status = 'pending',
  String? rejectionReason,
  String? reviewedAt,
}) => AdminDoctorApplication.fromJson({
  'id': 'app-1',
  'user_id': 'user-1',
  'specialty_id': 'spec-1',
  'medical_license_number': 'LIC-9',
  'sub_specialty': 'Interventional',
  'years_of_experience': 7,
  'education': const <String>['MD, An-Najah'],
  'certifications': const <String>['Board certified'],
  'bio': 'Cardiologist',
  'status': status,
  'submitted_at': '2026-02-01T09:00:00Z',
  'reviewed_at': reviewedAt,
  'rejection_reason': rejectionReason,
  'applicant': const {
    'email': 'applicant@example.test',
    'first_name_ar': 'لينا',
    'last_name_ar': 'حداد',
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
  Size size = const Size(420, 2000),
}) => pumpAdminScreen(
  tester,
  screen: const AdminApplicationReviewScreen(applicationId: 'app-1'),
  role: role,
  isArabic: isArabic,
  textScale: textScale,
  surfaceSize: size,
  overrides: [adminDoctorApplicationsApiProvider.overrideWithValue(api)],
);

void main() {
  testWidgets('a patient is refused and no application is fetched', (
    tester,
  ) async {
    final api = _FakeApi();
    await _pump(tester, api: api, role: 'patient');

    expect(find.byKey(const ValueKey('admin-restricted')), findsOneWidget);
    expect(api.getCalls, 0);
  });

  testWidgets('always re-reads the application before offering a decision', (
    tester,
  ) async {
    final api = _FakeApi()..gate = Completer<AdminDoctorApplication>();
    await _pump(tester, api: api);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-application-approve')),
      findsNothing,
    );
    expect(api.getCalls, 1);
  });

  testWidgets('renders applicant and professional detail for a pending row', (
    tester,
  ) async {
    await _pump(tester, api: _FakeApi()..application = _application());

    expect(find.text('Lina Haddad'), findsOneWidget);
    expect(find.text('applicant@example.test'), findsWidgets);
    expect(find.text('LIC-9'), findsOneWidget);
    expect(find.text('Cardiology'), findsOneWidget);
    expect(find.text(en.adminApplicationYears(7)), findsOneWidget);
    expect(find.text('MD, An-Najah'), findsOneWidget);
    expect(find.text(en.adminApplicationsStatusPending), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-application-approve')),
      findsOneWidget,
    );
  });

  testWidgets('a decided application shows no decision buttons', (tester) async {
    await _pump(
      tester,
      api: _FakeApi()
        ..application = _application(
          status: 'rejected',
          rejectionReason: 'Licence could not be verified',
          reviewedAt: '2026-02-05T09:00:00Z',
        ),
    );

    expect(find.text(en.adminApplicationsStatusRejected), findsOneWidget);
    expect(find.text('Licence could not be verified'), findsOneWidget);
    expect(find.text(en.adminApplicationDecidedNote), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-application-approve')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('admin-application-reject')), findsNothing);
  });

  testWidgets('approval is confirmed, then sent, then re-read', (tester) async {
    final api = _FakeApi()..application = _application();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-application-approve'));
    await tester.pumpAndSettle();
    expect(find.text(en.adminApplicationApproveTitle), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, en.cancel));
    await tester.pumpAndSettle();
    expect(api.approveCalls, 0);

    api.application = _application(
      status: 'approved',
      reviewedAt: '2026-02-05T09:00:00Z',
    );
    await tapByKey(tester, const ValueKey('admin-application-approve'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-application-approve-confirm')),
    );
    await tester.pumpAndSettle();

    expect(api.approveCalls, 1);
    expect(api.getCalls, 2);
    expect(find.text(en.adminApplicationApprovedSuccess), findsOneWidget);
    expect(find.text(en.adminApplicationDecidedNote), findsOneWidget);
  });

  testWidgets('rejection requires a reason before the request is sent', (
    tester,
  ) async {
    final api = _FakeApi()..application = _application();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-application-reject'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('admin-application-reject-submit')),
    );
    await tester.pumpAndSettle();

    expect(api.rejectCalls, 0);
    expect(
      find.text(en.adminApplicationRejectReasonRequired),
      findsOneWidget,
    );
  });

  testWidgets('rejection sends the trimmed reason the backend requires', (
    tester,
  ) async {
    final api = _FakeApi()..application = _application();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-application-reject'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('admin-application-reject-reason')),
      '  Licence could not be verified  ',
    );
    api.application = _application(
      status: 'rejected',
      rejectionReason: 'Licence could not be verified',
    );
    await tester.tap(
      find.byKey(const ValueKey('admin-application-reject-submit')),
    );
    await tester.pumpAndSettle();

    expect(api.rejectCalls, 1);
    expect(api.lastReason, 'Licence could not be verified');
    expect(find.text(en.adminApplicationRejectedSuccess), findsOneWidget);
  });

  testWidgets('a failed decision shows mapped copy, never the raw message', (
    tester,
  ) async {
    final api = _FakeApi()
      ..application = _application()
      ..decisionError = const ApiException(
        message: 'Pending application not found for user@example.test',
        code: 'NOT_FOUND',
      );
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-application-approve'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-application-approve-confirm')),
    );
    await tester.pumpAndSettle();

    expect(find.text(en.adminError('NOT_FOUND')), findsOneWidget);
    expect(find.textContaining('user@example.test'), findsNothing);
  });

  testWidgets('both decision buttons are disabled while one is in flight', (
    tester,
  ) async {
    final api = _FakeApi()
      ..application = _application()
      ..decisionGate = Completer<void>();
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-application-approve'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-application-approve-confirm')),
    );
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('admin-application-approve')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('admin-application-reject')),
          )
          .onPressed,
      isNull,
    );
    expect(api.approveCalls, 1);
  });

  testWidgets('a load failure shows retry and reloads', (tester) async {
    final api = _FakeApi()
      ..getError = const ApiException(
        message: 'raw backend detail',
        code: 'INTERNAL_ERROR',
      );
    await _pump(tester, api: api);

    expect(find.text(en.adminLoadErrorTitle), findsOneWidget);
    expect(find.textContaining('raw backend detail'), findsNothing);

    api.getError = null;
    api.application = _application();
    await tapByKey(tester, const ValueKey('admin-application-retry'));
    await tester.pump();
    await tester.pump();

    expect(api.getCalls, 2);
    expect(find.text('Lina Haddad'), findsOneWidget);
  });

  testWidgets('renders in Arabic RTL at 1.5x on a 320 px viewport', (
    tester,
  ) async {
    await _pump(
      tester,
      api: _FakeApi()..application = _application(),
      isArabic: true,
      textScale: 1.5,
      size: const Size(320, 3000),
    );

    expect(find.text('لينا حداد'), findsOneWidget);
    expect(find.text('طب القلب'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing during an in-flight decision does not throw', (
    tester,
  ) async {
    final gate = Completer<void>();
    final api = _FakeApi()
      ..application = _application()
      ..decisionGate = gate;
    await _pump(tester, api: api);

    await tapByKey(tester, const ValueKey('admin-application-approve'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('admin-application-approve-confirm')),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

class _FakeApi extends AdminDoctorApplicationsApi {
  _FakeApi() : super(Dio());

  AdminDoctorApplication? application;
  Object? getError;
  Completer<AdminDoctorApplication>? gate;
  Object? decisionError;
  Completer<void>? decisionGate;

  int getCalls = 0;
  int approveCalls = 0;
  int rejectCalls = 0;
  String? lastReason;

  @override
  Future<List<AdminDoctorApplication>> list({
    AdminApplicationStatus? status,
  }) async => application == null ? const [] : [application!];

  @override
  Future<AdminDoctorApplication> get(String applicationId) {
    getCalls++;
    if (gate != null) return gate!.future;
    if (getError != null) return Future.error(getError!);
    return Future.value(application!);
  }

  @override
  Future<void> approve(String applicationId) {
    approveCalls++;
    return _decide();
  }

  @override
  Future<void> reject(String applicationId, String reason) {
    rejectCalls++;
    lastReason = reason;
    return _decide();
  }

  Future<void> _decide() {
    if (decisionGate != null) return decisionGate!.future;
    if (decisionError != null) return Future.error(decisionError!);
    return Future.value();
  }
}

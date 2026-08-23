import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/appointments/data/appointments_api.dart';
import 'package:mobile/features/appointments/models/appointment_model.dart';
import 'package:mobile/features/appointments/providers/appointments_provider.dart';
import 'package:mobile/features/appointments/screens/appointments_screen.dart';
import 'package:mobile/routes/route_paths.dart';

const _strings = AppStrings(false); // English, matching the default direction used below

String _futureDate() {
  final date = DateTime.now().add(const Duration(days: 7));
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _pastDate() {
  final date = DateTime.now().subtract(const Duration(days: 7));
  return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

AppointmentModel _appointment({
  required String id,
  required String status,
  String? scheduledDate,
}) {
  return AppointmentModel.fromJson({
    'id': id,
    'appointment_number': 'APT-$id',
    'doctor_id': 'doctor-1',
    'scheduled_date': scheduledDate ?? _futureDate(),
    'start_time': '09:00:00',
    'end_time': '09:30:00',
    'status': status,
  });
}

Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _switchTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('cancel button eligibility', () {
    testWidgets('visible for a scheduled upcoming appointment', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()..listResult = Future.value([_appointment(id: '1', status: 'scheduled')]);
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();

      expect(find.text(_strings.cancelAppointmentAction), findsOneWidget);
    });

    testWidgets('visible for a confirmed upcoming appointment', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()..listResult = Future.value([_appointment(id: '1', status: 'confirmed')]);
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();

      expect(find.text(_strings.cancelAppointmentAction), findsOneWidget);
    });

    testWidgets('absent for an in_progress appointment even though it sorts into the Upcoming tab', (tester) async {
      await _useTallSurface(tester);
      // A future-dated in_progress row lands in Upcoming by date/status routing,
      // so only the per-card status check (not tab routing) can hide Cancel here.
      final api = _FakeAppointmentsApi()..listResult = Future.value([_appointment(id: '1', status: 'in_progress')]);
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();

      expect(find.textContaining('APT-1'), findsOneWidget);
      expect(find.text(_strings.cancelAppointmentAction), findsNothing);
    });

    testWidgets('absent for a completed appointment in the Past tab', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()
        ..listResult = Future.value([_appointment(id: '1', status: 'completed', scheduledDate: _pastDate())]);
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();
      await _switchTab(tester, _strings.tabPast);

      expect(find.textContaining('APT-1'), findsOneWidget);
      expect(find.text(_strings.cancelAppointmentAction), findsNothing);
    });

    testWidgets('absent for a no_show appointment in the Past tab', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()
        ..listResult = Future.value([_appointment(id: '1', status: 'no_show', scheduledDate: _pastDate())]);
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();
      await _switchTab(tester, _strings.tabPast);

      expect(find.textContaining('APT-1'), findsOneWidget);
      expect(find.text(_strings.cancelAppointmentAction), findsNothing);
    });

    testWidgets('absent for a cancelled appointment in the Cancelled tab', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()..listResult = Future.value([_appointment(id: '1', status: 'cancelled')]);
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();
      await _switchTab(tester, _strings.tabCancelled);

      expect(find.textContaining('APT-1'), findsOneWidget);
      expect(find.text(_strings.cancelAppointmentAction), findsNothing);
    });
  });

  group('cancellation flow', () {
    testWidgets('dismissing the confirmation dialog sends no request', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()..listResult = Future.value([_appointment(id: '1', status: 'scheduled')]);
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_strings.cancelAppointmentAction));
      await tester.pumpAndSettle();
      expect(find.text(_strings.cancelDialogTitle), findsOneWidget);
      await tester.tap(find.text(_strings.cancel));
      await tester.pumpAndSettle();

      expect(api.cancelCalls, isEmpty);
      expect(find.text(_strings.cancelDialogTitle), findsNothing);
    });

    testWidgets('confirming sends exactly one request and shows success feedback', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()
        ..listResult = Future.value([_appointment(id: '1', status: 'scheduled')])
        ..cancelResults.add(_appointment(id: '1', status: 'cancelled'));
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_strings.cancelAppointmentAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_strings.cancelConfirm));
      await tester.pumpAndSettle();

      expect(api.cancelCalls, hasLength(1));
      expect(api.cancelCalls.single.id, '1');
      expect(find.text(_strings.cancelSuccessMessage), findsOneWidget);
    });

    testWidgets('a failed cancel shows failure feedback and leaves the appointment in Upcoming', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()
        ..listResult = Future.value([_appointment(id: '1', status: 'scheduled')])
        ..cancelResults.add(
          const ApiException(message: 'Server error', code: ApiException.codeHttpError, statusCode: 500),
        );
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_strings.cancelAppointmentAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_strings.cancelConfirm));
      await tester.pumpAndSettle();

      expect(find.text(_strings.cancelErrorMessage), findsOneWidget);
      expect(find.text(_strings.cancelAppointmentAction), findsOneWidget, reason: 'still cancellable — the local list was not mutated on failure');
    });

    testWidgets('a successful cancel moves the card from Upcoming to Cancelled without a manual refresh', (tester) async {
      await _useTallSurface(tester);
      final api = _FakeAppointmentsApi()
        ..listResult = Future.value([_appointment(id: '1', status: 'scheduled')])
        ..cancelResults.add(_appointment(id: '1', status: 'cancelled'));
      await tester.pumpWidget(_app(api: api));
      await tester.pumpAndSettle();

      await tester.tap(find.text(_strings.cancelAppointmentAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_strings.cancelConfirm));
      await tester.pumpAndSettle();

      expect(find.textContaining('APT-1'), findsNothing, reason: 'no longer in the still-visible Upcoming tab');
      await _switchTab(tester, _strings.tabCancelled);
      expect(find.textContaining('APT-1'), findsOneWidget);
    });
  });
}

Widget _app({required AppointmentsApi api}) {
  final router = GoRouter(
    initialLocation: RoutePaths.appointments,
    routes: [
      GoRoute(path: RoutePaths.appointments, builder: (context, state) => const AppointmentsScreen()),
      GoRoute(path: RoutePaths.appointmentBooking, builder: (context, state) => const Text('booking-stub')),
    ],
  );

  return ProviderScope(
    overrides: [
      appointmentsApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(isArabic: false),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    ),
  );
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}

  @override
  Future<String?> getThemeMode() async => null;

  @override
  Future<void> saveThemeMode(String mode) async {}
}

class _FakeAppointmentsApi extends AppointmentsApi {
  _FakeAppointmentsApi() : super(Dio());

  Future<List<AppointmentModel>>? listResult;
  // Holds an `AppointmentModel` for success or any other `Object` to throw,
  // built into a `Future` lazily inside `cancel()` so an unconsumed
  // `Future.error(...)` never trips the test zone's uncaught-exception check.
  final cancelResults = <Object>[];
  final cancelCalls = <({String id, String? reason})>[];

  @override
  Future<List<AppointmentModel>> list() => listResult ?? Future.value(const []);

  @override
  Future<AppointmentModel> cancel(String id, {String? reason}) {
    cancelCalls.add((id: id, reason: reason));
    final next = cancelResults.removeAt(0);
    if (next is AppointmentModel) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<(String? ar, String? en)> getDoctorName(String doctorId) async => (null, null);

  @override
  Future<(String? ar, String? en)> getClinicName(String clinicId) async => (null, null);
}

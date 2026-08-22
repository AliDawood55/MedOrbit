import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/appointments/data/appointments_api.dart';
import 'package:mobile/features/appointments/models/appointment_model.dart';
import 'package:mobile/features/appointments/providers/appointments_provider.dart';
import 'package:mobile/features/care/data/care_api.dart';
import 'package:mobile/features/care/models/my_doctor_model.dart';
import 'package:mobile/features/care/models/shared_note_model.dart';
import 'package:mobile/features/care/providers/care_provider.dart';
import 'package:mobile/features/care/screens/my_doctor_screen.dart';
import 'package:mobile/routes/route_paths.dart';

const _strings = AppStrings(false); // English, matching the default direction used below
const _canary = 'INTERNAL_ONLY_DO_NOT_RENDER';

MyDoctorModel _doctor({String id = 'doctor-1'}) {
  return MyDoctorModel.fromJson({
    'id': id,
    'first_name_en': 'Ahmad',
    'last_name_en': 'Mahmoud',
    'specialty_en': 'Cardiology',
  });
}

AppointmentModel _appointment({required String doctorId}) {
  return AppointmentModel.fromJson({
    'id': 'appt-1',
    'appointment_number': 'APT-2026-001',
    'doctor_id': doctorId,
    'scheduled_date': '2099-01-01',
    'start_time': '09:00:00',
    'end_time': '09:30:00',
    'status': 'scheduled',
  });
}

Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('loaded My Doctor screen renders the doctor card and section headers', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()..doctorsResults.add([_doctor()]);
    await tester.pumpWidget(_app(careApi: careApi));
    await tester.pumpAndSettle();

    expect(find.text(_strings.myDoctorsSectionTitle), findsOneWidget);
    expect(find.text(_strings.upcomingWithMyDoctorsTitle), findsOneWidget);
    expect(find.text(_strings.sharedNotesSectionTitle), findsOneWidget);
    expect(find.text('Ahmad Mahmoud'), findsOneWidget);
    expect(find.text('Cardiology'), findsOneWidget);
  });

  testWidgets('no active doctors shows the honest empty state with a Browse Doctors CTA', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()..doctorsResults.add(const <MyDoctorModel>[]);
    await tester.pumpWidget(_app(careApi: careApi));
    await tester.pumpAndSettle();

    expect(find.text(_strings.noActiveDoctorsTitle), findsOneWidget);

    await tester.tap(find.text(_strings.browseDoctorsAction));
    await tester.pumpAndSettle();

    expect(find.text('doctors-stub'), findsOneWidget);
  });

  testWidgets('View Doctor navigates to the doctor detail route', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()..doctorsResults.add([_doctor(id: 'doctor-42')]);
    await tester.pumpWidget(_app(careApi: careApi));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_strings.viewDoctorAction));
    await tester.pumpAndSettle();

    expect(find.text('doctor-detail-stub:doctor-42'), findsOneWidget);
  });

  testWidgets('Book Appointment navigates to booking with the doctor id', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()..doctorsResults.add([_doctor(id: 'doctor-42')]);
    await tester.pumpWidget(_app(careApi: careApi));
    await tester.pumpAndSettle();

    await tester.tap(find.text(_strings.bookAppointmentWithDoctorAction));
    await tester.pumpAndSettle();

    expect(find.text('booking-stub:doctor-42'), findsOneWidget);
  });

  testWidgets('upcoming appointments with my doctors renders a filtered appointment', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()..doctorsResults.add([_doctor()]);
    final appointmentsApi = _FakeAppointmentsApi()
      ..listResult = Future.value([_appointment(doctorId: 'doctor-1')]);
    await tester.pumpWidget(_app(careApi: careApi, appointmentsApi: appointmentsApi));
    await tester.pumpAndSettle();

    expect(find.textContaining('APT-2026-001'), findsOneWidget);
    expect(find.text(_strings.noUpcomingWithMyDoctorsTitle), findsNothing);
  });

  testWidgets('shared notes render legitimate clinical content', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()
      ..doctorsResults.add([_doctor()])
      ..sharedNotesResults['doctor-1'] = [
        SharedNoteModel.fromJson({
          'id': 'note-1',
          'record_type': 'consultation',
          'clinical_notes': 'Patient responded well to treatment.',
        }),
      ];
    await tester.pumpWidget(_app(careApi: careApi));
    await tester.pumpAndSettle();

    expect(find.text('Patient responded well to treatment.'), findsOneWidget);
    expect(find.text(_strings.noSharedNotesTitle), findsNothing);
  });

  testWidgets('a shared-notes failure shows a distinct error, never the empty state', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()
      ..doctorsResults.add([_doctor()])
      ..sharedNotesResults['doctor-1'] = Exception('network down');
    await tester.pumpWidget(_app(careApi: careApi));
    await tester.pumpAndSettle();

    expect(find.text(_strings.sharedNotesErrorTitle), findsOneWidget);
    expect(find.text(_strings.noSharedNotesTitle), findsNothing);
  });

  testWidgets('PRIVACY CANARY: a doctor_notes field in the shared-note payload is never rendered', (tester) async {
    await _useTallSurface(tester);
    final careApi = _FakeCareApi()
      ..doctorsResults.add([_doctor()])
      ..sharedNotesResults['doctor-1'] = [
        SharedNoteModel.fromJson({
          'id': 'note-1',
          'doctor_notes': _canary,
          'clinical_notes': 'Legitimate shared note.',
        }),
      ];
    await tester.pumpWidget(_app(careApi: careApi));
    await tester.pumpAndSettle();

    expect(find.textContaining(_canary), findsNothing);
    expect(find.text('Legitimate shared note.'), findsOneWidget);
  });
}

Widget _app({required CareApi careApi, AppointmentsApi? appointmentsApi}) {
  final router = GoRouter(
    initialLocation: RoutePaths.myDoctor,
    routes: [
      GoRoute(path: RoutePaths.myDoctor, builder: (context, state) => const MyDoctorScreen()),
      GoRoute(path: RoutePaths.doctors, builder: (context, state) => const Text('doctors-stub')),
      GoRoute(
        path: RoutePaths.doctorDetail,
        builder: (context, state) => Text('doctor-detail-stub:${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: RoutePaths.appointmentBooking,
        builder: (context, state) => Text('booking-stub:${state.uri.queryParameters['doctorId']}'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      careApiProvider.overrideWithValue(careApi),
      appointmentsApiProvider.overrideWithValue(appointmentsApi ?? _FakeAppointmentsApi()),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
      activeOriginProvider.overrideWithValue('https://example.test'),
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

class _FakeCareApi extends CareApi {
  _FakeCareApi() : super(Dio());

  // Holds a `List<...>` for success or any other `Object` to throw, built
  // into a `Future` lazily inside `myDoctors()`/`sharedNotes()` — a widget
  // test drives several real `pump()`s between queuing and consumption, and
  // an already-constructed `Future.error(...)` left unhandled across those
  // turns gets reported by the test zone as an uncaught exception even
  // though the caller does handle it.
  final doctorsResults = <Object>[];
  final sharedNotesResults = <String, Object>{};

  @override
  Future<List<MyDoctorModel>> myDoctors() {
    final next = doctorsResults.removeAt(0);
    if (next is List<MyDoctorModel>) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<List<SharedNoteModel>> sharedNotes(String doctorId) {
    final next = sharedNotesResults[doctorId];
    if (next == null) return Future.value(const []);
    if (next is List<SharedNoteModel>) return Future.value(next);
    return Future.error(next);
  }
}

class _FakeAppointmentsApi extends AppointmentsApi {
  _FakeAppointmentsApi() : super(Dio());

  Future<List<AppointmentModel>>? listResult;

  @override
  Future<List<AppointmentModel>> list() => listResult ?? Future.value(const []);

  @override
  Future<(String? ar, String? en)> getDoctorName(String doctorId) async => (null, null);

  @override
  Future<(String? ar, String? en)> getClinicName(String clinicId) async => (null, null);
}

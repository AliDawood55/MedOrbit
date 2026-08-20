import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/appointments/data/appointments_api.dart';
import 'package:mobile/features/appointments/data/booking_api.dart';
import 'package:mobile/features/appointments/models/appointment_model.dart';
import 'package:mobile/features/appointments/models/availability_slot_model.dart';
import 'package:mobile/features/appointments/providers/appointments_provider.dart';
import 'package:mobile/features/appointments/providers/booking_provider.dart';
import 'package:mobile/features/appointments/screens/book_appointment_screen.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';

const _strings = AppStrings(false); // English, matching the default direction used below

const _doctor = Doctor(id: 'doctor-1', firstNameEn: 'Sara', lastNameEn: 'Ahmad', specialtyEn: 'Cardiology');
const _soleClinic = DoctorClinicSummary(id: 'clinic-1', nameEn: 'Nablus Clinic');
const _clinicA = DoctorClinicSummary(id: 'clinic-a', nameEn: 'Clinic A');
const _clinicB = DoctorClinicSummary(id: 'clinic-b', nameEn: 'Clinic B');

AppointmentModel _appointment() {
  return AppointmentModel.fromJson({
    'id': 'appt-1',
    'appointment_number': 'APT-482913',
    'doctor_id': 'doctor-1',
    'clinic_id': 'clinic-1',
    'scheduled_date': '2026-08-10',
    'start_time': '09:00:00',
    'end_time': '09:30:00',
    'appointment_type': 'in_person',
    'status': 'scheduled',
  });
}

void main() {
  testWidgets('the doctor step opens with the browse list already loaded, not empty', (tester) async {
    final discoveryApi = _FakeDiscoveryApi()..doctorListResults.add(Future.value(const DoctorListResponse(doctors: [_doctor])));
    await tester.pumpWidget(_app(discoveryApi: discoveryApi));
    await tester.pump();

    expect(find.text('Sara Ahmad'), findsOneWidget);
    expect(discoveryApi.doctorListCalls, hasLength(1));
  });

  testWidgets('selecting a doctor with one clinic auto-selects it and Next reaches the slot step', (tester) async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorListResults.add(Future.value(const DoctorListResponse(doctors: [_doctor])))
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])));
    final bookingApi = _FakeBookingApi()..availableSlotsResults.add(Future.value(const []));
    await tester.pumpWidget(_app(discoveryApi: discoveryApi, bookingApi: bookingApi));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('booking-doctor-doctor-1')));
    await tester.pump();
    expect(find.text(_strings.changeDoctorAction), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, _strings.nextAction));
    await tester.pump();

    expect(find.text(_strings.availableSlotsLabel), findsOneWidget);
    expect(bookingApi.availableSlotsCalls.single.clinicId, 'clinic-1');
  });

  testWidgets('a doctor with two clinics shows a clinic choice and switching clinics reloads slots', (tester) async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorListResults.add(Future.value(const DoctorListResponse(doctors: [_doctor])))
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_clinicA, _clinicB])));
    final bookingApi = _FakeBookingApi()
      ..availableSlotsResults.add(Future.value(const []))
      ..availableSlotsResults.add(Future.value(const []));
    await tester.pumpWidget(_app(discoveryApi: discoveryApi, bookingApi: bookingApi));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('booking-doctor-doctor-1')));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.nextAction));
    await tester.pump();

    expect(find.text('Clinic A'), findsOneWidget);
    expect(find.text('Clinic B'), findsOneWidget);
    expect(bookingApi.availableSlotsCalls, isEmpty, reason: 'no clinic is preselected when the doctor has more than one');

    await tester.tap(find.byKey(const ValueKey('booking-clinic-clinic-a')));
    await tester.pump();
    expect(bookingApi.availableSlotsCalls.single.clinicId, 'clinic-a');

    await tester.tap(find.byKey(const ValueKey('booking-clinic-clinic-b')));
    await tester.pump();

    expect(bookingApi.availableSlotsCalls.map((c) => c.clinicId), ['clinic-a', 'clinic-b']);
  });

  testWidgets('full flow: browse, pick a doctor, pick a slot, confirm, and see a success number', (tester) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowKey = 'booking-date-${tomorrow.year}-${tomorrow.month}-${tomorrow.day}';
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorListResults.add(Future.value(const DoctorListResponse(doctors: [_doctor])))
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])));
    final bookingApi = _FakeBookingApi()
      ..availableSlotsResults.add(Future.value(const [])) // today, auto-loaded on entering the slot step
      ..availableSlotsResults.add(Future.value(const [AvailabilityWindow(startTime: '09:00:00', endTime: '09:30:00')])) // tomorrow
      ..createResults.add(_appointment());
    final appointmentsApi = _FakeAppointmentsApi();
    await tester.pumpWidget(_app(discoveryApi: discoveryApi, bookingApi: bookingApi, appointmentsApi: appointmentsApi));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('booking-doctor-doctor-1')));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.nextAction));
    await tester.pump();

    // A future date never filters past slots, so picking tomorrow keeps this
    // deterministic. Tomorrow (index 1 of 21) is well within the default test
    // viewport width, so no scrolling is needed to reach it.
    await tester.tap(find.byKey(ValueKey(tomorrowKey)));
    await tester.pump();

    const slotKey = ValueKey('booking-slot-540|30|0');
    expect(find.byKey(slotKey), findsOneWidget);
    await tester.tap(find.byKey(slotKey));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, _strings.nextAction));
    await tester.pump();

    expect(find.text(_strings.confirmBookingTitle), findsNothing); // title lives on the section header only if present
    expect(find.widgetWithText(ElevatedButton, _strings.confirmAndBookAction), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, _strings.confirmAndBookAction));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.bookingSuccessTitle), findsOneWidget);
    expect(find.text('APT-482913'), findsOneWidget);
    expect(bookingApi.createCalls.single['appointmentType'], 'in_person');
    expect(bookingApi.createCalls.single['startTime'], '09:00:00');
  });

  testWidgets('a deep link with doctorId preselects the doctor and opens directly on the slot step', (tester) async {
    final discoveryApi = _FakeDiscoveryApi()..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])));
    final bookingApi = _FakeBookingApi()..availableSlotsResults.add(Future.value(const []));
    await tester.pumpWidget(_app(discoveryApi: discoveryApi, bookingApi: bookingApi, doctorId: 'doctor-1'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.availableSlotsLabel), findsOneWidget);
    expect(discoveryApi.doctorDetailCalls, ['doctor-1']);
    expect(discoveryApi.doctorListCalls, isEmpty, reason: 'the browse list is never fetched when a doctor is preselected');
  });

  testWidgets('an unknown preselected doctorId shows a not-found message and still offers the browse list', (tester) async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse()))
      ..doctorListResults.add(Future.value(const DoctorListResponse(doctors: [_doctor])));
    await tester.pumpWidget(_app(discoveryApi: discoveryApi, doctorId: 'missing'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.doctorNotFoundMessage), findsOneWidget);
    expect(find.text('Sara Ahmad'), findsOneWidget);
  });

  testWidgets('SLOT_BUSY on submit returns to the slot step with a warning and a refreshed, deselected grid', (tester) async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final tomorrowKey = 'booking-date-${tomorrow.year}-${tomorrow.month}-${tomorrow.day}';
    final discoveryApi = _FakeDiscoveryApi()..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])));
    final bookingApi = _FakeBookingApi()
      ..availableSlotsResults.add(Future.value(const [])) // today, auto-loaded by the doctorId deep link
      ..availableSlotsResults.add(Future.value(const [AvailabilityWindow(startTime: '09:00:00', endTime: '09:30:00')])) // tomorrow — never past-filtered
      ..createResults.add(const ApiException(message: 'Appointment slot already booked', code: 'SLOT_BUSY'))
      ..availableSlotsResults.add(Future.value(const [])); // refreshed after SLOT_BUSY
    await tester.pumpWidget(_app(discoveryApi: discoveryApi, bookingApi: bookingApi, doctorId: 'doctor-1'));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(ValueKey(tomorrowKey)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('booking-slot-540|30|0')));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.nextAction));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, _strings.confirmAndBookAction));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.slotBusyMessage), findsOneWidget);
    expect(find.text(_strings.availableSlotsLabel), findsOneWidget, reason: 'sent back to the slot step');
    expect(find.text(_strings.noSlotsTitle), findsOneWidget, reason: 'the refreshed grid came back empty and the busy slot is gone');
  });

  testWidgets('renders in Arabic RTL and at 2x text scale without throwing', (tester) async {
    final discoveryApi = _FakeDiscoveryApi()..doctorListResults.add(Future.value(const DoctorListResponse(doctors: [_doctor])));
    await tester.pumpWidget(_app(discoveryApi: discoveryApi, isArabic: true, direction: TextDirection.rtl, textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

Widget _app({
  DiscoveryApi? discoveryApi,
  BookingApi? bookingApi,
  AppointmentsApi? appointmentsApi,
  String? doctorId,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      discoveryApiProvider.overrideWithValue(discoveryApi ?? _FakeDiscoveryApi()),
      bookingApiProvider.overrideWithValue(bookingApi ?? _FakeBookingApi()),
      appointmentsApiProvider.overrideWithValue(appointmentsApi ?? _FakeAppointmentsApi()),
      // The real secure storage plugin has no backing implementation under
      // `flutter_test` and would throw MissingPluginException the moment
      // `localeControllerProvider` reads a persisted language on startup.
      secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: isArabic),
      // `BookingDateStrip` formats weekday names via `intl`, which needs its
      // locale symbol data loaded before any non-default `DateFormat` can be
      // constructed. In the real app that happens as a side effect of
      // `GlobalMaterialLocalizations` loading (see main.dart); a bare
      // `MaterialApp` skips that, so it's declared explicitly here too.
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: BookAppointmentScreen(doctorId: doctorId),
        ),
      ),
    ),
  );
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;
}

class _FakeDiscoveryApi extends DiscoveryApi {
  _FakeDiscoveryApi() : super(Dio());

  final doctorListResults = <Future<DoctorListResponse>>[];
  final doctorDetailResults = <Future<DoctorDetailResponse>>[];
  final doctorListCalls = <String?>[];
  final doctorDetailCalls = <String>[];

  @override
  Future<DoctorListResponse> listDoctors({
    String? specialty,
    String? region,
    double? minRating,
    double? minFee,
    double? maxFee,
    String? search,
    int page = 1,
    int limit = 10,
  }) {
    doctorListCalls.add(search);
    return doctorListResults.removeAt(0);
  }

  @override
  Future<DoctorDetailResponse> getDoctor(String id) {
    doctorDetailCalls.add(id);
    return doctorDetailResults.removeAt(0);
  }
}

class _FakeBookingApi extends BookingApi {
  _FakeBookingApi() : super(Dio());

  final availableSlotsResults = <Future<List<AvailabilityWindow>>>[];
  // Holds `AppointmentModel` for success or any other `Object` to throw.
  // Built into a `Future` lazily inside `create()` rather than queued as an
  // already-constructed `Future.error(...)` — a widget test drives several
  // real `pump()`s between queuing and the `await` that consumes it, and an
  // error `Future` left unhandled across those turns gets reported by the
  // test zone as an uncaught exception even though `create()` does handle it.
  final createResults = <Object>[];
  final availableSlotsCalls = <({String doctorId, String clinicId, String date})>[];
  final createCalls = <Map<String, dynamic>>[];

  @override
  Future<List<AvailabilityWindow>> availableSlots({required String doctorId, required String clinicId, required String date}) {
    availableSlotsCalls.add((doctorId: doctorId, clinicId: clinicId, date: date));
    return availableSlotsResults.removeAt(0);
  }

  @override
  Future<AppointmentModel> create({
    required String doctorId,
    required String clinicId,
    required String scheduledDate,
    required String startTime,
    required String endTime,
    required int durationMinutes,
    required String appointmentType,
    String? reasonForVisit,
    String? notes,
  }) {
    createCalls.add({
      'doctorId': doctorId,
      'clinicId': clinicId,
      'scheduledDate': scheduledDate,
      'startTime': startTime,
      'endTime': endTime,
      'durationMinutes': durationMinutes,
      'appointmentType': appointmentType,
      'reasonForVisit': reasonForVisit,
      'notes': notes,
    });
    final next = createResults.removeAt(0);
    if (next is AppointmentModel) return Future.value(next);
    return Future.error(next);
  }
}

class _FakeAppointmentsApi extends AppointmentsApi {
  _FakeAppointmentsApi() : super(Dio());

  @override
  Future<List<AppointmentModel>> list() => Future.value(const []);
}

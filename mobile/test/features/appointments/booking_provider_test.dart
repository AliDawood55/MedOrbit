import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/appointments/data/appointments_api.dart';
import 'package:mobile/features/appointments/data/booking_api.dart';
import 'package:mobile/features/appointments/models/appointment_model.dart';
import 'package:mobile/features/appointments/models/availability_slot_model.dart';
import 'package:mobile/features/appointments/providers/appointments_provider.dart';
import 'package:mobile/features/appointments/providers/booking_provider.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';

const _doctor = Doctor(id: 'doctor-1', firstNameEn: 'Sara', lastNameEn: 'Ahmad');
const _soleClinic = DoctorClinicSummary(id: 'clinic-1', nameEn: 'Nablus Clinic');
const _clinicA = DoctorClinicSummary(id: 'clinic-a', nameEn: 'Clinic A');
const _clinicB = DoctorClinicSummary(id: 'clinic-b', nameEn: 'Clinic B');

AppointmentModel _appointment({String status = 'scheduled'}) {
  return AppointmentModel.fromJson({
    'id': 'appt-1',
    'appointment_number': 'APT-1',
    'doctor_id': 'doctor-1',
    'clinic_id': 'clinic-1',
    'scheduled_date': '2026-08-10',
    'start_time': '09:00:00',
    'end_time': '09:30:00',
    'appointment_type': 'in_person',
    'status': status,
  });
}

void main() {
  test('initial state has no selections and starts on the doctor step', () {
    final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);

    final state = container.read(bookingControllerProvider);

    expect(state.step, BookingWizardStep.doctor);
    expect(state.draft.doctor, isNull);
    expect(state.draft.clinic, isNull);
    expect(state.draft.date, isNull);
    expect(state.draft.slot, isNull);
    expect(state.result, isNull);
  });

  test('selecting a doctor fetches detail, stores clinics, and auto-selects a sole clinic', () async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])));
    final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: discoveryApi);
    addTearDown(container.dispose);

    await container.read(bookingControllerProvider.notifier).selectDoctor(_doctor);

    final state = container.read(bookingControllerProvider);
    expect(state.draft.doctor?.id, 'doctor-1');
    expect(state.draft.clinics, hasLength(1));
    expect(state.draft.clinic?.id, 'clinic-1');
    expect(discoveryApi.doctorDetailCalls, ['doctor-1']);
  });

  test('a doctor with multiple clinics is not auto-selected', () async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_clinicA, _clinicB])));
    final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: discoveryApi);
    addTearDown(container.dispose);

    await container.read(bookingControllerProvider.notifier).selectDoctor(_doctor);

    expect(container.read(bookingControllerProvider).draft.clinic, isNull);
  });

  test('init with a preselected doctorId loads that doctor and jumps straight to the slot step', () async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])));
    final bookingApi = _FakeBookingApi()..availableSlotsResults.add(Future.value(const []));
    final container = _container(bookingApi: bookingApi, discoveryApi: discoveryApi);
    addTearDown(container.dispose);

    await container.read(bookingControllerProvider.notifier).init(doctorId: 'doctor-1');

    final state = container.read(bookingControllerProvider);
    expect(state.step, BookingWizardStep.slot);
    expect(state.draft.doctor?.id, 'doctor-1');
    expect(state.draft.date, isNotNull);
    expect(discoveryApi.doctorDetailCalls, ['doctor-1']);
    expect(bookingApi.availableSlotsCalls, hasLength(1));
  });

  test('init with an unknown doctorId sets a not-found failure and still loads the browse list', () async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse()))
      ..doctorListResults.add(Future.value(const DoctorListResponse()));
    final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: discoveryApi);
    addTearDown(container.dispose);

    await container.read(bookingControllerProvider.notifier).init(doctorId: 'missing-doctor');

    final state = container.read(bookingControllerProvider);
    expect(state.step, BookingWizardStep.doctor);
    expect(state.preselectFailure, PreselectDoctorFailure.notFound);
    expect(discoveryApi.doctorListCalls, hasLength(1));
  });

  test('init with a doctorId that fails to load sets a load-error failure', () async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorDetailResults.add(Future.error(const ApiException(message: 'Network down', code: ApiException.codeServiceUnavailable)))
      ..doctorListResults.add(Future.value(const DoctorListResponse()));
    final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: discoveryApi);
    addTearDown(container.dispose);

    await container.read(bookingControllerProvider.notifier).init(doctorId: 'doctor-1');

    expect(container.read(bookingControllerProvider).preselectFailure, PreselectDoctorFailure.loadError);
  });

  test('selecting a clinic clears any selected slot and reloads slots', () async {
    final bookingApi = _FakeBookingApi()
      ..availableSlotsResults.add(Future.value(const [AvailabilityWindow(startTime: '09:00:00', endTime: '09:30:00')]))
      ..availableSlotsResults.add(Future.value(const []));
    final container = _container(bookingApi: bookingApi, discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);
    final notifier = container.read(bookingControllerProvider.notifier)
      ..testSeedDraftForClinicAndDate(doctor: _doctor, clinics: const [_clinicA, _clinicB], clinic: _clinicA, date: DateTime(2026, 8, 10));
    await notifier.loadSlots();
    notifier.selectSlot(container.read(bookingControllerProvider).slots.single);
    expect(container.read(bookingControllerProvider).draft.slot, isNotNull);

    notifier.selectClinic(_clinicB);
    // selectClinic itself only clears + kicks off a reload; wait for it.
    await Future<void>.delayed(Duration.zero);

    final state = container.read(bookingControllerProvider);
    expect(state.draft.clinic?.id, 'clinic-b');
    expect(state.draft.slot, isNull);
    expect(bookingApi.availableSlotsCalls.map((c) => c.clinicId), ['clinic-a', 'clinic-b']);
  });

  test('changing the date clears the selected slot and reloads slots', () async {
    final bookingApi = _FakeBookingApi()
      ..availableSlotsResults.add(Future.value(const [AvailabilityWindow(startTime: '09:00:00', endTime: '09:30:00')]))
      ..availableSlotsResults.add(Future.value(const []));
    final container = _container(bookingApi: bookingApi, discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);
    final notifier = container.read(bookingControllerProvider.notifier)
      ..testSeedDraftForClinicAndDate(doctor: _doctor, clinics: const [_soleClinic], clinic: _soleClinic, date: DateTime(2026, 8, 10));
    await notifier.loadSlots();
    notifier.selectSlot(container.read(bookingControllerProvider).slots.single);
    expect(container.read(bookingControllerProvider).draft.slot, isNotNull);

    notifier.selectDate(DateTime(2026, 8, 11));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(bookingControllerProvider).draft.slot, isNull);
    expect(bookingApi.availableSlotsCalls.map((c) => c.date), ['2026-08-10', '2026-08-11']);
  });

  test('selecting a slot stores it on the draft', () async {
    final bookingApi = _FakeBookingApi()..availableSlotsResults.add(Future.value(const [AvailabilityWindow(startTime: '09:00:00', endTime: '09:30:00')]));
    final container = _container(bookingApi: bookingApi, discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);
    final notifier = container.read(bookingControllerProvider.notifier)
      ..testSeedDraftForClinicAndDate(doctor: _doctor, clinics: const [_soleClinic], clinic: _soleClinic, date: DateTime(2026, 8, 10));
    await notifier.loadSlots();

    final slot = container.read(bookingControllerProvider).slots.single;
    notifier.selectSlot(slot);

    expect(container.read(bookingControllerProvider).draft.slot?.id, slot.id);
  });

  test('submit is rejected when required selections are missing', () async {
    final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);

    final ok = await container.read(bookingControllerProvider.notifier).submit();

    expect(ok, isFalse);
    expect(container.read(bookingControllerProvider).submitError?.kind, BookingSubmitErrorKind.validation);
  });

  test('a successful booking stores the result and refreshes an already-open appointments list', () async {
    final bookingApi = _FakeBookingApi()..createResults.add(Future.value(_appointment()));
    final appointmentsApi = _FakeAppointmentsApi();
    final container = _container(bookingApi: bookingApi, discoveryApi: _FakeDiscoveryApi(), appointmentsApi: appointmentsApi);
    addTearDown(container.dispose);
    // Simulates the appointments screen already being mounted beneath this
    // one (e.g. the patient had it open before pushing the booking route) —
    // that's what keeps the autoDispose controller alive to be refreshed.
    final subscription = container.listen(appointmentsControllerProvider, (previous, next) {});
    addTearDown(subscription.close);
    await Future<void>.delayed(Duration.zero); // let the controller's constructor-time load() settle
    final initialListCalls = appointmentsApi.listCallCount;
    final notifier = container.read(bookingControllerProvider.notifier)
      ..testSeedFullSelection(
        doctor: _doctor,
        clinic: _soleClinic,
        date: DateTime(2026, 8, 10),
        slot: const GeneratedSlot(id: '540|30|0', startMinutes: 540, startTime: '09:00:00', endTime: '09:30:00', startDisplay: '09:00', endDisplay: '09:30', durationMinutes: 30, isTelemedicine: false),
      );

    final ok = await notifier.submit();
    await Future<void>.delayed(Duration.zero); // let the invalidated appointments controller's reload settle

    expect(ok, isTrue);
    final state = container.read(bookingControllerProvider);
    expect(state.result?.appointmentNumber, 'APT-1');
    expect(state.draft.doctor, isNull, reason: 'draft is cleared after a successful booking');
    expect(bookingApi.createCalls.single['appointmentType'], 'in_person');
    expect(appointmentsApi.listCallCount, greaterThan(initialListCalls));
  });

  test('a second concurrent submit is ignored while the first is in flight', () async {
    final completer = Completer<AppointmentModel>();
    final bookingApi = _FakeBookingApi()..createResults.add(completer.future);
    final container = _container(bookingApi: bookingApi, discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);
    final notifier = container.read(bookingControllerProvider.notifier)
      ..testSeedFullSelection(
        doctor: _doctor,
        clinic: _soleClinic,
        date: DateTime(2026, 8, 10),
        slot: const GeneratedSlot(id: '540|30|0', startMinutes: 540, startTime: '09:00:00', endTime: '09:30:00', startDisplay: '09:00', endDisplay: '09:30', durationMinutes: 30, isTelemedicine: false),
      );

    final first = notifier.submit();
    final second = await notifier.submit();

    expect(second, isFalse);
    completer.complete(_appointment());
    await first;
    expect(bookingApi.createCalls, hasLength(1));
  });

  test('SLOT_BUSY sends the patient back to the slot step, clears the slot, and refreshes availability', () async {
    final bookingApi = _FakeBookingApi()
      ..createResults.add(Future.error(const ApiException(message: 'Appointment slot already booked', code: 'SLOT_BUSY')))
      ..availableSlotsResults.add(Future.value(const []));
    final container = _container(bookingApi: bookingApi, discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);
    final notifier = container.read(bookingControllerProvider.notifier)
      ..testSeedFullSelection(
        doctor: _doctor,
        clinic: _soleClinic,
        date: DateTime(2026, 8, 10),
        slot: const GeneratedSlot(id: '540|30|0', startMinutes: 540, startTime: '09:00:00', endTime: '09:30:00', startDisplay: '09:00', endDisplay: '09:30', durationMinutes: 30, isTelemedicine: false),
      );
    notifier.goToConfirm();

    final ok = await notifier.submit();
    await Future<void>.delayed(Duration.zero);

    expect(ok, isFalse);
    final state = container.read(bookingControllerProvider);
    expect(state.step, BookingWizardStep.slot);
    expect(state.draft.slot, isNull);
    expect(state.draft.clinic?.id, 'clinic-1', reason: 'clinic/date must survive a SLOT_BUSY recovery');
    expect(state.draft.date, isNotNull);
    expect(state.submitError?.kind, BookingSubmitErrorKind.slotBusy);
    expect(bookingApi.availableSlotsCalls, hasLength(1), reason: 'slots are refreshed after SLOT_BUSY');
  });

  test('changeDoctor (used as the cancel/reset path) discards the whole draft', () async {
    final discoveryApi = _FakeDiscoveryApi()
      ..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])))
      ..doctorListResults.add(Future.value(const DoctorListResponse()));
    final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: discoveryApi);
    addTearDown(container.dispose);
    final notifier = container.read(bookingControllerProvider.notifier);
    await notifier.selectDoctor(_doctor);
    expect(container.read(bookingControllerProvider).draft.doctor, isNotNull);

    await notifier.changeDoctor();

    final state = container.read(bookingControllerProvider);
    expect(state.draft.doctor, isNull);
    expect(state.draft.clinic, isNull);
    expect(state.step, BookingWizardStep.doctor);
  });

  test(
    'discardDraft resets to a clean slate — the mechanism a logout/session-expiry redirect relies on '
    '(the route is protected, so a session clear pops it and disposes this autoDispose provider)',
    () async {
      final discoveryApi = _FakeDiscoveryApi()..doctorDetailResults.add(Future.value(const DoctorDetailResponse(doctor: _doctor, clinics: [_soleClinic])));
      final container = _container(bookingApi: _FakeBookingApi(), discoveryApi: discoveryApi);
      addTearDown(container.dispose);
      final notifier = container.read(bookingControllerProvider.notifier);
      await notifier.selectDoctor(_doctor);

      notifier.discardDraft();

      final state = container.read(bookingControllerProvider);
      expect(state.draft.doctor, isNull);
      expect(state.step, BookingWizardStep.doctor);
    },
  );

  test('reason and notes are never printed', () async {
    final bookingApi = _FakeBookingApi()..createResults.add(Future.value(_appointment()));
    final container = _container(bookingApi: bookingApi, discoveryApi: _FakeDiscoveryApi());
    addTearDown(container.dispose);
    final notifier = container.read(bookingControllerProvider.notifier)
      ..testSeedFullSelection(
        doctor: _doctor,
        clinic: _soleClinic,
        date: DateTime(2026, 8, 10),
        slot: const GeneratedSlot(id: '540|30|0', startMinutes: 540, startTime: '09:00:00', endTime: '09:30:00', startDisplay: '09:00', endDisplay: '09:30', durationMinutes: 30, isTelemedicine: false),
      );
    notifier.setReason('Persistent private symptom detail');
    notifier.setNotes('Private additional note');
    final printed = <String>[];

    await runZoned(
      notifier.submit,
      zoneSpecification: ZoneSpecification(print: (_, _, _, line) => printed.add(line)),
    );

    expect(printed, isEmpty);
  });
}

ProviderContainer _container({
  required BookingApi bookingApi,
  required DiscoveryApi discoveryApi,
  AppointmentsApi? appointmentsApi,
}) {
  final container = ProviderContainer(
    overrides: [
      bookingApiProvider.overrideWithValue(bookingApi),
      discoveryApiProvider.overrideWithValue(discoveryApi),
      appointmentsApiProvider.overrideWithValue(appointmentsApi ?? _FakeAppointmentsApi()),
    ],
  );
  // `bookingControllerProvider` is `autoDispose` so its draft clears when the
  // screen is left. In the real app `BookAppointmentScreen` holds it alive
  // via `ref.watch` for as long as it's mounted; `container.read()` alone
  // does not — Riverpod schedules disposal the moment nothing is watching,
  // which fires between awaited statements here. Mirror the screen's watch
  // with a real listener so state persists across `await`s the same way it
  // does in production.
  container.listen(bookingControllerProvider, (previous, next) {});
  return container;
}

/// Test-only seams so tests can put the controller directly into a mid-wizard
/// state without re-driving every prior step through the network.
extension _BookingControllerTestSeed on BookingController {
  void testSeedDraftForClinicAndDate({
    required Doctor doctor,
    required List<DoctorClinicSummary> clinics,
    required DoctorClinicSummary clinic,
    required DateTime date,
  }) {
    state = state.copyWith(
      draft: state.draft.copyWith(doctor: doctor, clinics: clinics, clinic: clinic, date: date),
    );
  }

  void testSeedFullSelection({
    required Doctor doctor,
    required DoctorClinicSummary clinic,
    required DateTime date,
    required GeneratedSlot slot,
  }) {
    state = state.copyWith(
      draft: state.draft.copyWith(doctor: doctor, clinics: [clinic], clinic: clinic, date: date, slot: slot),
    );
  }
}

class _FakeBookingApi extends BookingApi {
  _FakeBookingApi() : super(Dio());

  final availableSlotsResults = <Future<List<AvailabilityWindow>>>[];
  final createResults = <Future<AppointmentModel>>[];
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
    return createResults.removeAt(0);
  }
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

class _FakeAppointmentsApi extends AppointmentsApi {
  _FakeAppointmentsApi() : super(Dio());

  int listCallCount = 0;

  @override
  Future<List<AppointmentModel>> list() {
    listCallCount++;
    return Future.value(const []);
  }
}

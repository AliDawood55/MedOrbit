import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/appointments/data/appointments_api.dart';
import 'package:mobile/features/appointments/models/appointment_model.dart';
import 'package:mobile/features/appointments/providers/appointments_provider.dart';
import 'package:mobile/features/care/data/care_api.dart';
import 'package:mobile/features/care/models/my_doctor_model.dart';
import 'package:mobile/features/care/models/shared_note_model.dart';
import 'package:mobile/features/care/providers/care_provider.dart';

AppointmentModel _appointment({
  required String id,
  required String doctorId,
  String status = 'scheduled',
  String scheduledDate = '2099-01-01',
}) {
  return AppointmentModel.fromJson({
    'id': id,
    'appointment_number': 'APT-$id',
    'doctor_id': doctorId,
    'scheduled_date': scheduledDate,
    'start_time': '09:00:00',
    'end_time': '09:30:00',
    'status': status,
  });
}

void main() {
  group('myDoctorsProvider', () {
    test('exposes the doctors returned by the api', () async {
      final api = _FakeCareApi()
        ..doctorsResults.add([MyDoctorModel.fromJson({'id': 'doctor-1'})]);
      final container = _container(careApi: api);
      addTearDown(container.dispose);

      final doctors = await container.read(myDoctorsProvider.future);

      expect(doctors, hasLength(1));
      expect(doctors.single.id, 'doctor-1');
    });

    test('no doctors is a legitimate empty list, not an error', () async {
      final api = _FakeCareApi()..doctorsResults.add(const <MyDoctorModel>[]);
      final container = _container(careApi: api);
      addTearDown(container.dispose);

      final doctors = await container.read(myDoctorsProvider.future);

      expect(doctors, isEmpty);
    });

    test('a failed fetch surfaces as a provider error', () async {
      final api = _FakeCareApi()..doctorsResults.add(Exception('network down'));
      final container = _container(careApi: api);
      addTearDown(container.dispose);

      await expectLater(container.read(myDoctorsProvider.future), throwsException);
    });
  });

  group('sharedNotesProvider', () {
    test('merges notes across every treating doctor, newest first', () async {
      final api = _FakeCareApi()
        ..doctorsResults.add([
          MyDoctorModel.fromJson({'id': 'doctor-1', 'first_name_en': 'A'}),
          MyDoctorModel.fromJson({'id': 'doctor-2', 'first_name_en': 'B'}),
        ])
        ..sharedNotesResults['doctor-1'] = [
          SharedNoteModel.fromJson({'id': 'note-1', 'created_at': '2026-01-01T00:00:00.000Z'}),
        ]
        ..sharedNotesResults['doctor-2'] = [
          SharedNoteModel.fromJson({'id': 'note-2', 'created_at': '2026-06-01T00:00:00.000Z'}),
        ];
      final container = _container(careApi: api);
      addTearDown(container.dispose);

      final notes = await container.read(sharedNotesProvider.future);

      expect(notes.map((e) => e.note.id), ['note-2', 'note-1']);
    });

    test('no doctors means nothing to fetch, and a legitimate empty list', () async {
      final api = _FakeCareApi()..doctorsResults.add(const <MyDoctorModel>[]);
      final container = _container(careApi: api);
      addTearDown(container.dispose);

      final notes = await container.read(sharedNotesProvider.future);

      expect(notes, isEmpty);
    });

    test('a doctor with legitimately zero shared notes contributes nothing, not an error', () async {
      final api = _FakeCareApi()
        ..doctorsResults.add([MyDoctorModel.fromJson({'id': 'doctor-1'})])
        ..sharedNotesResults['doctor-1'] = const <SharedNoteModel>[];
      final container = _container(careApi: api);
      addTearDown(container.dispose);

      final notes = await container.read(sharedNotesProvider.future);

      expect(notes, isEmpty);
    });

    test('one doctor\'s failed fetch fails the whole provider rather than reading as empty', () async {
      final api = _FakeCareApi()
        ..doctorsResults.add([MyDoctorModel.fromJson({'id': 'doctor-1'})])
        ..sharedNotesResults['doctor-1'] = Exception('network down');
      final container = _container(careApi: api);
      addTearDown(container.dispose);

      await expectLater(container.read(sharedNotesProvider.future), throwsException);
    });
  });

  group('upcomingWithMyDoctorsProvider', () {
    test('filters the existing appointments list to active treating doctors', () async {
      final careApi = _FakeCareApi()
        ..doctorsResults.add([MyDoctorModel.fromJson({'id': 'doctor-1'})]);
      final appointmentsApi = _FakeAppointmentsApi()
        ..listResult = Future.value([
          _appointment(id: '1', doctorId: 'doctor-1'),
          _appointment(id: '2', doctorId: 'doctor-other'),
        ]);
      final container = _container(careApi: careApi, appointmentsApi: appointmentsApi);
      addTearDown(container.dispose);
      container.listen(appointmentsControllerProvider, (previous, next) {});

      await container.read(appointmentsControllerProvider.notifier).load();
      await container.read(myDoctorsProvider.future);

      final result = container.read(upcomingWithMyDoctorsProvider);
      expect(result.value?.map((e) => e.appointment.id), ['1']);
    });

    test('excludes cancelled, completed, and no_show appointments', () async {
      final careApi = _FakeCareApi()
        ..doctorsResults.add([MyDoctorModel.fromJson({'id': 'doctor-1'})]);
      final appointmentsApi = _FakeAppointmentsApi()
        ..listResult = Future.value([
          _appointment(id: '1', doctorId: 'doctor-1', status: 'scheduled'),
          _appointment(id: '2', doctorId: 'doctor-1', status: 'cancelled'),
          _appointment(id: '3', doctorId: 'doctor-1', status: 'completed'),
          _appointment(id: '4', doctorId: 'doctor-1', status: 'no_show'),
        ]);
      final container = _container(careApi: careApi, appointmentsApi: appointmentsApi);
      addTearDown(container.dispose);
      container.listen(appointmentsControllerProvider, (previous, next) {});

      await container.read(appointmentsControllerProvider.notifier).load();
      await container.read(myDoctorsProvider.future);

      final result = container.read(upcomingWithMyDoctorsProvider);
      expect(result.value?.map((e) => e.appointment.id), ['1']);
    });

    test('a past-dated appointment with an active doctor is excluded', () async {
      final careApi = _FakeCareApi()
        ..doctorsResults.add([MyDoctorModel.fromJson({'id': 'doctor-1'})]);
      final appointmentsApi = _FakeAppointmentsApi()
        ..listResult = Future.value([
          _appointment(id: '1', doctorId: 'doctor-1', scheduledDate: '2000-01-01'),
        ]);
      final container = _container(careApi: careApi, appointmentsApi: appointmentsApi);
      addTearDown(container.dispose);
      container.listen(appointmentsControllerProvider, (previous, next) {});

      await container.read(appointmentsControllerProvider.notifier).load();
      await container.read(myDoctorsProvider.future);

      final result = container.read(upcomingWithMyDoctorsProvider);
      expect(result.value, isEmpty);
    });
  });
}

ProviderContainer _container({required CareApi careApi, AppointmentsApi? appointmentsApi}) {
  return ProviderContainer(
    overrides: [
      careApiProvider.overrideWithValue(careApi),
      appointmentsApiProvider.overrideWithValue(appointmentsApi ?? _FakeAppointmentsApi()),
    ],
  );
}

class _FakeCareApi extends CareApi {
  _FakeCareApi() : super(Dio());

  // Holds a `List<...>` for success or any other `Object` to throw. Built
  // into a `Future` lazily inside `myDoctors()`/`sharedNotes()` rather than
  // queued as an already-constructed `Future.error(...)` — this provider
  // chain awaits `myDoctorsProvider.future` before consuming a queued shared
  // notes result, and an error `Future` left unhandled across that await
  // gets reported by the test zone as an uncaught exception even though the
  // caller does handle it (see `book_appointment_screen_test.dart`'s
  // `_FakeBookingApi` for the same pattern).
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

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/appointments/data/appointments_api.dart';
import 'package:mobile/features/appointments/models/appointment_model.dart';
import 'package:mobile/features/appointments/providers/appointments_provider.dart';

AppointmentModel _appointment({
  required String id,
  String status = 'scheduled',
  String? reasonForVisit,
}) {
  return AppointmentModel.fromJson({
    'id': id,
    'appointment_number': 'APT-$id',
    'doctor_id': 'doctor-1',
    'scheduled_date': '2099-01-01',
    'start_time': '09:00:00',
    'end_time': '09:30:00',
    'status': status,
    'reason_for_visit': reasonForVisit,
  });
}

void main() {
  group('AppointmentsController.cancel', () {
    test('a successful cancel replaces only the target appointment with the server response', () async {
      final api = _FakeAppointmentsApi()
        ..listResults.add(Future.value([
          _appointment(id: 'appt-1', status: 'scheduled'),
          _appointment(id: 'appt-2', status: 'confirmed'),
        ]))
        ..cancelResults.add(
          _appointment(id: 'appt-1', status: 'cancelled', reasonForVisit: 'server-preserved reason'),
        );
      final container = _container(api: api);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero); // let the constructor's initial load() settle

      final ok = await container.read(appointmentsControllerProvider.notifier).cancel('appt-1', reason: 'Feeling better');

      expect(ok, isTrue);
      final list = container.read(appointmentsControllerProvider).value!;
      final cancelled = list.firstWhere((e) => e.appointment.id == 'appt-1');
      final untouched = list.firstWhere((e) => e.appointment.id == 'appt-2');
      expect(cancelled.appointment.status, 'cancelled');
      expect(cancelled.appointment.reasonForVisit, 'server-preserved reason', reason: 'must reflect the server response, not a fabricated local status flip');
      expect(untouched.appointment.status, 'confirmed');
      expect(api.cancelCalls.single, (id: 'appt-1', reason: 'Feeling better'));
    });

    test('a non-404 failure leaves the local list unchanged, returns false, and does not reload', () async {
      final api = _FakeAppointmentsApi()
        ..listResults.add(Future.value([_appointment(id: 'appt-1', status: 'scheduled')]))
        ..cancelResults.add(
          const ApiException(message: 'Server error', code: ApiException.codeHttpError, statusCode: 500),
        );
      final container = _container(api: api);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero); // let the constructor's initial load() settle
      final callsBeforeCancel = api.listCallCount;

      final ok = await container.read(appointmentsControllerProvider.notifier).cancel('appt-1');

      expect(ok, isFalse);
      expect(container.read(appointmentsControllerProvider).value!.single.appointment.status, 'scheduled');
      expect(api.listCallCount, callsBeforeCancel, reason: 'only a stale (404) failure should trigger a reload');
    });

    test('a 404 failure (stale/already-actioned appointment) reloads the list to converge on server truth', () async {
      final api = _FakeAppointmentsApi()
        ..listResults.add(Future.value([_appointment(id: 'appt-1', status: 'scheduled')]))
        ..cancelResults.add(
          const ApiException(message: 'Appointment not found', code: 'NOT_FOUND', statusCode: 404),
        )
        ..listResults.add(Future.value([_appointment(id: 'appt-1', status: 'cancelled')]));
      final container = _container(api: api);
      addTearDown(container.dispose);
      await Future<void>.delayed(Duration.zero); // let the constructor's initial load() settle

      final ok = await container.read(appointmentsControllerProvider.notifier).cancel('appt-1');

      expect(ok, isFalse);
      expect(api.listCallCount, 2);
      expect(container.read(appointmentsControllerProvider).value!.single.appointment.status, 'cancelled');
    });
  });
}

ProviderContainer _container({required AppointmentsApi api}) {
  final container = ProviderContainer(
    overrides: [appointmentsApiProvider.overrideWithValue(api)],
  );
  container.listen(appointmentsControllerProvider, (previous, next) {});
  return container;
}

class _FakeAppointmentsApi extends AppointmentsApi {
  _FakeAppointmentsApi() : super(Dio());

  final listResults = <Future<List<AppointmentModel>>>[];
  int listCallCount = 0;
  // Holds an `AppointmentModel` for success or any other `Object` to throw,
  // built into a `Future` lazily inside `cancel()` — an already-constructed
  // `Future.error(...)` left unhandled across the awaits in these tests gets
  // reported by the test zone as an uncaught exception even though the
  // caller does handle it (see `care_provider_test.dart`'s `_FakeCareApi`
  // for the same pattern).
  final cancelResults = <Object>[];
  final cancelCalls = <({String id, String? reason})>[];

  @override
  Future<List<AppointmentModel>> list() {
    listCallCount++;
    return listResults.removeAt(0);
  }

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

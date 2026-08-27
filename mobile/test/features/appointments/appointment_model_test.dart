import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/appointments/models/appointment_model.dart';

Map<String, dynamic> _validJson() => {
  'id': 'appt-1',
  'appointment_number': 'APT-1',
  'doctor_id': 'doctor-1',
  'clinic_id': 'clinic-1',
  'scheduled_date': '2026-08-10',
  'start_time': '09:00:00',
  'end_time': '09:30:00',
  'appointment_type': 'in_person',
  'status': 'scheduled',
  'reason_for_visit': 'Checkup',
};

void main() {
  group('AppointmentModel.fromJson', () {
    test('maps a normal payload exactly', () {
      final appointment = AppointmentModel.fromJson(_validJson());

      expect(appointment.id, 'appt-1');
      expect(appointment.appointmentNumber, 'APT-1');
      expect(appointment.doctorId, 'doctor-1');
      expect(appointment.clinicId, 'clinic-1');
      expect(appointment.scheduledDate, '2026-08-10');
      expect(appointment.status, 'scheduled');
    });

    test('tolerates a null clinic_id and reason_for_visit', () {
      final json = _validJson()
        ..['clinic_id'] = null
        ..['reason_for_visit'] = null;

      final appointment = AppointmentModel.fromJson(json);

      expect(appointment.clinicId, isNull);
      expect(appointment.reasonForVisit, isNull);
    });

    // id/doctor_id/clinic_id are UUID columns (`db/02_dependent_tables.sql`'s
    // `appointments` table) — never numeric in a well-formed response, so a
    // number must fail rather than being silently coerced into a string.
    test('throws FormatException for a numeric id instead of coercing it to a string', () {
      final json = _validJson()..['id'] = 42;

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a numeric doctor_id instead of coercing it to a string', () {
      final json = _validJson()..['doctor_id'] = 7;

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('defaults a missing appointment_type to in_person', () {
      final json = _validJson()..remove('appointment_type');

      expect(AppointmentModel.fromJson(json).appointmentType, 'in_person');
    });

    test('throws FormatException for a missing appointment_number', () {
      final json = _validJson()..remove('appointment_number');

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a null doctor_id', () {
      final json = _validJson()..['doctor_id'] = null;

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when scheduled_date is a structured Map', () {
      final json = _validJson()..['scheduled_date'] = {'year': 2026};

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when scheduled_date is a boolean instead of coercing it to a string', () {
      final json = _validJson()..['scheduled_date'] = true;

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when start_time is numeric instead of coercing it to a string', () {
      final json = _validJson()..['start_time'] = 900;

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing start_time', () {
      final json = _validJson()..remove('start_time');

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for a missing status', () {
      final json = _validJson()..remove('status');

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when status is a boolean instead of coercing it to a string', () {
      final json = _validJson()..['status'] = false;

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });

    test('throws FormatException when status is a structured value', () {
      final json = _validJson()..['status'] = ['scheduled'];

      expect(() => AppointmentModel.fromJson(json), throwsA(isA<FormatException>()));
    });
  });
}

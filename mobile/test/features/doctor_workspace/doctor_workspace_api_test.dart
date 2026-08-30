import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/doctor_workspace/data/doctor_workspace_api.dart';

void main() {
  group('DoctorWorkspaceApi profile and schedule', () {
    test('uses JWT-scoped profile and schedule paths', () async {
      final fake = _RecordingDio([_ok(_profile()), _ok(_schedule())]);
      final api = DoctorWorkspaceApi(fake.dio);
      final profile = await api.getProfile();
      final schedule = await api.getSchedule();
      expect(profile.id, '11111111-1111-4111-8111-111111111111');
      expect(schedule.bookingHorizonDays, 90);
      expect(fake.paths, ['/doctors/me/profile', '/doctors/me/schedule']);
    });

    test(
      'profile update sends editable fields and no credential authority',
      () async {
        final fake = _RecordingDio([_ok(_profile())]);
        await DoctorWorkspaceApi(fake.dio).updateProfile(
          headline: '  Cardiologist  ',
          bio: '  Bio  ',
          subSpecialty: 'Heart',
          yearsOfExperience: 12,
          expertise: const ['ECG'],
          interests: const ['Prevention'],
          education: const ['MD'],
          certifications: const ['Board'],
          languages: const ['Arabic'],
          city: ' Cairo ',
          consultationFee: 500,
          consultationDuration: 30,
          isAcceptingPatients: true,
        );
        final data = fake.requests.single.data as Map<String, dynamic>;
        expect(data['professionalHeadline'], 'Cardiologist');
        expect(data['bio'], 'Bio');
        expect(data, isNot(contains('doctor_id')));
        expect(data, isNot(contains('user_id')));
        expect(data, isNot(contains('medical_license_number')));
        expect(data, isNot(contains('approval_status')));
        expect(data, isNot(contains('role')));
      },
    );

    test('availability create and update never send doctor id', () async {
      final fake = _RecordingDio([_ok(_availability()), _ok(_availability())]);
      final api = DoctorWorkspaceApi(fake.dio);
      final payload = {
        'day_of_week': 1,
        'start_time': '09:00',
        'end_time': '12:00',
        'slot_duration': 30,
        'is_telemedicine': true,
        'availability_type': 'available',
      };
      await api.createAvailability(payload);
      await api.updateAvailability('slot-1', {'is_active': false});
      expect(fake.requests[0].method, 'POST');
      expect(fake.requests[0].path, '/doctors/me/availability');
      expect(fake.requests[1].method, 'PUT');
      expect(fake.requests[1].path, '/doctors/me/availability/slot-1');
      expect(fake.requests[0].data, isNot(contains('doctor_id')));
    });

    test('delete availability targets only route slot id', () async {
      final fake = _RecordingDio([_ok(null)]);
      await DoctorWorkspaceApi(fake.dio).deleteAvailability('slot-1');
      expect(fake.requests.single.method, 'DELETE');
      expect(fake.requests.single.path, '/doctors/me/availability/slot-1');
    });

    test(
      'appointment lifecycle uses empty body except trimmed cancel reason',
      () async {
        final fake = _RecordingDio([
          _ok(_appointment(status: 'confirmed')),
          _ok(_appointment(status: 'completed')),
          _ok(_appointment(status: 'cancelled')),
        ]);
        final api = DoctorWorkspaceApi(fake.dio);
        await api.confirmAppointment('appt-1');
        await api.completeAppointment('appt-1');
        await api.cancelAppointment('appt-1', reason: '  unavailable  ');
        expect(fake.paths, [
          '/appointments/appt-1/confirm',
          '/appointments/appt-1/complete',
          '/appointments/appt-1/cancel',
        ]);
        expect(fake.requests[0].data, isEmpty);
        expect(fake.requests[1].data, isEmpty);
        expect(fake.requests[2].data, {'reason': 'unavailable'});
      },
    );
  });

  group('DoctorWorkspaceApi patient isolation', () {
    test('patient search is server-side and JWT-scoped', () async {
      final fake = _RecordingDio([
        _ok([_patient()]),
      ]);
      final values = await DoctorWorkspaceApi(
        fake.dio,
      ).getPatients(search: '  Noor  ');
      expect(values.single.email, 'patient@example.test');
      expect(fake.requests.single.path, '/doctors/me/patients');
      expect(fake.requests.single.queryParameters, {'search': 'Noor'});
    });

    test('patient detail uses URL patient id only', () async {
      final fake = _RecordingDio([
        _ok({
          'patient': _patient(),
          'appointments': [_appointment()],
          'notes': [_record()],
          'prescriptions': [_prescription()],
        }),
      ]);
      final detail = await DoctorWorkspaceApi(fake.dio).getPatient('patient-1');
      expect(detail.notes.single.diagnosis, 'Migraine');
      expect(fake.paths.single, '/doctors/me/patients/patient-1');
      expect(fake.requests.single.data, isNull);
    });

    test(
      'session note exact body omits patient and doctor authority',
      () async {
        final fake = _RecordingDio([_ok(_record())]);
        await DoctorWorkspaceApi(fake.dio).createSessionNote(
          'patient-1',
          recordType: 'consultation',
          chiefComplaint: ' Headache ',
          diagnosis: ' Migraine ',
          clinicalNotes: ' Rest ',
          isDraft: false,
          visibleToPatient: true,
        );
        final body = fake.requests.single.data as Map<String, dynamic>;
        expect(fake.paths.single, '/doctors/me/patients/patient-1/notes');
        expect(body, {
          'record_type': 'consultation',
          'chief_complaint': 'Headache',
          'diagnosis': 'Migraine',
          'clinical_notes': 'Rest',
          'is_draft': false,
          'visible_to_patient': true,
        });
        expect(body, isNot(contains('patient_id')));
        expect(body, isNot(contains('doctor_id')));
      },
    );

    test('relationship end sends only reason', () async {
      final fake = _RecordingDio([
        _ok({'id': 'rel-1', 'status': 'ended'}),
      ]);
      await DoctorWorkspaceApi(
        fake.dio,
      ).endRelationship('patient-1', '  transferred  ');
      expect(fake.requests.single.data, {'reason': 'transferred'});
    });
  });

  group('DoctorWorkspaceApi content and clinical records', () {
    test('post create and edit use canonical title', () async {
      final fake = _RecordingDio([_ok(_post()), _ok(_post())]);
      final api = DoctorWorkspaceApi(fake.dio);
      await api.savePost(
        title: '  Prevention ',
        category: 'health_tip',
        body: ' Body ',
        publish: true,
      );
      await api.savePost(
        id: 'post-1',
        title: 'Edit',
        category: 'article',
        body: 'Long',
        publish: false,
      );
      expect(fake.requests.first.data, {
        'title': 'Prevention',
        'category': 'health_tip',
        'body': 'Body',
        'isPublished': true,
      });
      expect(fake.paths, ['/doctors/me/posts', '/doctors/me/posts/post-1']);
    });

    test('record create derives doctor and patient from appointment', () async {
      final fake = _RecordingDio([_ok(_record())]);
      await DoctorWorkspaceApi(fake.dio).createRecord(
        appointmentId: 'appt-1',
        recordType: 'consultation',
        chiefComplaint: 'Pain',
        diagnosis: 'Dx',
        treatmentPlan: 'Plan',
        clinicalNotes: 'Clinical',
        doctorNotes: 'Private',
        isDraft: true,
      );
      final body = fake.requests.single.data as Map<String, dynamic>;
      expect(body['appointment_id'], 'appt-1');
      expect(body, isNot(contains('patient_id')));
      expect(body, isNot(contains('doctor_id')));
      expect(body, isNot(contains('visible_to_patient')));
    });

    test('record update sends only backend-supported mutable fields', () async {
      final fake = _RecordingDio([_ok(_record())]);
      await DoctorWorkspaceApi(fake.dio).updateRecord(
        'record-1',
        diagnosis: 'Dx',
        treatmentPlan: 'Plan',
        clinicalNotes: 'Clinical',
        doctorNotes: 'Private',
        isDraft: false,
      );
      final body = fake.requests.single.data as Map<String, dynamic>;
      expect(
        body.keys,
        unorderedEquals([
          'diagnosis',
          'treatment_plan',
          'clinical_notes',
          'doctor_notes',
          'is_draft',
        ]),
      );
    });

    test(
      'prescription sends explicitly required patient and appointment ids but no doctor id',
      () async {
        final fake = _RecordingDio([
          _ok({
            ..._prescription(),
            'safety_check': {'status': 'warning'},
          }),
        ]);
        final result = await DoctorWorkspaceApi(fake.dio).createPrescription(
          patientId: 'patient-1',
          appointmentId: 'appt-1',
          diagnosis: 'Dx',
          instructions: 'After food',
          doctorNotes: 'Private',
          items: const [
            {
              'medication_name_ar': 'دواء',
              'medication_name_en': 'Medicine',
              'dosage': '5 mg',
              'frequency': 'daily',
              'duration': '5 days',
              'quantity': 5,
              'instructions': '',
            },
          ],
        );
        final body = fake.requests.single.data as Map<String, dynamic>;
        expect(result.safetyStatus, 'warning');
        expect(body['patient_id'], 'patient-1');
        expect(body['appointment_id'], 'appt-1');
        expect(body, isNot(contains('doctor_id')));
      },
    );

    test('malformed top-level data is a controlled INVALID_RESPONSE', () async {
      final fake = _RecordingDio([_ok('bad')]);
      await expectLater(
        DoctorWorkspaceApi(fake.dio).getProfile(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test('malformed clinical entry fails instead of being dropped', () async {
      final fake = _RecordingDio([
        _ok([_record(), 'bad-entry']),
      ]);
      await expectLater(
        DoctorWorkspaceApi(fake.dio).getRecords(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'INVALID_RESPONSE'),
        ),
      );
    });

    test(
      'missing required typed field is normalized to INVALID_RESPONSE',
      () async {
        final fake = _RecordingDio([
          _ok([
            {'id': 'record-1', 'record_type': 'consultation'},
          ]),
        ]);
        await expectLater(
          DoctorWorkspaceApi(fake.dio).getRecords(),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'INVALID_RESPONSE',
            ),
          ),
        );
      },
    );
  });
}

Map<String, dynamic> _profile() => {
  'id': '11111111-1111-4111-8111-111111111111',
  'approval_status': 'approved',
  'is_accepting_patients': true,
  'professional_bio': 'Bio',
};
Map<String, dynamic> _availability() => {
  'id': 'slot-1',
  'clinic_id': null,
  'day_of_week': 1,
  'specific_date': null,
  'start_time': '09:00:00',
  'end_time': '12:00:00',
  'slot_duration': 30,
  'is_telemedicine': true,
  'availability_type': 'available',
  'is_active': true,
};
Map<String, dynamic> _appointment({String status = 'scheduled'}) => {
  'id': 'appt-1',
  'appointment_number': 'APT-1',
  'patient_profile_id': 'profile-1',
  'scheduled_date': '2026-09-01',
  'start_time': '09:00:00',
  'end_time': '09:30:00',
  'appointment_type': 'telemedicine',
  'status': status,
};
Map<String, dynamic> _schedule() => {
  'booking_horizon_days': 90,
  'weekly': [_availability()],
  'overrides': [],
  'clinics': [],
  'appointments': [_appointment()],
};
Map<String, dynamic> _patient() => {
  'id': 'patient-1',
  'email': 'patient@example.test',
  'first_name_en': 'Noor',
  'has_upcoming': true,
};
Map<String, dynamic> _record() => {
  'id': 'record-1',
  'record_number': 'MR-1',
  'record_type': 'consultation',
  'diagnosis': 'Migraine',
  'is_draft': false,
  'visible_to_patient': true,
};
Map<String, dynamic> _prescription() => {
  'id': 'rx-1',
  'prescription_number': 'RX-1',
  'status': 'active',
};
Map<String, dynamic> _post() => {
  'id': 'post-1',
  'title': 'Title',
  'category': 'health_tip',
  'body': 'Body',
  'is_published': true,
  'status': 'published',
  'moderation_status': 'approved',
};

class _Reply {
  const _Reply(this.data);
  final Object? data;
}

_Reply _ok(Object? data) => _Reply({'success': true, 'data': data});

class _RecordingDio {
  _RecordingDio(List<_Reply> replies)
    : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    final queue = [...replies];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          final reply = queue.removeAt(0);
          handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: reply.data,
            ),
          );
        },
      ),
    );
  }
  final Dio dio;
  final requests = <RequestOptions>[];
  List<String> get paths => requests.map((r) => r.path).toList();
}

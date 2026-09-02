import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/my_doctors/data/my_doctors_api.dart';

void main() {
  test(
    'listDoctors reads the authenticated patient care relationship endpoint',
    () async {
      final fake = _FakeDio({
        'success': true,
        'data': [
          {
            'id': 'doctor-1',
            'first_name_ar': 'ليان',
            'last_name_ar': 'خليل',
            'first_name_en': 'Layan',
            'last_name_en': 'Khalil',
            'specialty_ar': 'قلب',
            'specialty_en': 'Cardiology',
            'next_appointment_date': '2026-09-01',
            'has_upcoming': true,
          },
        ],
      });

      final doctors = await MyDoctorsApi(fake.dio).listDoctors();

      expect(fake.path, '/patients/me/doctors');
      expect(doctors.single.fullName(false), 'Layan Khalil');
      expect(doctors.single.specialty(true), 'قلب');
      expect(doctors.single.hasUpcoming, isTrue);
    },
  );

  test(
    'listSharedNotes reads only the selected doctor shared-note endpoint',
    () async {
      final fake = _FakeDio({
        'success': true,
        'data': [
          {
            'id': 'note-1',
            'record_type': 'consultation',
            'chief_complaint': 'Persistent headache',
            'diagnosis': 'Hypertension',
            'treatment_plan': 'Monitor blood pressure',
            'clinical_notes': 'Follow up in one month',
            'created_at': '2026-08-26T08:00:00.000Z',
          },
        ],
      });

      final notes = await MyDoctorsApi(fake.dio).listSharedNotes('doctor-1');

      expect(fake.path, '/patients/me/doctors/doctor-1/notes');
      expect(notes.single.chiefComplaint, 'Persistent headache');
      expect(notes.single.diagnosis, 'Hypertension');
      expect(notes.single.clinicalNotes, 'Follow up in one month');
    },
  );

  test(
    'rejects an unexpected envelope without exposing its contents',
    () async {
      final fake = _FakeDio({
        'success': true,
        'data': {'private': 'unexpected'},
      });
      await expectLater(
        MyDoctorsApi(fake.dio).listDoctors(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.code,
            'code',
            'INVALID_RESPONSE',
          ),
        ),
      );
    },
  );
}

class _FakeDio {
  _FakeDio(this.body)
    : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.path;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: body,
            ),
          );
        },
      ),
    );
  }

  final Map<String, dynamic> body;
  final Dio dio;
  String? path;
}

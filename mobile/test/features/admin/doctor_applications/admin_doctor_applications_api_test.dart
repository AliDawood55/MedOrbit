import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/admin/doctor_applications/data/admin_doctor_applications_api.dart';
import 'package:mobile/features/admin/doctor_applications/models/admin_doctor_application.dart';

import '../admin_test_support.dart';

Map<String, dynamic> _application({
  String id = 'app-1',
  String status = 'pending',
  Object? education = const <String>['MD, An-Najah'],
}) => {
  'id': id,
  'user_id': 'user-1',
  'specialty_id': 'spec-1',
  'medical_license_number': 'LIC-9',
  'sub_specialty': 'Interventional',
  'years_of_experience': 7,
  'education': education,
  'certifications': <String>['Board certified'],
  'bio': 'Cardiologist',
  'bio_ar': 'طبيب قلب',
  'bio_en': 'Cardiologist',
  'status': status,
  'submitted_at': '2026-02-01T09:00:00Z',
  'reviewed_at': null,
  'rejection_reason': null,
  'approved_doctor_id': null,
  'applicant': {
    'email': 'applicant@example.test',
    'first_name_ar': 'لينا',
    'last_name_ar': 'حداد',
    'first_name_en': 'Lina',
    'last_name_en': 'Haddad',
  },
  'specialty': {'name_ar': 'طب القلب', 'name_en': 'Cardiology'},
};

void main() {
  test('list sends only the status filter the backend implements', () async {
    final dio = RecordingDio()
      ..enqueue({'success': true, 'data': <dynamic>[]})
      ..enqueue({'success': true, 'data': <dynamic>[]});

    final api = AdminDoctorApplicationsApi(dio.dio);
    await api.list(status: AdminApplicationStatus.pending);
    await api.list();

    expect(dio.paths, [
      '/admin/doctor-applications',
      '/admin/doctor-applications',
    ]);
    expect(dio.methods, ['GET', 'GET']);
    expect(dio.queries.first, {'status': 'pending'});
    expect(dio.queries[1], isEmpty);
  });

  test('every status filter maps to its exact wire value', () {
    expect(
      adminApplicationStatusWireValue(AdminApplicationStatus.approved),
      'approved',
    );
    expect(
      adminApplicationStatusWireValue(AdminApplicationStatus.rejected),
      'rejected',
    );
    expect(
      adminApplicationStatusWireValue(AdminApplicationStatus.withdrawn),
      'withdrawn',
    );
    expect(adminApplicationStatusWireValue(null), isNull);
  });

  test('parses the admin projection, applicant and specialty included', () async {
    final dio = RecordingDio()
      ..enqueue({
        'success': true,
        'data': [_application()],
      });

    final application = (await AdminDoctorApplicationsApi(dio.dio).list()).single;

    expect(application.id, 'app-1');
    expect(application.status, AdminApplicationStatus.pending);
    expect(application.isPending, isTrue);
    expect(application.medicalLicenseNumber, 'LIC-9');
    expect(application.yearsOfExperience, 7);
    expect(application.education, ['MD, An-Najah']);
    expect(application.applicant.email, 'applicant@example.test');
    expect(application.applicant.displayName(isArabic: true), 'لينا حداد');
    expect(application.applicant.displayName(isArabic: false), 'Lina Haddad');
    expect(application.specialtyName(isArabic: true), 'طب القلب');
    expect(application.specialtyName(isArabic: false), 'Cardiology');
  });

  test('an applicant with no profile names falls back to the email', () {
    final application = AdminDoctorApplication.fromJson({
      ..._application(),
      'applicant': {'email': 'nameless@example.test'},
    });

    expect(
      application.applicant.displayName(isArabic: false),
      'nameless@example.test',
    );
  });

  test('an unknown status keeps its raw value', () {
    final application = AdminDoctorApplication.fromJson(
      _application(status: 'escalated'),
    );

    expect(application.status, AdminApplicationStatus.unknown);
    expect(application.statusValue, 'escalated');
    expect(application.isPending, isFalse);
  });

  test('a malformed credential list fails loudly instead of dropping it', () {
    // Hiding a credential line would show the reviewer an incomplete record
    // for a decision that cannot be undone.
    expect(
      () => AdminDoctorApplication.fromJson(
        _application(education: [1, 2]),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('detail, approve and reject use the exact paths and payloads', () async {
    final dio = RecordingDio()
      ..enqueue({'success': true, 'data': _application()})
      ..enqueue({'success': true, 'data': _application(status: 'approved')})
      ..enqueue({'success': true, 'data': _application(status: 'rejected')});

    final api = AdminDoctorApplicationsApi(dio.dio);
    await api.get('app-1');
    await api.approve('app-1');
    await api.reject('app-1', 'Licence could not be verified');

    expect(dio.paths, [
      '/admin/doctor-applications/app-1',
      '/admin/doctor-applications/app-1/approve',
      '/admin/doctor-applications/app-1/reject',
    ]);
    expect(dio.methods, ['GET', 'POST', 'POST']);
    expect(dio.bodies[1], <String, dynamic>{});
    expect(dio.bodies[2], {
      'rejection_reason': 'Licence could not be verified',
    });
  });

  test('a NOT_FOUND decision surfaces the code only', () async {
    final dio = RecordingDio()..enqueueFailure(404, 'NOT_FOUND');

    try {
      await AdminDoctorApplicationsApi(dio.dio).approve('app-1');
      fail('expected a failure');
    } catch (error) {
      expect(ApiException.from(error).code, 'NOT_FOUND');
    }
  });
}

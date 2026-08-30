import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/doctor_application/models/doctor_application_model.dart';

void main() {
  Map<String, dynamic> json({String status = 'pending'}) => {
    'id': 'application-1', 'user_id': 'user-1', 'specialty_id': 'specialty-1',
    'medical_license_number': 'LIC-1', 'status': status,
    'submitted_at': '2026-01-02T03:04:05Z',
    'sub_specialty': 'Cardiac imaging', 'years_of_experience': 12,
    'education': ['University A', 'University B'], 'certifications': ['Board certified'],
    'bio': 'Bio', 'bio_ar': 'Arabic bio', 'bio_en': 'English bio',
    'consultation_fee': '250.5', 'consultation_duration': '30',
    'reviewed_at': '2026-01-03T03:04:05Z', 'rejection_reason': 'Missing record',
    'approved_doctor_id': 'doctor-1',
  };

  test('parses complete application DTO', () {
    final value = DoctorApplication.fromJson(json());
    expect(value.status, DoctorApplicationStatus.pending);
    expect(value.education, ['University A', 'University B']);
    expect(value.certifications, ['Board certified']);
    expect(value.submittedAt.toUtc().year, 2026);
    expect(value.reviewedAt, isNotNull);
    expect(value.consultationFee, 250.5);
    expect(value.consultationDuration, 30);
    expect(value.rejectionReason, 'Missing record');
    expect(value.approvedDoctorId, 'doctor-1');
  });

  test('parses null optional fields', () {
    final body = json()..addAll({'sub_specialty': null, 'years_of_experience': null, 'education': null, 'certifications': null, 'bio': null, 'bio_ar': null, 'bio_en': null, 'consultation_fee': null, 'consultation_duration': null, 'reviewed_at': null, 'rejection_reason': null, 'approved_doctor_id': null});
    final value = DoctorApplication.fromJson(body);
    expect(value.subSpecialty, isNull); expect(value.education, isEmpty); expect(value.reviewedAt, isNull); expect(value.consultationFee, isNull);
  });

  test('parses all verified statuses and safely preserves unknown values', () {
    expect(DoctorApplication.fromJson(json(status: 'approved')).status, DoctorApplicationStatus.approved);
    expect(DoctorApplication.fromJson(json(status: 'rejected')).status, DoctorApplicationStatus.rejected);
    expect(DoctorApplication.fromJson(json(status: 'withdrawn')).status, DoctorApplicationStatus.withdrawn);
    final unknown = DoctorApplication.fromJson(json(status: 'under_review'));
    expect(unknown.status, DoctorApplicationStatus.unknown); expect(unknown.statusValue, 'under_review');
  });

  test('rejects malformed required data', () {
    expect(() => DoctorApplication.fromJson(json()..remove('id')), throwsFormatException);
    expect(() => DoctorApplication.fromJson(json()..['submitted_at'] = 'not-a-date'), throwsFormatException);
  });

  test('request normalization is deterministic', () {
    final request = DoctorApplicationRequest.fromMultiline(specialtyId: ' specialty ', medicalLicenseNumber: ' LIC ', subSpecialty: ' ', bio: ' bio ', yearsOfExperience: 0, education: 'University A\n\n University B ', certifications: ' A \n \nB ');
    expect(request.toJson(), {'specialty_id': 'specialty', 'medical_license_number': 'LIC', 'sub_specialty': null, 'years_of_experience': 0, 'education': ['University A', 'University B'], 'certifications': ['A', 'B'], 'bio': 'bio'});
  });
}

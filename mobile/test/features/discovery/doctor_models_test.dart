import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';

void main() {
  test('parses doctor list with numeric strings nested clinics availability and reviews', () {
    final response = DoctorListResponse.fromJson({
      'success': true,
      'data': {
        'doctors': [
          {
            'id': 'doctor-1',
            'user_id': 'user-1',
            'medical_license_number': 'WB-123',
            'years_of_experience': '12',
            'consultation_fee': '75.50',
            'consultation_duration': '30',
            'average_rating': '4.9',
            'total_ratings': '42',
            'is_accepting_patients': 'true',
            'education': ['An-Najah National University'],
            'certifications': ['Board certified'],
            'professional_bio_ar': 'طبيب قلب',
            'professional_bio_en': 'Cardiologist',
            'email': 'doctor@example.test',
            'first_name_ar': 'ليلى',
            'last_name_ar': 'خالد',
            'first_name_en': 'Layla',
            'last_name_en': 'Khaled',
            'specialty_id': 'specialty-1',
            'specialty_name_en': 'Cardiology',
            'clinics': [
              {'id': 'clinic-1', 'name_en': 'Nablus Clinic', 'distance_km': '1.4'},
            ],
            'availability': [
              {
                'id': 'slot-1',
                'date': '2026-08-05',
                'start_time': '09:00',
                'end_time': '09:30',
                'is_available': 1,
              },
            ],
            'reviews': [
              {'id': 'review-1', 'patient_name': 'Anonymous', 'rating': '5', 'comment': 'Helpful'},
            ],
            'created_at': '2026-08-04T10:00:00Z',
            'unknown_doctor_field': {'kept': true},
          },
        ],
        'pagination': {'page': '1', 'limit': '10', 'total': '1', 'total_pages': '1'},
      },
    });

    final doctor = response.doctors.single;
    expect(doctor.id, 'doctor-1');
    expect(doctor.userId, 'user-1');
    expect(doctor.yearsOfExperience, 12);
    expect(doctor.consultationFee, 75.5);
    expect(doctor.consultationDuration, 30);
    expect(doctor.averageRating, 4.9);
    expect(doctor.totalRatings, 42);
    expect(doctor.isAcceptingPatients, isTrue);
    expect(doctor.specialtyNameEn, 'Cardiology');
    expect(doctor.clinics.single.distanceKm, 1.4);
    expect(doctor.availability.single.isAvailable, isTrue);
    expect(doctor.reviews.single.rating, 5);
    expect(doctor.createdAt, isNotNull);
    expect(doctor.extra['unknown_doctor_field'], {'kept': true});
    expect(response.pagination?.totalPages, 1);
  });

  test('parses doctor detail and availability response with camelCase aliases', () {
    final detail = DoctorDetailResponse.fromJson({
      'data': {
        'doctor': {
          'id': 9,
          'userId': 'user-9',
          'medicalLicenseNumber': 'WB-999',
          'yearsOfExperience': 8,
          'consultationFee': '60',
          'consultationDuration': '20',
          'averageRating': '4.5',
          'totalRatings': '13',
          'isAcceptingPatients': true,
          'firstNameEn': 'Samir',
          'lastNameEn': 'Nasser',
          'specialtyEn': 'Dermatology',
        },
        'clinics': [
          {'id': 'clinic-9', 'nameEn': 'Village Clinic', 'latitude': '32.2', 'longitude': '35.2'},
        ],
        'availability': [
          {'id': 'slot-9', 'doctorId': 9, 'clinicId': 'clinic-9', 'isAvailable': 'false'},
        ],
        'reviews': [
          {'id': 'review-9', 'patientName': 'Verified patient', 'rating': 4.5, 'createdAt': '2026-08-01T09:00:00Z'},
        ],
      },
    });

    expect(detail.doctor?.id, '9');
    expect(detail.doctor?.medicalLicenseNumber, 'WB-999');
    expect(detail.doctor?.specialtyEn, 'Dermatology');
    expect(detail.clinics.single.latitude, 32.2);
    expect(detail.availability.single.doctorId, '9');
    expect(detail.availability.single.isAvailable, isFalse);
    expect(detail.reviews.single.patientName, 'Verified patient');
    expect(detail.reviews.single.createdAt, isNotNull);

    final availability = DoctorAvailabilityResponse.fromJson({
      'data': {
        'slots': [
          {'id': 'slot-10', 'date': '2026-08-06', 'startTime': '10:00', 'endTime': '10:30', 'status': 'open'},
        ],
      },
    });

    expect(availability.slots.single.startTime, '10:00');
    expect(availability.slots.single.status, 'open');
  });

  test('missing optional fields do not throw and toJson copies unknown maps', () {
    expect(() => DoctorDetailResponse.fromJson({'data': {}}), returnsNormally);

    final doctor = Doctor.fromJson({
      'id': 'doctor-2',
      'future_payload': {'nested': 'kept'},
    });
    final json = doctor.toJson();

    (json['future_payload'] as Map)['nested'] = 'changed';

    expect(doctor.extra['future_payload'], {'nested': 'kept'});
  });
}

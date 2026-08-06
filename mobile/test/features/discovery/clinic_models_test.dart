import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/discovery/models/clinic_models.dart';

void main() {
  test('parses clinic list with PostgreSQL numeric strings and pagination aliases', () {
    final response = ClinicListResponse.fromJson({
      'success': true,
      'data': {
        'clinics': [
          {
            'id': 'clinic-1',
            'name_ar': 'عيادة رفيديا',
            'name_en': 'Rafidia Clinic',
            'address_en': 'Nablus',
            'city': 'Nablus',
            'region': 'West Bank',
            'latitude': '32.2211',
            'longitude': '35.2544',
            'distance_km': '2.35',
            'average_rating': '4.7',
            'rating': '4.6',
            'verification_status': 'verified',
            'is_active': 1,
            'unknown_clinic_field': {'kept': true},
          },
        ],
        'pagination': {'page': '1', 'limit': '20', 'total': '1', 'totalPages': '1', 'hasNext': false},
      },
    });

    final clinic = response.clinics.single;
    expect(clinic.id, 'clinic-1');
    expect(clinic.latitude, 32.2211);
    expect(clinic.longitude, 35.2544);
    expect(clinic.distanceKm, 2.35);
    expect(clinic.averageRating, 4.7);
    expect(clinic.rating, 4.6);
    expect(clinic.verificationStatus, ClinicVerificationStatus.verified);
    expect(clinic.isActive, isTrue);
    expect(clinic.extra['unknown_clinic_field'], {'kept': true});
    expect(response.pagination?.totalPages, 1);
    expect(response.pagination?.hasNext, isFalse);
  });

  test('parses clinic detail with operating hours services insurance doctors and missing optionals', () {
    final response = ClinicDetailResponse.fromJson({
      'data': {
        'clinic': {
          'id': 'clinic-2',
          'nameEn': 'Old City Clinic',
          'operating_hours': {
            'monday': {'open': '08:00', 'close': '16:00'},
            'friday': {'is_closed': true},
            'notes': 'Ramadan hours may differ',
          },
          'services': ['general', 'pediatrics'],
          'insurance_accepted': ['public', 'private'],
          'images': ['https://example.test/image.jpg'],
          'logo_url': null,
          'verification_status': 'under_review',
        },
        'doctors': [
          {
            'id': 'doctor-1',
            'firstNameEn': 'Alaa',
            'lastNameEn': 'Hassan',
            'consultation_fee': '50.00',
            'is_accepting_patients': 'true',
          },
        ],
      },
    });

    expect(response.clinic?.nameEn, 'Old City Clinic');
    expect(response.clinic?.operatingHours?.days['monday']?.open, '08:00');
    expect(response.clinic?.operatingHours?.days['friday']?.isClosed, isTrue);
    expect(response.clinic?.operatingHours?.extra['notes'], 'Ramadan hours may differ');
    expect(response.clinic?.services, ['general', 'pediatrics']);
    expect(response.clinic?.insuranceAccepted, ['public', 'private']);
    expect(response.clinic?.verificationStatus, ClinicVerificationStatus.unknown);
    expect(response.clinic?.verificationStatusValue, 'under_review');
    expect(response.doctors.single.consultationFee, 50.0);
    expect(response.doctors.single.isAcceptingPatients, isTrue);
  });

  test('nearby response and missing optional fields are tolerant', () {
    expect(() => NearbyClinicResponse.fromJson({'data': {}}), returnsNormally);

    final response = NearbyClinicResponse.fromJson({
      'data': {
        'clinics': [
          {'id': 7, 'distanceKm': '0.8'},
        ],
      },
    });

    expect(response.clinics.single.id, '7');
    expect(response.clinics.single.distanceKm, 0.8);
  });
}

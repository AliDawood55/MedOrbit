import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';

void main() {
  test('clinics list sends only non-null filters and parses numeric strings', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'clinics': [
            {
              'id': 'clinic-1',
              'name_en': 'Nablus Clinic',
              'latitude': '32.2211',
              'longitude': '35.2544',
              'distance_km': '1.7',
              'average_rating': '4.6',
            },
          ],
          'pagination': {'page': '2', 'limit': '10', 'total': '11'},
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);

    final response = await api.listClinics(
      region: 'Nablus',
      insurance: 'public',
      search: 'clinic',
      page: 2,
    );

    expect(fake.requests.single.method, 'GET');
    expect(fake.requests.single.path, '/clinics');
    expect(fake.requests.single.queryParameters, {
      'region': 'Nablus',
      'insurance': 'public',
      'search': 'clinic',
      'page': 2,
      'limit': 10,
    });
    expect(response.clinics.single.latitude, 32.2211);
    expect(response.clinics.single.distanceKm, 1.7);
    expect(response.pagination?.total, 11);
  });

  test('nearby clinics sends lat lng radius and type correctly', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'clinics': [
            {'id': 'clinic-2', 'name_en': 'Nearby Clinic', 'distanceKm': '0.9'},
          ],
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);

    final response = await api.nearbyClinics(
      lat: 32.2211,
      lng: 35.2544,
      radius: 7.5,
      type: 'clinic',
    );

    expect(fake.requests.single.path, '/clinics/nearby');
    expect(fake.requests.single.queryParameters, {
      'lat': 32.2211,
      'lng': 35.2544,
      'radius': 7.5,
      'type': 'clinic',
    });
    expect(response.clinics.single.distanceKm, 0.9);
  });

  test('clinic detail parses clinic doctors and missing optional fields', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'clinic': {
            'id': 'clinic-3',
            'nameEn': 'Old City Clinic',
            'operating_hours': {
              'monday': {'open': '08:00', 'close': '16:00'},
            },
          },
          'doctors': [
            {'id': 'doctor-1', 'firstNameEn': 'Alaa', 'consultation_fee': '60'},
          ],
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);

    final response = await api.getClinic('clinic-3');

    expect(fake.requests.single.path, '/clinics/clinic-3');
    expect(response.clinic?.nameEn, 'Old City Clinic');
    expect(response.clinic?.operatingHours?.days['monday']?.open, '08:00');
    expect(response.doctors.single.consultationFee, 60);
  });

  test('doctors list sends only non-null filters and parses nested data', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'doctors': [
            {
              'id': 'doctor-1',
              'first_name_en': 'Mariam',
              'specialty_name_en': 'Cardiology',
              'average_rating': '4.9',
              'consultation_fee': '80',
              'clinics': [
                {'id': 'clinic-1', 'name_en': 'Nablus Clinic'},
              ],
            },
          ],
          'pagination': {'page': '1', 'limit': '10', 'total': '1'},
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);

    final response = await api.listDoctors(
      specialty: 'cardiology',
      minRating: 4.5,
      maxFee: 100,
      search: 'mariam',
    );

    expect(fake.requests.single.path, '/doctors');
    expect(fake.requests.single.queryParameters, {
      'specialty': 'cardiology',
      'minRating': 4.5,
      'maxFee': 100.0,
      'search': 'mariam',
      'page': 1,
      'limit': 10,
    });
    expect(response.doctors.single.averageRating, 4.9);
    expect(response.doctors.single.consultationFee, 80);
    expect(response.doctors.single.clinics.single.nameEn, 'Nablus Clinic');
  });

  test('doctor detail and availability parse correctly', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'doctor': {
            'id': 'doctor-2',
            'firstNameEn': 'Samir',
            'isAcceptingPatients': true,
          },
          'clinics': [
            {'id': 'clinic-2', 'nameEn': 'Village Clinic', 'latitude': '32.2'},
          ],
          'availability': [
            {'id': 'slot-1', 'start_time': '09:00', 'is_available': 'true'},
          ],
          'reviews': [
            {'id': 'review-1', 'rating': '5', 'comment': 'Helpful'},
          ],
        },
      },
      {
        'success': true,
        'data': {
          'slots': [
            {'id': 'slot-2', 'date': '2026-08-05', 'startTime': '10:00', 'status': 'open'},
          ],
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);

    final detail = await api.getDoctor('doctor-2');
    final availability = await api.getDoctorAvailability('doctor-2', date: '2026-08-05');

    expect(fake.requests[0].path, '/doctors/doctor-2');
    expect(detail.doctor?.isAcceptingPatients, isTrue);
    expect(detail.clinics.single.latitude, 32.2);
    expect(detail.availability.single.isAvailable, isTrue);
    expect(detail.reviews.single.rating, 5);
    expect(fake.requests[1].path, '/doctors/doctor-2/availability');
    expect(fake.requests[1].queryParameters, {'date': '2026-08-05'});
    expect(availability.slots.single.startTime, '10:00');
  });

  test('success false is not parsed as data and null optional fields do not throw', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'doctors': [
            {'id': 'doctor-3', 'first_name_en': null, 'average_rating': null},
          ],
          'pagination': null,
        },
      },
      {'success': false, 'message': 'Discovery request failed', 'data': {'private': 'payload'}},
    ]);
    final api = DiscoveryApi(fake.dio);

    final doctors = await api.listDoctors();

    expect(doctors.doctors.single.firstNameEn, isNull);
    expect(doctors.pagination, isNull);
    await expectLater(
      api.getClinic('clinic-private'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'BACKEND_FAILURE')
            .having((error) => error.message, 'message', 'Discovery request failed')
            .having((error) => error.details, 'details', isNull),
      ),
    );
  });

  test('client does not print or manually log request or response bodies', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'clinics': [
            {'id': 'clinic-private', 'name_en': 'Private Clinic'},
          ],
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      () => api.listClinics(search: 'private medical search'),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });

  test('a doctor missing its id throws instead of the list silently succeeding with a broken entry', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'doctors': [
            {'first_name_en': 'No id doctor'},
          ],
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);

    await expectLater(api.listDoctors(), throwsFormatException);
  });

  test('a clinic missing its id throws instead of the list silently succeeding with a broken entry', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'clinics': [
            {'name_en': 'No id clinic'},
          ],
        },
      },
    ]);
    final api = DiscoveryApi(fake.dio);

    await expectLater(api.listClinics(), throwsFormatException);
  });
}

class _FakeDio {
  _FakeDio(List<Map<String, dynamic>> responses)
    : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(
            _RecordedRequest(
              method: options.method,
              path: options.path,
              data: options.data,
              queryParameters: Map<String, dynamic>.from(options.queryParameters),
            ),
          );
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: responses.removeAt(0),
            ),
          );
        },
      ),
    );
  }

  final Dio dio;
  final requests = <_RecordedRequest>[];
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.data,
    required this.queryParameters,
  });

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic> queryParameters;
}

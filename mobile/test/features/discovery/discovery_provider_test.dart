import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';
import 'package:mobile/features/discovery/models/clinic_models.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';

void main() {
  test('clinic filters are passed correctly and pagination load more appends', () async {
    final fake = _FakeDiscoveryApi()
      ..clinicListResults.add(
        Future.value(
          const ClinicListResponse(
            clinics: [Clinic(id: 'clinic-1', nameEn: 'First')],
            pagination: ClinicPagination(page: 1, limit: 1, total: 2, totalPages: 2, hasNext: true),
          ),
        ),
      )
      ..clinicListResults.add(
        Future.value(
          const ClinicListResponse(
            clinics: [Clinic(id: 'clinic-2', nameEn: 'Second')],
            pagination: ClinicPagination(page: 2, limit: 1, total: 2, totalPages: 2, hasNext: false),
          ),
        ),
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    await container.read(discoveryControllerProvider.notifier).loadClinics(
      filters: const ClinicFilters(region: 'Nablus', service: 'pediatrics', insurance: 'public', limit: 1),
    );
    await container.read(discoveryControllerProvider.notifier).loadMoreClinics();

    final state = container.read(discoveryControllerProvider);
    expect(fake.clinicListCalls.first.region, 'Nablus');
    expect(fake.clinicListCalls.first.service, 'pediatrics');
    expect(fake.clinicListCalls.first.insurance, 'public');
    expect(fake.clinicListCalls.last.page, 2);
    expect(state.clinics.map((clinic) => clinic.id), ['clinic-1', 'clinic-2']);
  });

  test('stale filtered clinic response is ignored', () async {
    final first = Completer<ClinicListResponse>();
    final second = Completer<ClinicListResponse>();
    final fake = _FakeDiscoveryApi()
      ..clinicListResults.add(first.future)
      ..clinicListResults.add(second.future);
    final container = _container(fake);
    addTearDown(container.dispose);

    final stale = container
        .read(discoveryControllerProvider.notifier)
        .loadClinics(filters: const ClinicFilters(search: 'old'));
    final fresh = container
        .read(discoveryControllerProvider.notifier)
        .loadClinics(filters: const ClinicFilters(search: 'new'));

    second.complete(const ClinicListResponse(clinics: [Clinic(id: 'new')]));
    expect(await fresh, isTrue);

    first.complete(const ClinicListResponse(clinics: [Clinic(id: 'old')]));
    expect(await stale, isFalse);
    expect(container.read(discoveryControllerProvider).clinics.single.id, 'new');
  });

  test('nearby results remain separate and coordinates are not persisted in filters', () async {
    final fake = _FakeDiscoveryApi()
      ..clinicListResults.add(Future.value(const ClinicListResponse(clinics: [Clinic(id: 'normal')])))
      ..nearbyResults.add(Future.value(const NearbyClinicResponse(clinics: [Clinic(id: 'nearby')])));
    final container = _container(fake);
    addTearDown(container.dispose);

    await container.read(discoveryControllerProvider.notifier).loadClinics();
    await container.read(discoveryControllerProvider.notifier).loadNearbyClinics(
      lat: 32.2211,
      lng: 35.2544,
      radius: 7,
      type: 'clinic',
    );

    final state = container.read(discoveryControllerProvider);
    expect(fake.nearbyCalls.single.lat, 32.2211);
    expect(fake.nearbyCalls.single.lng, 35.2544);
    expect(fake.nearbyCalls.single.radius, 7);
    expect(fake.nearbyCalls.single.type, 'clinic');
    expect(state.clinics.single.id, 'normal');
    expect(state.nearbyClinics.single.id, 'nearby');
    expect(state.clinicFilters, const ClinicFilters());
  });

  test('clinic detail preserves verification status', () async {
    final fake = _FakeDiscoveryApi()
      ..clinicDetailResults.add(
        Future.value(
          const ClinicDetailResponse(
            clinic: Clinic(
              id: 'clinic-1',
              nameEn: 'Verified Clinic',
              verificationStatus: ClinicVerificationStatus.verified,
              verificationStatusValue: 'verified',
              isActive: true,
            ),
            doctors: [ClinicDoctorSummary(id: 'doctor-1', firstNameEn: 'Alaa')],
          ),
        ),
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    await container.read(discoveryControllerProvider.notifier).loadClinicDetail('clinic-1');

    final clinic = container.read(discoveryControllerProvider).selectedClinicDetail?.clinic;
    expect(fake.clinicDetailCalls.single, 'clinic-1');
    expect(clinic?.verificationStatus, ClinicVerificationStatus.verified);
    expect(clinic?.isActive, isTrue);
  });

  test('doctor filters pagination detail and availability update separate state', () async {
    final fake = _FakeDiscoveryApi()
      ..doctorListResults.add(
        Future.value(
          const DoctorListResponse(
            doctors: [Doctor(id: 'doctor-1', firstNameEn: 'Mariam')],
            pagination: DoctorPagination(page: 1, limit: 1, total: 2, totalPages: 2, hasNext: true),
          ),
        ),
      )
      ..doctorListResults.add(
        Future.value(
          const DoctorListResponse(
            doctors: [Doctor(id: 'doctor-2', firstNameEn: 'Samir')],
            pagination: DoctorPagination(page: 2, limit: 1, total: 2, totalPages: 2, hasNext: false),
          ),
        ),
      )
      ..doctorDetailResults.add(
        Future.value(const DoctorDetailResponse(doctor: Doctor(id: 'doctor-1', firstNameEn: 'Mariam'))),
      )
      ..availabilityResults.add(
        Future.value(const DoctorAvailabilityResponse(slots: [DoctorAvailabilitySlot(id: 'slot-1', status: 'open')])),
      );
    final container = _container(fake);
    addTearDown(container.dispose);

    await container.read(discoveryControllerProvider.notifier).loadDoctors(
      filters: const DoctorFilters(specialty: 'cardiology', minRating: 4.5, maxFee: 100, limit: 1),
    );
    await container.read(discoveryControllerProvider.notifier).loadMoreDoctors();
    await container.read(discoveryControllerProvider.notifier).loadDoctorDetail('doctor-1');
    await container.read(discoveryControllerProvider.notifier).loadDoctorAvailability('doctor-1', date: '2026-08-05');

    final state = container.read(discoveryControllerProvider);
    expect(fake.doctorListCalls.first.specialty, 'cardiology');
    expect(fake.doctorListCalls.first.minRating, 4.5);
    expect(fake.doctorListCalls.first.maxFee, 100);
    expect(fake.doctorListCalls.last.page, 2);
    expect(state.doctors.map((doctor) => doctor.id), ['doctor-1', 'doctor-2']);
    expect(state.selectedDoctorDetail?.doctor?.id, 'doctor-1');
    expect(fake.availabilityCalls.single.date, '2026-08-05');
    expect(state.doctorAvailability.single.id, 'slot-1');
  });

  test('duplicate clinic requests are prevented', () async {
    final completer = Completer<ClinicListResponse>();
    final fake = _FakeDiscoveryApi()..clinicListResults.add(completer.future);
    final container = _container(fake);
    addTearDown(container.dispose);

    final first = container.read(discoveryControllerProvider.notifier).loadClinics();
    final second = await container.read(discoveryControllerProvider.notifier).loadClinics();

    expect(second, isFalse);
    expect(fake.clinicListCalls, hasLength(1));

    completer.complete(const ClinicListResponse(clinics: [Clinic(id: 'clinic-1')]));
    expect(await first, isTrue);
  });

  test('API failures expose safe retryable state', () async {
    final failure = Completer<DoctorListResponse>();
    final fake = _FakeDiscoveryApi()..doctorListResults.add(failure.future);
    final container = _container(fake);
    addTearDown(container.dispose);

    final pending = container.read(discoveryControllerProvider.notifier).loadDoctors();
    failure.completeError(
      const ApiException(message: 'Could not load doctors.', code: 'DOCTORS_FAILED', statusCode: 503),
    );
    final ok = await pending;

    final error = container.read(discoveryControllerProvider).doctorListError;
    expect(ok, isFalse);
    expect(error?.message, 'Could not load doctors.');
    expect(error?.code, 'DOCTORS_FAILED');
    expect(error?.statusCode, 503);
    expect(error?.retryable, isTrue);
  });
}

ProviderContainer _container(_FakeDiscoveryApi fake) {
  return ProviderContainer(
    overrides: [
      discoveryApiProvider.overrideWithValue(fake),
    ],
  );
}

class _FakeDiscoveryApi extends DiscoveryApi {
  _FakeDiscoveryApi() : super(Dio());

  final clinicListResults = <Future<ClinicListResponse>>[];
  final nearbyResults = <Future<NearbyClinicResponse>>[];
  final clinicDetailResults = <Future<ClinicDetailResponse>>[];
  final doctorListResults = <Future<DoctorListResponse>>[];
  final doctorDetailResults = <Future<DoctorDetailResponse>>[];
  final availabilityResults = <Future<DoctorAvailabilityResponse>>[];
  final clinicListCalls = <ClinicFilters>[];
  final nearbyCalls = <({double lat, double lng, double radius, String? type})>[];
  final clinicDetailCalls = <String>[];
  final doctorListCalls = <DoctorFilters>[];
  final availabilityCalls = <({String id, String? date})>[];

  @override
  Future<ClinicListResponse> listClinics({
    String? region,
    String? service,
    String? insurance,
    String? search,
    String? type,
    int page = 1,
    int limit = 10,
  }) {
    clinicListCalls.add(
      ClinicFilters(
        region: region,
        service: service,
        insurance: insurance,
        search: search,
        type: type,
        page: page,
        limit: limit,
      ),
    );
    return clinicListResults.removeAt(0);
  }

  @override
  Future<NearbyClinicResponse> nearbyClinics({
    required double lat,
    required double lng,
    double radius = 5,
    String? type,
  }) {
    nearbyCalls.add((lat: lat, lng: lng, radius: radius, type: type));
    return nearbyResults.removeAt(0);
  }

  @override
  Future<ClinicDetailResponse> getClinic(String id) {
    clinicDetailCalls.add(id);
    return clinicDetailResults.removeAt(0);
  }

  @override
  Future<DoctorListResponse> listDoctors({
    String? specialty,
    String? region,
    double? minRating,
    double? minFee,
    double? maxFee,
    String? search,
    int page = 1,
    int limit = 10,
  }) {
    doctorListCalls.add(
      DoctorFilters(
        specialty: specialty,
        region: region,
        minRating: minRating,
        minFee: minFee,
        maxFee: maxFee,
        search: search,
        page: page,
        limit: limit,
      ),
    );
    return doctorListResults.removeAt(0);
  }

  @override
  Future<DoctorDetailResponse> getDoctor(String id) {
    return doctorDetailResults.removeAt(0);
  }

  @override
  Future<DoctorAvailabilityResponse> getDoctorAvailability(String id, {String? date}) {
    availabilityCalls.add((id: id, date: date));
    return availabilityResults.removeAt(0);
  }
}

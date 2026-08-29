import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/doctor_application/data/doctor_application_api.dart';
import 'package:mobile/features/doctor_application/models/doctor_application_model.dart';
import 'package:mobile/features/doctor_application/providers/doctor_application_provider.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';

void main() {
  test('initial load populates application history and specialties', () async {
    final api = _FakeApi(); final controller = DoctorApplicationController(api);
    await _drain();
    expect(controller.state.isLoading, isFalse);
    expect(controller.state.applications.single.id, 'old');
    expect(controller.state.specialties.single.id, 'cardiology');
    controller.dispose();
  });

  test('duplicate submit calls API once and successful submit updates authoritative history', () async {
    final gate = Completer<DoctorApplication>();
    final api = _FakeApi()..submitResult = gate.future;
    final controller = DoctorApplicationController(api); await _drain();
    final request = _request(); final first = controller.submit(request);
    expect(await controller.submit(request), isFalse); expect(api.submitCalls, 1); expect(api.lastRequest, same(request));
    gate.complete(_application('new')); expect(await first, isTrue);
    expect(controller.state.applications.first.id, 'new'); expect(controller.state.isSubmitting, isFalse);
    controller.dispose();
  });

  test('submit preserves API code and safely handles unexpected errors', () async {
    final api = _FakeApi(); final controller = DoctorApplicationController(api); await _drain();
    api.submitResult = Future.error(const ApiException(message: 'x', code: 'VALIDATION_ERROR'));
    expect(await controller.submit(_request()), isFalse); expect(controller.state.errorCode, 'VALIDATION_ERROR'); expect(controller.state.isSubmitting, isFalse);
    api.submitResult = Future.error(StateError('unexpected'));
    expect(await controller.submit(_request()), isFalse); expect(controller.state.errorCode, ApiException.codeUnknown); expect(controller.state.isSubmitting, isFalse);
    controller.dispose();
  });

  test('duplicate withdrawal calls API once and updates only returned history row', () async {
    final gate = Completer<DoctorApplication>(); final api = _FakeApi()..withdrawResult = gate.future;
    final controller = DoctorApplicationController(api); await _drain();
    final first = controller.withdraw('old'); expect(await controller.withdraw('old'), isFalse); expect(api.withdrawCalls, 1);
    gate.complete(_application('old', status: 'withdrawn')); expect(await first, isTrue);
    expect(controller.state.applications.single.status, DoctorApplicationStatus.withdrawn); expect(controller.state.withdrawingApplicationId, isNull);
    controller.dispose();
  });

  test('withdraw preserves API errors and unexpected exceptions do not escape', () async {
    final api = _FakeApi(); final controller = DoctorApplicationController(api); await _drain();
    api.withdrawResult = Future.error(const ApiException(message: 'x', code: 'INVALID_TARGET'));
    expect(await controller.withdraw('old'), isFalse); expect(controller.state.errorCode, 'INVALID_TARGET');
    api.withdrawResult = Future.error(StateError('unexpected'));
    expect(await controller.withdraw('old'), isFalse); expect(controller.state.errorCode, ApiException.codeUnknown); expect(controller.state.withdrawingApplicationId, isNull);
    controller.dispose();
  });

  test('newer refresh supersedes stale initial load', () async {
    final firstApplications = Completer<List<DoctorApplication>>(); final firstSpecialties = Completer<List<Specialty>>();
    final api = _FakeApi()..applicationLoads = [firstApplications.future, Future.value([_application('fresh')])]..specialtyLoads = [firstSpecialties.future, Future.value([_specialty])];
    final controller = DoctorApplicationController(api); final refresh = controller.refresh();
    await refresh; firstApplications.complete([_application('stale')]); firstSpecialties.complete([_specialty]); await _drain();
    expect(controller.state.applications.single.id, 'fresh'); controller.dispose();
  });

  test('in-flight completion after dispose does not mutate state', () async {
    final applications = Completer<List<DoctorApplication>>(); final specialties = Completer<List<Specialty>>();
    final api = _FakeApi()..applicationLoads = [applications.future]..specialtyLoads = [specialties.future];
    final controller = DoctorApplicationController(api); controller.dispose();
    applications.complete([_application('late')]); specialties.complete([_specialty]); await _drain();
  });

  test('submit completion after dispose is safely ignored', () async {
    final gate = Completer<DoctorApplication>();
    final api = _FakeApi()..submitResult = gate.future;
    final controller = DoctorApplicationController(api);
    await _drain();

    final pending = controller.submit(_request());
    expect(api.submitCalls, 1);
    controller.dispose();

    gate.complete(_application('new'));
    expect(await pending, isTrue);
    expect(api.submitCalls, 1);
  });

  test('withdraw completion after dispose is safely ignored', () async {
    final gate = Completer<DoctorApplication>();
    final api = _FakeApi()..withdrawResult = gate.future;
    final controller = DoctorApplicationController(api);
    await _drain();

    final pending = controller.withdraw('old');
    expect(api.withdrawCalls, 1);
    controller.dispose();

    gate.complete(_application('old', status: 'withdrawn'));
    expect(await pending, isTrue);
    expect(api.withdrawCalls, 1);
  });
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);
final _specialty = Specialty(id: 'cardiology', nameEn: 'Cardiology', nameAr: 'Cardiology');
DoctorApplicationRequest _request() => DoctorApplicationRequest(specialtyId: 'cardiology', medicalLicenseNumber: 'LIC', education: const ['University']);
DoctorApplication _application(String id, {String status = 'pending'}) => DoctorApplication.fromJson({'id': id, 'user_id': 'user', 'specialty_id': 'cardiology', 'medical_license_number': 'LIC', 'status': status, 'submitted_at': '2026-01-01T00:00:00Z', 'education': <String>[], 'certifications': <String>[]});

class _FakeApi extends DoctorApplicationApi {
  _FakeApi() : super(Dio());
  List<Future<List<DoctorApplication>>> applicationLoads = [Future.value([_application('old')])];
  List<Future<List<Specialty>>> specialtyLoads = [Future.value([_specialty])];
  Future<DoctorApplication> submitResult = Future.value(_application('new'));
  Future<DoctorApplication> withdrawResult = Future.value(_application('old', status: 'withdrawn'));
  int submitCalls = 0; int withdrawCalls = 0; DoctorApplicationRequest? lastRequest;
  @override Future<List<DoctorApplication>> loadMyApplications() => applicationLoads.removeAt(0);
  @override Future<List<Specialty>> loadSpecialties() => specialtyLoads.removeAt(0);
  @override Future<DoctorApplication> submitApplication(DoctorApplicationRequest request) { submitCalls++; lastRequest = request; return submitResult; }
  @override Future<DoctorApplication> withdrawApplication(String id) { withdrawCalls++; return withdrawResult; }
}

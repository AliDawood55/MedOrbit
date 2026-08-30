import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';
import 'package:mobile/features/discovery/screens/doctor_detail_screen.dart';

const _strings = AppStrings(false);
const _arStrings = AppStrings(true);

void main() {
  testWidgets('loading and populated doctor detail show backend data without verification claims', (tester) async {
    final pending = Completer<DoctorDetailResponse>(); final api = _DetailApi()..details.add(pending.future);
    await tester.pumpWidget(_app(api)); await tester.pump(); expect(find.text(_strings.doctorLoadingDetails), findsOneWidget);
    pending.complete(const DoctorDetailResponse(doctor: Doctor(id: 'd1', firstNameEn: 'Mariam', lastNameEn: 'Saleh', specialtyEn: 'Family medicine', professionalBioEn: 'Community physician', yearsOfExperience: 8, medicalLicenseNumber: 'LIC-1', education: ['Medical school'], certifications: ['Course']), clinics: [DoctorClinicSummary(id: 'c1', nameEn: 'Rafidia Clinic', latitude: 32.22, longitude: 35.25)], reviews: [DoctorReview(id: 'r1', rating: 5, comment: 'Helpful')]));
    await tester.pump();
    expect(find.text('Mariam Saleh'), findsOneWidget); expect(find.text('Medical school'), findsOneWidget); expect(find.text('Course'), findsOneWidget); expect(find.text('Rafidia Clinic'), findsOneWidget); expect(find.text('Helpful'), findsOneWidget); expect(find.textContaining('verified'), findsNothing);
    expect(find.byKey(const ValueKey('discovery-map-place-c1')), findsOneWidget);
    expect(find.text(_strings.bookNewAppointment), findsOneWidget);
    expect(find.text(_strings.messagesMessageDoctor), findsOneWidget);
  });
  testWidgets('missing optional detail, not found, error retry, and availability states are safe', (tester) async {
    final api = _DetailApi()..failures.add(const ApiException(message: 'Failed', code: 'FAILED'))..details.add(Future.value(const DoctorDetailResponse()));
    await tester.pumpWidget(_app(api)); await tester.pump(); await tester.pump(); expect(find.text(_strings.doctorDetailLoadErrorTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry)); await tester.pump(); await tester.pump(); expect(find.text(_strings.doctorDetailNotFoundTitle), findsOneWidget); expect(api.calls, hasLength(2));
  });

  testWidgets('Book Appointment and key section headings localize, backend doctor name stays data-driven', (tester) async {
    final api = _DetailApi()
      ..details.add(
        Future.value(
          const DoctorDetailResponse(
            doctor: Doctor(id: 'd1', firstNameAr: 'مريم', lastNameAr: 'صالح', specialtyAr: 'طب الأسرة'),
          ),
        ),
      );
    await tester.pumpWidget(_app(api, isArabic: true));
    await tester.pump();
    await tester.pump();

    expect(find.text(_arStrings.bookNewAppointment), findsOneWidget);
    expect(find.text(_arStrings.doctorDetailTitle), findsOneWidget);
    expect(find.text(_arStrings.doctorSectionEducation), findsOneWidget);
    expect(find.text(_arStrings.doctorSectionAssociatedClinics), findsOneWidget);
    expect(find.text(_arStrings.doctorSectionReviews), findsOneWidget);
    // Backend-provided doctor name is never translated locally — it renders
    // verbatim from the Arabic name field the API returned.
    expect(find.text('مريم صالح'), findsOneWidget);
  });

  testWidgets('accepting patients drives the booking CTA across all three states', (tester) async {
    Future<void> pumpFor(bool? accepting) async {
      final api = _DetailApi()
        ..details.add(Future.value(DoctorDetailResponse(
          doctor: Doctor(id: 'd1', firstNameEn: 'A', isAcceptingPatients: accepting),
        )));
      await tester.pumpWidget(_app(api));
      await tester.pump();
      await tester.pump();
    }

    await pumpFor(true);
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, _strings.bookNewAppointment)).enabled,
      isTrue,
    );
    expect(find.text(_strings.doctorBookingUnavailableNotAccepting), findsNothing);

    await pumpFor(false);
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, _strings.bookNewAppointment)).enabled,
      isFalse,
    );
    expect(find.text(_strings.doctorBookingUnavailableNotAccepting), findsOneWidget);

    await pumpFor(null);
    expect(
      tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, _strings.bookNewAppointment)).enabled,
      isFalse,
    );
    expect(find.text(_strings.doctorBookingUnavailableUnknown), findsOneWidget);
    // `false` is never shown as `unknown`.
    expect(find.text(_strings.doctorBookingUnavailableNotAccepting), findsNothing);
  });

  testWidgets('review body and reviewer name come straight from backend fields', (tester) async {
    final api = _DetailApi()
      ..details.add(Future.value(const DoctorDetailResponse(
        doctor: Doctor(id: 'd1', firstNameEn: 'A'),
        reviews: [
          DoctorReview(id: 'r1', rating: 4, reviewTextEn: 'Very thorough', patientFirstNameEn: 'Huda'),
        ],
      )));
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();

    expect(find.text('Very thorough'), findsOneWidget);
    expect(find.text('Huda'), findsOneWidget);
  });

  testWidgets('switching to another doctor never shows the first doctor briefly', (tester) async {
    final api = _DetailApi()
      ..details.add(Future.value(const DoctorDetailResponse(doctor: Doctor(id: 'd1', firstNameEn: 'First'))));
    final pendingB = Completer<DoctorDetailResponse>();
    api.details.add(pendingB.future);

    final container = ProviderContainer(overrides: [
      discoveryApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
    ]);
    addTearDown(container.dispose);

    Widget host(String id) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: DoctorDetailScreen(doctorId: id),
            ),
          ),
        );

    await tester.pumpWidget(host('d1'));
    await tester.pump();
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    await tester.pumpWidget(host('d2'));
    await tester.pump();
    // Doctor B is still loading — Doctor A's name must not be on screen.
    expect(find.text('First'), findsNothing);
    expect(find.text(_strings.doctorLoadingDetails), findsOneWidget);

    pendingB.complete(const DoctorDetailResponse(doctor: Doctor(id: 'd2', firstNameEn: 'Second')));
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets(
      'stacked Doctor A / Doctor B routes: hidden A never re-fetches, no ping-pong, call sequence is A, B, A',
      (tester) async {
    final api = _DetailApi()
      ..details.add(Future.value(const DoctorDetailResponse(doctor: Doctor(id: 'A', firstNameEn: 'Alice'))));
    final pendingB = Completer<DoctorDetailResponse>();
    api.details.add(pendingB.future);
    api.details.add(Future.value(const DoctorDetailResponse(doctor: Doctor(id: 'A', firstNameEn: 'Alice'))));

    final container = ProviderContainer(overrides: [
      discoveryApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
    ]);
    addTearDown(container.dispose);
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: navKey,
        theme: AppTheme.light(),
        home: const Directionality(
          textDirection: TextDirection.ltr,
          child: DoctorDetailScreen(doctorId: 'A'),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(api.calls, ['A']);

    // Push Doctor B on top; Doctor A stays mounted underneath.
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Directionality(
        textDirection: TextDirection.ltr,
        child: DoctorDetailScreen(doctorId: 'B'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();

    // B owns the shared slice and is loading; hidden A must not have re-fetched.
    expect(container.read(discoveryControllerProvider).selectedDoctorId, 'B');
    expect(api.calls, ['A', 'B']);
    // A few more frames prove there is no A/B ownership ping-pong.
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['A', 'B']);

    pendingB.complete(const DoctorDetailResponse(doctor: Doctor(id: 'B', firstNameEn: 'Bob')));
    await tester.pump();
    expect(find.text('Bob'), findsOneWidget);

    // Pop B — A becomes current again and reloads exactly once.
    navKey.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();

    expect(api.calls, ['A', 'B', 'A']);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
    final state = container.read(discoveryControllerProvider);
    expect(state.selectedDoctorId, 'A');
    expect(state.selectedDoctorDetail?.doctor?.id, 'A');

    // Settle — no further looped calls.
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['A', 'B', 'A']);
  });
}
Widget _app(_DetailApi api, {bool isArabic = false}) => ProviderScope(
      overrides: [
        discoveryApiProvider.overrideWithValue(api),
        secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
      ],
      child: MaterialApp(
        theme: AppTheme.light(isArabic: isArabic),
        home: Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: const DoctorDetailScreen(doctorId: 'd1'),
        ),
      ),
    );
class _DetailApi extends DiscoveryApi {
  _DetailApi() : super(Dio());
  final details = <Future<DoctorDetailResponse>>[];
  final failures = <Object>[];
  final calls = <String>[];
  final availabilityById = <String, DoctorAvailabilityResponse>{};
  final availabilityCalls = <String>[];
  @override
  Future<DoctorDetailResponse> getDoctor(String id) {
    calls.add(id);
    if (failures.isNotEmpty) return Future.error(failures.removeAt(0));
    return details.removeAt(0);
  }

  @override
  Future<DoctorAvailabilityResponse> getDoctorAvailability(String id, {String? date}) async {
    availabilityCalls.add(id);
    return availabilityById[id] ?? const DoctorAvailabilityResponse();
  }
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

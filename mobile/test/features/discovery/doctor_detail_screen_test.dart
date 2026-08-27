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
class _DetailApi extends DiscoveryApi { _DetailApi() : super(Dio()); final details = <Future<DoctorDetailResponse>>[]; final failures = <Object>[]; final calls = <String>[];
  @override Future<DoctorDetailResponse> getDoctor(String id) { calls.add(id); if (failures.isNotEmpty) return Future.error(failures.removeAt(0)); return details.removeAt(0); }
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

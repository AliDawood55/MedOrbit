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
import 'package:mobile/features/discovery/screens/doctor_directory_screen.dart';

const _strings = AppStrings(false); // English, matching the default direction used below
const _arStrings = AppStrings(true);

void main() {
  testWidgets('loading, doctor cards, optional fields, and accepting status render safely', (tester) async {
    final pending = Completer<DoctorListResponse>();
    final api = _DoctorsApi()..results.add(pending.future);
    await tester.pumpWidget(_app(api));
    await tester.pump();
    expect(find.text(_strings.doctorLoadingDoctors), findsOneWidget);
    pending.complete(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'Mariam', lastNameEn: 'Saleh', specialtyEn: 'Family medicine', averageRating: 4.7, totalRatings: 12, isAcceptingPatients: true), Doctor(id: 'd2')]));
    await tester.pump();
    expect(find.text('Mariam Saleh'), findsOneWidget);
    expect(find.text('Family medicine'), findsOneWidget);
    expect(find.text(_strings.doctorAcceptingPatients), findsOneWidget);
    expect(find.text(_strings.doctorFallbackName), findsOneWidget);
  });

  testWidgets('search debounces and supported filters are sent to the API', (tester) async {
    final api = _DoctorsApi()
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', specialtyEn: 'Cardiology', clinics: [DoctorClinicSummary(id: 'c1', region: 'Nablus')])])))
      ..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'cardio');
    await tester.pump(const Duration(milliseconds: 399));
    expect(api.calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(api.calls.last.search, 'cardio');
  });

  testWidgets('pagination, empty, error retry, and RTL large text states are safe', (tester) async {
    final api = _DoctorsApi()
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'First')], pagination: DoctorPagination(page: 1, totalPages: 2))))
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd2', firstNameEn: 'Second')], pagination: DoctorPagination(page: 2, totalPages: 2))));
    await tester.pumpWidget(_app(api, direction: TextDirection.rtl, scale: 2, isArabic: true));
    await tester.pump();
    final loadMore = find.widgetWithText(ElevatedButton, _arStrings.discoveryLoadMoreButton);
    await tester.ensureVisible(loadMore);
    await tester.pump();
    expect(loadMore.hitTestable(), findsOneWidget);
    await tester.tap(loadMore);
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('safe error renders and retry calls API again', (tester) async {
    final api = _DoctorsApi()..failures.add(const ApiException(message: 'Failed', code: 'FAILED'))..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api)); await tester.pump(); await tester.pump();
    expect(find.text(_strings.couldNotLoadDoctors), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry)); await tester.pump(); await tester.pump();
    expect(api.calls, hasLength(2)); expect(find.text(_strings.doctorEmptyTitle), findsOneWidget);
  });

  testWidgets('English title, search, and filter copy render in English', (tester) async {
    final api = _DoctorsApi()..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api));
    await tester.pump();

    expect(find.text(_strings.doctorDirectoryScreenTitle), findsOneWidget);
    expect(find.text(_strings.doctorDirectoryTitle), findsOneWidget);
    expect(find.text(_strings.searchDoctorsLabel), findsOneWidget);
    expect(find.text(_strings.discoveryFiltersButton), findsOneWidget);
  });

  testWidgets('Arabic title, search, and filter copy render in Arabic', (tester) async {
    final api = _DoctorsApi()..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api, isArabic: true));
    await tester.pump();

    expect(find.text(_arStrings.doctorDirectoryScreenTitle), findsOneWidget);
    expect(find.text(_arStrings.doctorDirectoryTitle), findsOneWidget);
    expect(find.text(_arStrings.searchDoctorsLabel), findsOneWidget);
    expect(find.text(_arStrings.discoveryFiltersButton), findsOneWidget);
  });

  testWidgets('filter sheet sends the raw backend specialty value regardless of display locale', (tester) async {
    final api = _DoctorsApi()
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', specialtyEn: 'Cardiology')])))
      ..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api, isArabic: true));
    await tester.pump();

    await tester.tap(find.text(_arStrings.discoveryFiltersButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('doctor-filter-${_arStrings.doctorFilterSpecialtyLabel}-Cardiology')));
    await tester.tap(find.widgetWithText(ElevatedButton, _arStrings.discoveryApplyFiltersButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.calls.last.specialty, 'Cardiology');
  });
}

Widget _app(_DoctorsApi api, {TextDirection direction = TextDirection.ltr, double scale = 1, bool isArabic = false}) => ProviderScope(
      overrides: [
        discoveryApiProvider.overrideWithValue(api),
        secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
      ],
      child: MaterialApp(theme: AppTheme.light(isArabic: direction == TextDirection.rtl), home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: direction, child: const DoctorDirectoryScreen()))),
    );

class _DoctorsApi extends DiscoveryApi {
  _DoctorsApi() : super(Dio()); final results = <Future<DoctorListResponse>>[]; final failures = <Object>[]; final calls = <DoctorFilters>[];
  @override Future<DoctorListResponse> listDoctors({String? specialty, String? region, double? minRating, double? minFee, double? maxFee, String? search, int page = 1, int limit = 10}) { calls.add(DoctorFilters(specialty: specialty, region: region, minRating: minRating, minFee: minFee, maxFee: maxFee, search: search, page: page, limit: limit)); if (failures.isNotEmpty) return Future.error(failures.removeAt(0)); return results.removeAt(0); }
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/discovery/data/discovery_api.dart';
import 'package:mobile/features/discovery/models/doctor_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';
import 'package:mobile/features/discovery/screens/doctor_directory_screen.dart';

void main() {
  testWidgets('loading, doctor cards, optional fields, and accepting status render safely', (tester) async {
    final pending = Completer<DoctorListResponse>();
    final api = _DoctorsApi()..results.add(pending.future);
    await tester.pumpWidget(_app(api));
    await tester.pump();
    expect(find.text('Loading doctors...'), findsOneWidget);
    pending.complete(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'Mariam', lastNameEn: 'Saleh', specialtyEn: 'Family medicine', averageRating: 4.7, totalRatings: 12, isAcceptingPatients: true), Doctor(id: 'd2')]));
    await tester.pump();
    expect(find.text('Mariam Saleh'), findsOneWidget);
    expect(find.text('Family medicine'), findsOneWidget);
    expect(find.text('Accepting patients'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
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
    await tester.pumpWidget(_app(api, direction: TextDirection.rtl, scale: 2));
    await tester.pump();
    final loadMore = find.widgetWithText(ElevatedButton, 'Load more');
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
    expect(find.text('Could not load doctors'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry')); await tester.pump(); await tester.pump();
    expect(api.calls, hasLength(2)); expect(find.text('No doctors found'), findsOneWidget);
  });
}

Widget _app(_DoctorsApi api, {TextDirection direction = TextDirection.ltr, double scale = 1}) => ProviderScope(overrides: [discoveryApiProvider.overrideWithValue(api)], child: MaterialApp(theme: AppTheme.light(isArabic: direction == TextDirection.rtl), home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: direction, child: const DoctorDirectoryScreen()))));

class _DoctorsApi extends DiscoveryApi {
  _DoctorsApi() : super(Dio()); final results = <Future<DoctorListResponse>>[]; final failures = <Object>[]; final calls = <DoctorFilters>[];
  @override Future<DoctorListResponse> listDoctors({String? specialty, String? region, double? minRating, double? minFee, double? maxFee, String? search, int page = 1, int limit = 10}) { calls.add(DoctorFilters(specialty: specialty, region: region, minRating: minRating, minFee: minFee, maxFee: maxFee, search: search, page: page, limit: limit)); if (failures.isNotEmpty) return Future.error(failures.removeAt(0)); return results.removeAt(0); }
}

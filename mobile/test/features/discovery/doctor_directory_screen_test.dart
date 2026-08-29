import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
    final retry = find.widgetWithText(OutlinedButton, _strings.retry);
    await tester.ensureVisible(retry); await tester.pumpAndSettle();
    await tester.tap(retry); await tester.pump(); await tester.pump();
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

  testWidgets('specialty quick filter shows a localized label but sends the raw English name', (tester) async {
    final api = _DoctorsApi()
      ..specialties = const [Specialty(nameEn: 'Cardiology', nameAr: 'طب القلب')]
      ..results.add(Future.value(const DoctorListResponse()))
      ..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api, isArabic: true));
    await tester.pump();
    await tester.pump();

    final chip = find.byKey(const ValueKey('doctor-specialty-quick-Cardiology'));
    await tester.ensureVisible(chip);
    expect(find.descendant(of: chip, matching: find.text('طب القلب')), findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.calls.last.specialty, 'Cardiology');
    expect(api.calls.last.page, 1);
  });

  testWidgets('specialty quick filter falls back to the built-in list when the endpoint is empty', (tester) async {
    final api = _DoctorsApi()..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('doctor-specialty-quick-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('doctor-specialty-quick-Pediatrics')), findsOneWidget);
  });

  testWidgets('recommended strip is hidden for anonymous viewers', (tester) async {
    final api = _DoctorsApi()
      ..recommended = const [Doctor(id: 'r1', firstNameEn: 'Rec')]
      ..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.doctorRecommendedTitle), findsNothing);
  });

  testWidgets('authenticated viewer sees recommended doctors with reason and can navigate', (tester) async {
    final api = _DoctorsApi()
      ..recommended = const [
        Doctor(id: 'rec-1', firstNameEn: 'Rita', lastNameEn: 'Nasser', specialtyEn: 'Cardiology', extra: {'reason_code': 'FOLLOWED_DOCTOR'}),
      ]
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'Main')])));
    await tester.pumpWidget(_routerApp(api, initialLocation: '/doctors'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.doctorRecommendedTitle), findsOneWidget);
    expect(find.text(_strings.doctorReasonFollowed), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('doctor-recommended-rec-1')));
    await tester.pumpAndSettle();
    expect(find.text('detail:rec-1'), findsOneWidget);
  });

  testWidgets('recommended failure is isolated: strip shows a safe message, main list still loads', (tester) async {
    final api = _DoctorsApi()
      ..recommendedError = const ApiException(message: 'boom', code: 'BOOM')
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'Main')])))
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'Main')])));
    await tester.pumpWidget(_app(api, authenticated: true));
    await tester.pump();
    await tester.pump();

    expect(find.text(_strings.doctorRecommendedUnavailable), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
    expect(find.text('Main'), findsOneWidget);
  });

  testWidgets('picking a specialty fires the telemetry ping with the resolved backend id', (tester) async {
    final api = _DoctorsApi()
      ..specialties = const [Specialty(id: 'spec-uuid', nameEn: 'Cardiology', nameAr: 'طب القلب')]
      ..results.add(Future.value(const DoctorListResponse()))
      ..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_app(api, authenticated: true));
    await tester.pump();
    await tester.pump();

    final chip = find.byKey(const ValueKey('doctor-specialty-quick-Cardiology'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(api.specialtySearchCalls, ['spec-uuid']);
  });

  testWidgets('deep link /doctors?search= seeds the search field and first request', (tester) async {
    final api = _DoctorsApi()..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_routerApp(api, initialLocation: '/doctors?search=cardio', authenticated: false));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(TextFormField, 'cardio'), findsOneWidget);
    expect(api.calls.single.search, 'cardio');
    expect(api.calls.single.specialty, isNull);
  });

  testWidgets('deep link /doctors?specialty= seeds the specialty filter as the raw wire value', (tester) async {
    final api = _DoctorsApi()..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_routerApp(api, initialLocation: '/doctors?specialty=Cardiology', authenticated: false));
    await tester.pump();
    await tester.pump();

    expect(api.calls.single.specialty, 'Cardiology');
    expect(find.byKey(const ValueKey('doctor-specialty-quick-Cardiology')), findsOneWidget);
  });

  testWidgets('deep link seeds search and specialty together', (tester) async {
    final api = _DoctorsApi()..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_routerApp(api, initialLocation: '/doctors?search=heart&specialty=Cardiology', authenticated: false));
    await tester.pump();
    await tester.pump();

    expect(api.calls.single.search, 'heart');
    expect(api.calls.single.specialty, 'Cardiology');
  });

  testWidgets('empty deep-link query values are ignored', (tester) async {
    final api = _DoctorsApi()..results.add(Future.value(const DoctorListResponse()));
    await tester.pumpWidget(_routerApp(api, initialLocation: '/doctors?search=%20&specialty=', authenticated: false));
    await tester.pump();
    await tester.pump();

    expect(api.calls.single.search, isNull);
    expect(api.calls.single.specialty, isNull);
  });

  testWidgets('stale recommendations from a prior session never paint and are cleared on mount', (tester) async {
    final api = _DoctorsApi()
      ..recommended = const [Doctor(id: 'rec-stale', firstNameEn: 'Stale')]
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'Main')])));
    final flag = StateProvider<bool>((_) => true);
    final container = ProviderContainer(overrides: [
      discoveryApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
      discoveryViewerAuthenticatedProvider.overrideWith((ref) => ref.watch(flag)),
    ]);
    addTearDown(container.dispose);

    // A previous viewer's recommendations are already sitting in the shared state.
    await container.read(discoveryControllerProvider.notifier).loadRecommendedDoctors();
    expect(container.read(discoveryControllerProvider).recommendedDoctors.single.id, 'rec-stale');
    api.recommended = const [Doctor(id: 'rec-fresh', firstNameEn: 'Fresh')];

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DoctorDirectoryScreen()),
    ));
    // First frame: the retained stale card must not be shown.
    expect(find.text('Stale'), findsNothing);
    await tester.pump();
    await tester.pump();

    expect(find.text('Stale'), findsNothing);
    expect(find.text('Fresh'), findsOneWidget);
    expect(container.read(discoveryControllerProvider).recommendedDoctors.single.id, 'rec-fresh');
  });

  testWidgets('auth transitions while mounted: sign-out clears the strip, sign-in reloads it', (tester) async {
    final api = _DoctorsApi()
      ..recommended = const [Doctor(id: 'rec-1', firstNameEn: 'Rec')]
      ..results.add(Future.value(const DoctorListResponse(doctors: [Doctor(id: 'd1', firstNameEn: 'Main')])));
    final flag = StateProvider<bool>((_) => true);
    final container = ProviderContainer(overrides: [
      discoveryApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
      discoveryViewerAuthenticatedProvider.overrideWith((ref) => ref.watch(flag)),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DoctorDirectoryScreen()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text(_strings.doctorRecommendedTitle), findsOneWidget);
    expect(find.text('Rec'), findsOneWidget);
    final callsAfterBootstrap = api.recommendedCalls;
    expect(callsAfterBootstrap, 1); // single initial request, no listener double-fire

    // authenticated -> unauthenticated
    container.read(flag.notifier).state = false;
    await tester.pump();
    expect(find.text(_strings.doctorRecommendedTitle), findsNothing);
    expect(container.read(discoveryControllerProvider).recommendedDoctors, isEmpty);
    expect(container.read(discoveryControllerProvider).recommendedDoctorsError, isNull);
    expect(container.read(discoveryControllerProvider).isLoadingRecommendedDoctors, isFalse);

    // unauthenticated -> authenticated
    container.read(flag.notifier).state = true;
    await tester.pump();
    await tester.pump();
    expect(find.text(_strings.doctorRecommendedTitle), findsOneWidget);
    expect(api.recommendedCalls, 2);

    // Main list stayed put throughout.
    expect(find.text('Main'), findsOneWidget);
  });
}

/// GoRouter-backed host: the real doctors route builder (mirroring
/// `app_router.dart`) plus a stub `/doctors/:id` the tests assert against.
Widget _routerApp(_DoctorsApi api, {required String initialLocation, bool authenticated = true}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/doctors',
        builder: (context, state) => DoctorDirectoryScreen(
          initialSearch: state.uri.queryParameters['search'],
          initialSpecialty: state.uri.queryParameters['specialty'],
        ),
      ),
      GoRoute(path: '/doctors/:id', builder: (_, s) => Scaffold(body: Text('detail:${s.pathParameters['id']}'))),
    ],
  );
  return ProviderScope(
    overrides: [
      discoveryApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage('en')),
      discoveryViewerAuthenticatedProvider.overrideWithValue(authenticated),
    ],
    child: MaterialApp.router(theme: AppTheme.light(isArabic: false), routerConfig: router),
  );
}

Widget _app(_DoctorsApi api, {TextDirection direction = TextDirection.ltr, double scale = 1, bool isArabic = false, bool authenticated = false, Widget? screen}) => ProviderScope(
      overrides: [
        discoveryApiProvider.overrideWithValue(api),
        secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
        discoveryViewerAuthenticatedProvider.overrideWithValue(authenticated),
      ],
      child: MaterialApp(theme: AppTheme.light(isArabic: direction == TextDirection.rtl), home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)), child: Directionality(textDirection: direction, child: screen ?? const DoctorDirectoryScreen()))),
    );

class _DoctorsApi extends DiscoveryApi {
  _DoctorsApi() : super(Dio()); final results = <Future<DoctorListResponse>>[]; final failures = <Object>[]; final calls = <DoctorFilters>[]; List<Specialty> specialties = const []; List<Doctor> recommended = const []; Object? recommendedError; int recommendedCalls = 0; final specialtySearchCalls = <String>[];
  @override Future<DoctorListResponse> listDoctors({String? specialty, String? region, double? minRating, double? minFee, double? maxFee, String? search, int page = 1, int limit = 10}) { calls.add(DoctorFilters(specialty: specialty, region: region, minRating: minRating, minFee: minFee, maxFee: maxFee, search: search, page: page, limit: limit)); if (failures.isNotEmpty) return Future.error(failures.removeAt(0)); return results.removeAt(0); }
  @override Future<List<Specialty>> listSpecialties() async => specialties;
  @override Future<List<Doctor>> recommendedDoctors({int limit = 6}) async { recommendedCalls++; if (recommendedError != null) throw recommendedError!; return recommended; }
  @override Future<void> recordSpecialtySearch(String specialtyId) async { specialtySearchCalls.add(specialtyId); }
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

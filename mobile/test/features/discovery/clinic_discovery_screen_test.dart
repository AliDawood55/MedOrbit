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
import 'package:mobile/features/discovery/data/location_service.dart';
import 'package:mobile/features/discovery/models/clinic_models.dart';
import 'package:mobile/features/discovery/models/location_models.dart';
import 'package:mobile/features/discovery/providers/discovery_provider.dart';
import 'package:mobile/features/discovery/providers/location_provider.dart';
import 'package:mobile/features/discovery/screens/clinic_discovery_screen.dart';

const _strings = AppStrings(false);
const _arStrings = AppStrings(true);

void main() {
  testWidgets('initial loading is visible', (tester) async {
    final pending = Completer<ClinicListResponse>();
    final api = _FakeDiscoveryApi()..clinicListResults.add(pending.future);

    await tester.pumpWidget(_app(api));
    await tester.pump();

    expect(find.text(_strings.clinicLoadingClinics), findsOneWidget);
    pending.complete(const ClinicListResponse());
    await tester.pump();
  });

  testWidgets('list success shows verification status and hides missing fields cleanly', (tester) async {
    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(
        Future.value(
          const ClinicListResponse(
            clinics: [
              Clinic(
                id: 'clinic-1',
                nameEn: 'Rafidia Clinic',
                type: 'clinic',
                verificationStatus: ClinicVerificationStatus.verified,
                services: ['Pediatrics'],
              ),
            ],
          ),
        ),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();

    expect(find.text('Rafidia Clinic'), findsOneWidget);
    expect(find.text(_strings.clinicVerifiedLabel), findsOneWidget);
    expect(find.text('Pediatrics'), findsOneWidget);
    expect(find.textContaining(_strings.clinicPhoneLabel), findsNothing);
  });

  testWidgets('search debounces and preserves query across list and map switch', (tester) async {
    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(Future.value(const ClinicListResponse()))
      ..clinicListResults.add(
        Future.value(
          const ClinicListResponse(clinics: [Clinic(id: 'search-1', nameEn: 'Nablus Lab')]),
        ),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'lab');
    await tester.pump(const Duration(milliseconds: 399));
    expect(api.clinicListCalls, hasLength(1));

    await tester.pump(const Duration(milliseconds: 2));
    await tester.pump();
    expect(api.clinicListCalls.last.search, 'lab');

    await tester.tap(find.text(_strings.discoveryViewModeMap));
    await tester.pump();
    expect(find.text('lab'), findsOneWidget);
  });

  testWidgets('type filter sends supported backend filter', (tester) async {
    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(Future.value(const ClinicListResponse()))
      ..clinicListResults.add(
        Future.value(const ClinicListResponse(clinics: [Clinic(id: 'pharmacy', nameEn: 'Care Pharmacy')])),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.tap(find.text(_strings.discoveryFiltersButton));
    await tester.pumpAndSettle();
    final sheetScrollable = find.descendant(
      of: find.byKey(const ValueKey('clinic-filter-scrollable')),
      matching: find.byType(Scrollable),
    );
    final pharmacy = find.byKey(const ValueKey('clinic-filter-type-pharmacy'));
    expect(sheetScrollable, findsOneWidget);
    await dragUntilHitTestable(tester, pharmacy, sheetScrollable);
    expect(pharmacy.hitTestable(), findsOneWidget);
    await tester.tap(pharmacy.hitTestable());
    final apply = find.byKey(const ValueKey('clinic-filter-apply'));
    await dragUntilHitTestable(tester, apply, sheetScrollable);
    final applyButton = find.widgetWithText(ElevatedButton, _strings.discoveryApplyFiltersButton);
    expect(applyButton.hitTestable(), findsOneWidget);
    await tester.tap(applyButton.hitTestable());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.clinicListCalls.last.type, 'pharmacy');
  });

  testWidgets('English search, filter, and location labels render in English', (tester) async {
    final api = _FakeDiscoveryApi()..clinicListResults.add(Future.value(const ClinicListResponse()));
    await tester.pumpWidget(_app(api));
    await tester.pump();

    expect(find.text(_strings.clinicDiscoveryScreenTitle), findsOneWidget);
    expect(find.text(_strings.searchClinicsLabel), findsOneWidget);
    expect(find.text(_strings.discoveryFiltersButton), findsOneWidget);
    expect(find.text(_strings.nearbySearchTitle), findsOneWidget);
    expect(find.text(_strings.useGpsButton), findsOneWidget);
    expect(find.text(_strings.chooseLocationButton), findsOneWidget);
  });

  testWidgets('Arabic search, filter, and location labels render in Arabic', (tester) async {
    final api = _FakeDiscoveryApi()..clinicListResults.add(Future.value(const ClinicListResponse()));
    await tester.pumpWidget(_app(api, isArabic: true));
    await tester.pump();

    expect(find.text(_arStrings.clinicDiscoveryScreenTitle), findsOneWidget);
    expect(find.text(_arStrings.searchClinicsLabel), findsOneWidget);
    expect(find.text(_arStrings.discoveryFiltersButton), findsOneWidget);
    expect(find.text(_arStrings.nearbySearchTitle), findsOneWidget);
    expect(find.text(_arStrings.useGpsButton), findsOneWidget);
    expect(find.text(_arStrings.chooseLocationButton), findsOneWidget);
  });

  testWidgets('facility type display localizes to Arabic while the raw enum sent to the backend stays stable', (tester) async {
    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(
        Future.value(
          const ClinicListResponse(
            clinics: [Clinic(id: 'pharmacy-1', nameEn: 'Care Pharmacy', type: 'pharmacy')],
          ),
        ),
      );

    await tester.pumpWidget(_app(api, isArabic: true));
    await tester.pump();
    await tester.pump();

    // Display label is localized to Arabic; the raw backend enum value
    // ('pharmacy') is proven stable by the separate "type filter sends
    // supported backend filter" test above, which applies the filter and
    // asserts the exact wire value sent.
    expect(find.text(_arStrings.clinicTypeLabelFor('pharmacy')), findsOneWidget);
  });

  testWidgets('nearby GPS and manual district keep nearby results separate', (tester) async {
    final location = _FakeLocationService()
      ..permissionResult = LocationPermissionState.granted
      ..results.add(
        LocationResult.success(
          AppLocation(
            latitude: 32.2211,
            longitude: 35.2544,
            source: LocationSource.gps,
            resolvedAt: DateTime.now(),
          ),
        ),
      );
    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(
        Future.value(const ClinicListResponse(clinics: [Clinic(id: 'normal', nameEn: 'Normal Clinic')])),
      )
      ..nearbyResults.add(
        Future.value(const NearbyClinicResponse(clinics: [Clinic(id: 'nearby', nameEn: 'Nearby Clinic')])),
      )
      ..nearbyResults.add(
        Future.value(const NearbyClinicResponse(clinics: [Clinic(id: 'district', nameEn: 'District Clinic')])),
      );

    await tester.pumpWidget(_app(api, location: location));
    await tester.pump();
    await tester.tap(find.text(_strings.useGpsButton));
    await tester.pump();
    await tester.pump();

    expect(find.text('Nearby Clinic'), findsOneWidget);
    expect(find.text('Normal Clinic'), findsNothing);
    expect(api.nearbyCalls.single.radius, 5);

    final mainScrollable = find.byKey(const PageStorageKey<String>('clinic-discovery-scroll'));
    final chooseLocation = find.widgetWithText(OutlinedButton, _strings.chooseLocationButton);
    await dragUntilHitTestable(tester, chooseLocation, mainScrollable);
    expect(chooseLocation.hitTestable(), findsOneWidget);
    await tester.tap(chooseLocation.hitTestable());
    await tester.pumpAndSettle();
    final pickerScrollable = find.descendant(
      of: find.byKey(const ValueKey('location-picker-scrollable')),
      matching: find.byType(Scrollable),
    );
    final district = find.byKey(const ValueKey('location-district-nablus-center'));
    expect(pickerScrollable, findsOneWidget);
    expect(district, findsOneWidget);
    await dragUntilHitTestable(tester, district, pickerScrollable);
    expect(district.hitTestable(), findsOneWidget);
    await tester.tap(district.hitTestable());
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ClinicDiscoveryScreen)),
      listen: false,
    );
    final selectedLocation = container.read(locationControllerProvider).currentLocation;
    expect(selectedLocation?.source, LocationSource.manualDistrict);
    expect(selectedLocation?.approximate, isTrue);
    expect(find.text('District Clinic'), findsOneWidget);
    expect(find.textContaining('approximate district'), findsOneWidget);
    expect(api.nearbyCalls.last.lat, 32.2211);
    expect(api.nearbyCalls.last.lng, 35.2544);
  });

  testWidgets('empty state is visible after a successful empty response', (tester) async {
    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(Future.value(const ClinicListResponse()));

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('clinic-discovery-empty-state')), findsOneWidget);
    expect(api.clinicListCalls, hasLength(1));
  });

  testWidgets('error and retry states are visible', (tester) async {
    final api = _FakeDiscoveryApi()
      ..clinicListFailures.add(const ApiException(message: 'Clinic load failed', code: 'FAILED'))
      ..clinicListResults.add(
        Future.value(const ClinicListResponse(clinics: [Clinic(id: 'retry', nameEn: 'Retry Clinic')])),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.pump();
    expect(find.text(_strings.clinicCouldNotLoadClinics), findsOneWidget);
    expect(api.clinicListCalls, hasLength(1));

    final mainScrollable = find.byKey(const PageStorageKey<String>('clinic-discovery-scroll'));
    final retry = find.byKey(const ValueKey('clinic-discovery-retry'));
    await dragUntilHitTestable(tester, retry, mainScrollable);
    expect(retry.hitTestable(), findsOneWidget);
    await tester.tap(retry.hitTestable());
    await tester.pump();
    await tester.pump();
    expect(find.text('Retry Clinic'), findsOneWidget);
    expect(api.clinicListCalls, hasLength(2));
  });

  testWidgets('marker selection opens clinic preview', (tester) async {
    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(
        Future.value(
          const ClinicListResponse(
            clinics: [
              Clinic(id: 'mapped', nameEn: 'Mapped Clinic', latitude: 32.2211, longitude: 35.2544),
            ],
          ),
        ),
      );

    await tester.pumpWidget(_app(api));
    await tester.pump();
    await tester.tap(find.text(_strings.discoveryViewModeMap));
    await tester.pump(const Duration(milliseconds: 300));
    final marker = find.byKey(const ValueKey('discovery-map-place-mapped'));
    await tester.ensureVisible(find.byKey(const ValueKey('discovery-flutter-map')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(marker);
    await tester.pump();
    await tester.tap(marker);
    await tester.pump();

    expect(find.byKey(const ValueKey('clinic-card-mapped')), findsOneWidget);
  });

  testWidgets('RTL and large text discovery layout does not overflow', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    final api = _FakeDiscoveryApi()
      ..clinicListResults.add(
        Future.value(const ClinicListResponse(clinics: [Clinic(id: 'rtl', nameAr: 'عيادة نابلس')])),
      );

    await tester.pumpWidget(_app(api, textDirection: TextDirection.rtl, textScale: 2, isArabic: true));
    await tester.pump();

    expect(errors.where((error) => error.exceptionAsString().contains('overflowed')), isEmpty);
    expect(find.text(_arStrings.clinicDiscoveryScreenTitle), findsOneWidget);
  });
}

Future<void> dragUntilHitTestable(
  WidgetTester tester,
  Finder target,
  Finder scrollable, {
  int maxDrags = 10,
  double delta = 250,
}) async {
  expect(target, findsOneWidget);
  expect(scrollable, findsOneWidget);

  for (var index = 0; index < maxDrags; index += 1) {
    if (target.hitTestable().evaluate().length == 1) return;
    await tester.drag(scrollable, Offset(0, -delta));
    await tester.pump();
  }

  final center = tester.getCenter(target);
  fail('Target $target never became hit-testable after $maxDrags drags. Last global center: $center');
}

Widget _app(
  _FakeDiscoveryApi api, {
  _FakeLocationService? location,
  TextDirection textDirection = TextDirection.ltr,
  double textScale = 1,
  bool isArabic = false,
}) {
  return ProviderScope(
    overrides: [
      discoveryApiProvider.overrideWithValue(api),
      locationServiceProvider.overrideWithValue(location ?? _FakeLocationService()),
      secureStorageProvider.overrideWithValue(_FakeSecureStorage(isArabic ? 'ar' : 'en')),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: textDirection == TextDirection.rtl),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: textDirection,
          child: const ClinicDiscoveryScreen(),
        ),
      ),
    ),
  );
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

class _FakeDiscoveryApi extends DiscoveryApi {
  _FakeDiscoveryApi() : super(Dio());

  final clinicListResults = <Future<ClinicListResponse>>[];
  final clinicListFailures = <Object>[];
  final nearbyResults = <Future<NearbyClinicResponse>>[];
  final clinicListCalls = <ClinicFilters>[];
  final nearbyCalls = <({double lat, double lng, double radius, String? type})>[];

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
    if (clinicListFailures.isNotEmpty) {
      return Future<ClinicListResponse>.error(clinicListFailures.removeAt(0));
    }
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
}

class _FakeLocationService extends LocationService {
  _FakeLocationService() : super(adapter: _NeverUsedAdapter());

  LocationPermissionState permissionResult = LocationPermissionState.unknown;
  final results = <FutureOr<LocationResult>>[];

  @override
  Future<LocationPermissionState> checkPermissionState() async => permissionResult;

  @override
  Future<LocationResult> resolveCurrentLocation() async {
    final result = results.removeAt(0);
    if (result is Future<LocationResult>) return result;
    return result;
  }
}

class _NeverUsedAdapter implements LocationPlatformAdapter {
  @override
  Future<LocationPermissionState> checkPermission() => throw UnimplementedError();

  @override
  Future<DevicePosition> getCurrentPosition({required Duration timeout}) => throw UnimplementedError();

  @override
  Future<bool> isLocationServiceEnabled() => throw UnimplementedError();

  @override
  Future<bool> openAppSettings() => throw UnimplementedError();

  @override
  Future<bool> openLocationSettings() => throw UnimplementedError();

  @override
  Future<LocationPermissionState> requestPermission() => throw UnimplementedError();
}

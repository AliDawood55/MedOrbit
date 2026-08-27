import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/discovery/models/location_models.dart';
import 'package:mobile/features/discovery/widgets/discovery_map.dart';
import 'package:mobile/features/discovery/widgets/location_picker_sheet.dart';
import 'package:mobile/features/discovery/widgets/place_marker.dart';

const _strings = AppStrings(false);
const _arStrings = AppStrings(true);

void main() {
  testWidgets('default Nablus center is configured', (tester) async {
    await tester.pumpWidget(_app(const DiscoveryMap()));

    final map = tester.widget<DiscoveryMap>(find.byType(DiscoveryMap));
    expect(map.initialCenter.latitude, nablusDefaultLatitude);
    expect(map.initialCenter.longitude, nablusDefaultLongitude);
    expect(map.initialZoom, 13);
  });

  testWidgets('OSM attribution is visible', (tester) async {
    await tester.pumpWidget(_sizedMap(const DiscoveryMap()));
    await tester.pump();

    expect(find.byKey(const ValueKey('osm-attribution')), findsOneWidget);
    expect(find.textContaining('OpenStreetMap'), findsOneWidget);
    expect(find.textContaining('©'), findsOneWidget);
  });

  testWidgets('marker types render safely', (tester) async {
    await tester.pumpWidget(
      _app(
        Wrap(
          children: [
            for (final type in DiscoveryPlaceType.values) PlaceMarker(type: type),
          ],
        ),
      ),
    );

    for (final type in DiscoveryPlaceType.values) {
      expect(find.byKey(ValueKey('place-marker-${type.name}')), findsOneWidget);
    }
  });

  testWidgets('user marker is distinct', (tester) async {
    await tester.pumpWidget(
      _app(
        const PlaceMarker(
          type: DiscoveryPlaceType.unknown,
          isUserLocation: true,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('user-location-marker')), findsOneWidget);
    expect(find.byIcon(Icons.my_location_rounded), findsOneWidget);
  });

  testWidgets('map tap callback receives coordinates', (tester) async {
    LatLng? tapped;
    await tester.pumpWidget(
      _sizedMap(
        DiscoveryMap(
          onMapTap: (point) => tapped = point,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final flutterMap = find.byKey(const ValueKey('discovery-flutter-map'));
    expect(flutterMap, findsOneWidget);

    final mapBox = tester.renderObject<RenderBox>(flutterMap);
    final mapCenter = mapBox.localToGlobal(mapBox.size.center(Offset.zero));
    final gesture = await tester.startGesture(mapCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tapped, isNotNull);
    expect(tapped!.latitude, inInclusiveRange(-90, 90));
    expect(tapped!.longitude, inInclusiveRange(-180, 180));
  });

  testWidgets('marker tap callback receives place', (tester) async {
    DiscoveryMapPlace? tapped;
    const place = DiscoveryMapPlace(
      id: 'clinic-1',
      latitude: 32.2211,
      longitude: 35.2544,
      type: DiscoveryPlaceType.clinic,
      label: 'Nablus Clinic',
    );
    await tester.pumpWidget(
      _sizedMap(
        DiscoveryMap(
          places: const [place],
          onPlaceTap: (place) => tapped = place,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('discovery-map-place-clinic-1')));
    await tester.pump();

    expect(tapped, same(place));
  });

  testWidgets('manual district picker labels locations as approximate', (tester) async {
    await tester.pumpWidget(
      _app(
        LocationPickerSheet(
          permissionState: LocationPermissionState.unknown,
          onUseCurrentLocation: () {},
          onSelectMapPoint: () {},
          onSelectDistrict: (_) {},
          onOpenAppSettings: () {},
          onOpenLocationSettings: () {},
          onClear: () {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Nablus City Center'), findsOneWidget);
    expect(find.textContaining('approximate'), findsWidgets);
  });

  testWidgets('manual district picker renders Arabic district names and labels in RTL', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(_FakeSecureStorage('ar'))],
        child: MaterialApp(
          theme: AppTheme.light(isArabic: true),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: LocationPickerSheet(
                permissionState: LocationPermissionState.unknown,
                onUseCurrentLocation: () {},
                onSelectMapPoint: () {},
                onSelectDistrict: (_) {},
                onOpenAppSettings: () {},
                onOpenLocationSettings: () {},
                onClear: () {},
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(_arStrings.chooseLocationTitle), findsOneWidget);
    expect(find.textContaining('مركز مدينة نابلس'), findsOneWidget);
    expect(find.textContaining(_arStrings.districtApproximateSuffix), findsWidgets);
  });

  testWidgets(
    'location failure states show distinct localized messages',
    (tester) async {
      final messages = <String, String>{};
      for (final code in const [
        'serviceDisabled',
        'denied',
        'deniedForever',
        'timeout',
        'unavailable',
        'unexpected',
      ]) {
        await tester.pumpWidget(
          _app(
            LocationPickerSheet(
              permissionState: LocationPermissionState.unknown,
              errorCode: code,
              errorMessage: 'raw_internal_code_for_$code',
              onUseCurrentLocation: () {},
              onSelectMapPoint: () {},
              onSelectDistrict: (_) {},
              onOpenAppSettings: () {},
              onOpenLocationSettings: () {},
              onClear: () {},
              onCancel: () {},
            ),
          ),
        );
        await tester.pump();

        final message = _strings.locationErrorForCode(code);
        expect(find.text(message), findsOneWidget, reason: 'no distinct message rendered for $code');
        // The raw internal failure code must never be shown to the patient.
        expect(find.textContaining('raw_internal_code_for_$code'), findsNothing);
        messages[code] = message;
      }

      // Every failure kind must render genuinely distinct text — a denied
      // permission is never confused with a service outage or a GPS timeout.
      expect(messages.values.toSet(), hasLength(messages.length));
    },
  );

  testWidgets('large text and RTL layout do not overflow', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureStorageProvider.overrideWithValue(_FakeSecureStorage('ar'))],
        child: MaterialApp(
          theme: AppTheme.light(isArabic: true),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Scaffold(
                body: LocationPickerSheet(
                  permissionState: LocationPermissionState.deniedForever,
                  errorCode: 'deniedForever',
                  errorMessage: 'location_permission_denied_forever',
                  onUseCurrentLocation: () {},
                  onSelectMapPoint: () {},
                  onSelectDistrict: (_) {},
                  onOpenAppSettings: () {},
                  onOpenLocationSettings: () {},
                  onClear: () {},
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(errors.where((error) => error.exceptionAsString().contains('overflowed')), isEmpty);
  });
}

Widget _sizedMap(Widget child) {
  return _app(
    SizedBox(
      width: 420,
      height: 420,
      child: child,
    ),
  );
}

Widget _app(Widget child) {
  return ProviderScope(
    overrides: [secureStorageProvider.overrideWithValue(_FakeSecureStorage('en'))],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: false),
      home: Scaffold(body: Center(child: child)),
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

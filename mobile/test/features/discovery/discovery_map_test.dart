import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/discovery/models/location_models.dart';
import 'package:mobile/features/discovery/widgets/discovery_map.dart';
import 'package:mobile/features/discovery/widgets/location_picker_sheet.dart';
import 'package:mobile/features/discovery/widgets/place_marker.dart';

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

    expect(find.textContaining('Nablus City Center'), findsOneWidget);
    expect(find.textContaining('approximate'), findsWidgets);
  });

  testWidgets('large text and RTL layout do not overflow', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(isArabic: true),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: LocationPickerSheet(
                permissionState: LocationPermissionState.deniedForever,
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
  return MaterialApp(
    theme: AppTheme.light(isArabic: false),
    home: Scaffold(body: Center(child: child)),
  );
}

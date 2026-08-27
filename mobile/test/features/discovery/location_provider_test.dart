import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/discovery/data/location_service.dart';
import 'package:mobile/features/discovery/models/location_models.dart';
import 'package:mobile/features/discovery/providers/location_provider.dart';

void main() {
  test('successful GPS resolution updates state', () async {
    final service = _FakeLocationService()
      ..permissionResult = LocationPermissionState.granted
      ..results.add(
        LocationResult.success(
          AppLocation(
            latitude: 32.2211,
            longitude: 35.2544,
            accuracy: 6,
            source: LocationSource.gps,
            resolvedAt: DateTime.parse('2026-08-04T10:00:00Z'),
          ),
        ),
      );
    final container = _container(service);
    addTearDown(container.dispose);

    final ok = await container
        .read(locationControllerProvider.notifier)
        .resolveCurrentLocation();
    final state = container.read(locationControllerProvider);

    expect(ok, isTrue);
    expect(state.status, LocationControllerStatus.resolved);
    expect(state.currentLocation?.source, LocationSource.gps);
    expect(state.currentLocation?.latitude, 32.2211);
  });

  test('duplicate GPS request is prevented', () async {
    final pending = Completer<LocationResult>();
    final service = _FakeLocationService()
      ..permissionResult = LocationPermissionState.granted
      ..results.add(pending.future);
    final container = _container(service);
    addTearDown(container.dispose);

    final first = container
        .read(locationControllerProvider.notifier)
        .resolveCurrentLocation();
    final second = await container
        .read(locationControllerProvider.notifier)
        .resolveCurrentLocation();

    expect(second, isFalse);
    expect(service.resolveCalls, 1);

    pending.complete(
      LocationResult.success(
        AppLocation(
          latitude: 32.2211,
          longitude: 35.2544,
          source: LocationSource.gps,
          resolvedAt: DateTime.now(),
        ),
      ),
    );
    expect(await first, isTrue);
  });

  test('stale GPS result is ignored after manual map selection', () async {
    final pending = Completer<LocationResult>();
    final service = _FakeLocationService()
      ..permissionResult = LocationPermissionState.granted
      ..results.add(pending.future);
    final container = _container(service);
    addTearDown(container.dispose);

    final gps = container
        .read(locationControllerProvider.notifier)
        .resolveCurrentLocation();
    container
        .read(locationControllerProvider.notifier)
        .selectManualMapPoint(32.2, 35.2);
    pending.complete(
      LocationResult.success(
        AppLocation(
          latitude: 32.2211,
          longitude: 35.2544,
          source: LocationSource.gps,
          resolvedAt: DateTime.now(),
        ),
      ),
    );

    expect(await gps, isFalse);
    final state = container.read(locationControllerProvider);
    expect(state.status, LocationControllerStatus.manual);
    expect(state.currentLocation?.source, LocationSource.manualMap);
    expect(state.currentLocation?.latitude, 32.2);
  });

  test('manual map selection and district selection update state', () {
    final container = _container(_FakeLocationService());
    addTearDown(container.dispose);

    container
        .read(locationControllerProvider.notifier)
        .selectManualMapPoint(32.2, 35.2);
    expect(
      container.read(locationControllerProvider).currentLocation?.source,
      LocationSource.manualMap,
    );
    expect(container.read(locationControllerProvider).isApproximate, isFalse);

    container
        .read(locationControllerProvider.notifier)
        .selectManualDistrict(manualDistrictLocations.first);
    expect(
      container.read(locationControllerProvider).currentLocation?.source,
      LocationSource.manualDistrict,
    );
    expect(container.read(locationControllerProvider).isApproximate, isTrue);
  });

  test('clear removes coordinates immediately', () {
    final container = _container(_FakeLocationService());
    addTearDown(container.dispose);

    container
        .read(locationControllerProvider.notifier)
        .selectManualMapPoint(32.2, 35.2);
    container.read(locationControllerProvider.notifier).clearLocation();

    final state = container.read(locationControllerProvider);
    expect(state.status, LocationControllerStatus.idle);
    expect(state.currentLocation, isNull);
  });

  test('retry repeats last GPS request', () async {
    final service = _FakeLocationService()
      ..permissionResult = LocationPermissionState.granted
      ..results.add(
        LocationResult.failure(
          const LocationFailure(
            code: LocationFailureCode.timeout,
            message: 'location_timeout',
          ),
        ),
      )
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
    final container = _container(service);
    addTearDown(container.dispose);

    expect(
      await container
          .read(locationControllerProvider.notifier)
          .resolveCurrentLocation(),
      isFalse,
    );
    expect(
      await container.read(locationControllerProvider.notifier).retry(),
      isTrue,
    );

    expect(service.resolveCalls, 2);
    expect(
      container.read(locationControllerProvider).status,
      LocationControllerStatus.resolved,
    );
  });

  test('no persistence is performed by provider', () {
    final service = _FakeLocationService();
    final first = _container(service);
    first
        .read(locationControllerProvider.notifier)
        .selectManualMapPoint(32.2, 35.2);
    first.dispose();

    final second = _container(service);
    addTearDown(second.dispose);

    expect(second.read(locationControllerProvider).currentLocation, isNull);
  });
}

ProviderContainer _container(LocationService service) {
  return ProviderContainer(
    overrides: [locationServiceProvider.overrideWithValue(service)],
  );
}

class _FakeLocationService extends LocationService {
  _FakeLocationService() : super(adapter: _NeverUsedAdapter());

  LocationPermissionState permissionResult = LocationPermissionState.unknown;
  final results = <FutureOr<LocationResult>>[];
  int resolveCalls = 0;

  @override
  Future<LocationPermissionState> checkPermissionState() async =>
      permissionResult;

  @override
  Future<LocationResult> resolveCurrentLocation() async {
    resolveCalls += 1;
    final result = results.removeAt(0);
    return result;
  }
}

class _NeverUsedAdapter implements LocationPlatformAdapter {
  @override
  Future<LocationPermissionState> checkPermission() =>
      throw UnimplementedError();

  @override
  Future<DevicePosition> getCurrentPosition({required Duration timeout}) =>
      throw UnimplementedError();

  @override
  Future<bool> isLocationServiceEnabled() => throw UnimplementedError();

  @override
  Future<bool> openAppSettings() => throw UnimplementedError();

  @override
  Future<bool> openLocationSettings() => throw UnimplementedError();

  @override
  Future<LocationPermissionState> requestPermission() =>
      throw UnimplementedError();
}

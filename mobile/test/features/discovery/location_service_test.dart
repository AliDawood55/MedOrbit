import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/discovery/data/location_service.dart';
import 'package:mobile/features/discovery/models/location_models.dart';

void main() {
  test('service disabled returns safe failure', () async {
    final service = LocationService(adapter: _FakeAdapter(serviceEnabled: false));

    final result = await service.resolveCurrentLocation();

    expect(result.failure?.code, LocationFailureCode.serviceDisabled);
    expect(result.failure?.permissionState, LocationPermissionState.serviceDisabled);
  });

  test('permission denied returns safe failure', () async {
    final service = LocationService(
      adapter: _FakeAdapter(
        checkedPermission: LocationPermissionState.denied,
        requestedPermission: LocationPermissionState.denied,
      ),
    );

    final result = await service.resolveCurrentLocation();

    expect(result.failure?.code, LocationFailureCode.denied);
    expect(result.failure?.message, 'location_permission_denied');
  });

  test('permission denied forever returns safe failure', () async {
    final service = LocationService(
      adapter: _FakeAdapter(checkedPermission: LocationPermissionState.deniedForever),
    );

    final result = await service.resolveCurrentLocation();

    expect(result.failure?.code, LocationFailureCode.deniedForever);
    expect(result.failure?.message, 'location_permission_denied_forever');
  });

  test('permission granted is reported by checkPermissionState', () async {
    final service = LocationService(
      adapter: _FakeAdapter(checkedPermission: LocationPermissionState.granted),
    );

    final permission = await service.checkPermissionState();

    expect(permission, LocationPermissionState.granted);
  });

  test('successful location returns GPS app location', () async {
    final fixedNow = DateTime.parse('2026-08-04T10:00:00Z');
    final service = LocationService(
      adapter: _FakeAdapter(
        checkedPermission: LocationPermissionState.granted,
        position: const DevicePosition(latitude: 32.2211, longitude: 35.2544, accuracy: 8),
      ),
      now: () => fixedNow,
    );

    final result = await service.resolveCurrentLocation();

    expect(result.location?.latitude, 32.2211);
    expect(result.location?.longitude, 35.2544);
    expect(result.location?.accuracy, 8);
    expect(result.location?.source, LocationSource.gps);
    expect(result.location?.resolvedAt, fixedNow);
  });

  test('timeout is mapped to safe failure', () async {
    final service = LocationService(
      adapter: _FakeAdapter(
        checkedPermission: LocationPermissionState.granted,
        getPositionError: TimeoutException('private timeout details'),
      ),
    );

    final result = await service.resolveCurrentLocation();

    expect(result.failure?.code, LocationFailureCode.timeout);
    expect(result.failure?.message, 'location_timeout');
  });

  test('raw plugin errors are mapped to safe failures', () async {
    final service = LocationService(
      adapter: _FakeAdapter(
        checkedPermission: LocationPermissionState.granted,
        getPositionError: StateError('raw plugin exception with coordinates 32.2211,35.2544'),
      ),
    );

    final result = await service.resolveCurrentLocation();

    expect(result.failure?.code, LocationFailureCode.unexpected);
    expect(result.failure?.message, 'location_unexpected');
  });

  test('does not log coordinates', () async {
    final printed = <String>[];
    final service = LocationService(
      adapter: _FakeAdapter(
        checkedPermission: LocationPermissionState.granted,
        position: const DevicePosition(latitude: 32.2211, longitude: 35.2544),
      ),
    );

    await runZoned(
      service.resolveCurrentLocation,
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed.join('\n'), isNot(contains('32.2211')));
    expect(printed.join('\n'), isNot(contains('35.2544')));
  });
}

class _FakeAdapter implements LocationPlatformAdapter {
  _FakeAdapter({
    this.serviceEnabled = true,
    this.checkedPermission = LocationPermissionState.granted,
    this.requestedPermission = LocationPermissionState.granted,
    this.position = const DevicePosition(latitude: 32.2, longitude: 35.2),
    this.getPositionError,
  });

  final bool serviceEnabled;
  final LocationPermissionState checkedPermission;
  final LocationPermissionState requestedPermission;
  final DevicePosition position;
  final Object? getPositionError;

  @override
  Future<LocationPermissionState> checkPermission() async => checkedPermission;

  @override
  Future<DevicePosition> getCurrentPosition({required Duration timeout}) async {
    final error = getPositionError;
    if (error != null) throw error;
    return position;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;

  @override
  Future<LocationPermissionState> requestPermission() async => requestedPermission;
}

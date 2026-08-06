import 'dart:async';

import 'package:geolocator/geolocator.dart' as geolocator;

import '../models/location_models.dart';

class DevicePosition {
  const DevicePosition({
    required this.latitude,
    required this.longitude,
    this.accuracy,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
}

abstract class LocationPlatformAdapter {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermissionState> checkPermission();
  Future<LocationPermissionState> requestPermission();
  Future<DevicePosition> getCurrentPosition({required Duration timeout});
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

class GeolocatorLocationAdapter implements LocationPlatformAdapter {
  const GeolocatorLocationAdapter();

  @override
  Future<bool> isLocationServiceEnabled() => geolocator.Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermissionState> checkPermission() async {
    return _mapPermission(await geolocator.Geolocator.checkPermission());
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    return _mapPermission(await geolocator.Geolocator.requestPermission());
  }

  @override
  Future<DevicePosition> getCurrentPosition({required Duration timeout}) async {
    final position = await geolocator.Geolocator.getCurrentPosition(
      locationSettings: geolocator.LocationSettings(
        accuracy: geolocator.LocationAccuracy.high,
        timeLimit: timeout,
      ),
    );
    return DevicePosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  }

  @override
  Future<bool> openAppSettings() => geolocator.Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => geolocator.Geolocator.openLocationSettings();

  LocationPermissionState _mapPermission(geolocator.LocationPermission permission) {
    return switch (permission) {
      geolocator.LocationPermission.denied => LocationPermissionState.denied,
      geolocator.LocationPermission.deniedForever => LocationPermissionState.deniedForever,
      geolocator.LocationPermission.whileInUse ||
      geolocator.LocationPermission.always =>
        LocationPermissionState.granted,
      geolocator.LocationPermission.unableToDetermine => LocationPermissionState.unknown,
    };
  }
}

class LocationService {
  const LocationService({
    LocationPlatformAdapter adapter = const GeolocatorLocationAdapter(),
    Duration timeout = const Duration(seconds: 10),
    DateTime Function()? now,
  }) : this._(adapter, timeout, now);

  const LocationService._(this._adapter, this.timeout, this._now);

  final LocationPlatformAdapter _adapter;
  final Duration timeout;
  final DateTime Function()? _now;

  Future<LocationPermissionState> checkPermissionState() async {
    try {
      if (!await _adapter.isLocationServiceEnabled()) {
        return LocationPermissionState.serviceDisabled;
      }
      return _adapter.checkPermission();
    } catch (_) {
      return LocationPermissionState.unknown;
    }
  }

  Future<LocationResult> resolveCurrentLocation() async {
    try {
      if (!await _adapter.isLocationServiceEnabled()) {
        return LocationResult.failure(
          const LocationFailure(
            code: LocationFailureCode.serviceDisabled,
            message: 'location_service_disabled',
            permissionState: LocationPermissionState.serviceDisabled,
          ),
        );
      }

      var permission = await _adapter.checkPermission();
      if (permission == LocationPermissionState.denied) {
        permission = await _adapter.requestPermission();
      }

      if (permission == LocationPermissionState.denied) {
        return LocationResult.failure(
          const LocationFailure(
            code: LocationFailureCode.denied,
            message: 'location_permission_denied',
            permissionState: LocationPermissionState.denied,
          ),
        );
      }

      if (permission == LocationPermissionState.deniedForever) {
        return LocationResult.failure(
          const LocationFailure(
            code: LocationFailureCode.deniedForever,
            message: 'location_permission_denied_forever',
            permissionState: LocationPermissionState.deniedForever,
          ),
        );
      }

      if (permission != LocationPermissionState.granted) {
        return LocationResult.failure(
          LocationFailure(
            code: LocationFailureCode.unavailable,
            message: 'location_unavailable',
            permissionState: permission,
          ),
        );
      }

      final position = await _adapter.getCurrentPosition(timeout: timeout);
      return LocationResult.success(
        AppLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          source: LocationSource.gps,
          resolvedAt: _now?.call() ?? DateTime.now(),
          approximate: false,
        ),
      );
    } on TimeoutException {
      return LocationResult.failure(
        const LocationFailure(
          code: LocationFailureCode.timeout,
          message: 'location_timeout',
          permissionState: LocationPermissionState.granted,
        ),
      );
    } catch (_) {
      return LocationResult.failure(
        const LocationFailure(
          code: LocationFailureCode.unexpected,
          message: 'location_unexpected',
        ),
      );
    }
  }

  Future<bool> openAppSettings() async {
    try {
      return await _adapter.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  Future<bool> openLocationSettings() async {
    try {
      return await _adapter.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}

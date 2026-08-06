import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/location_service.dart';
import '../models/location_models.dart';

final locationServiceProvider = Provider<LocationService>((ref) => const LocationService());

enum LocationControllerStatus {
  idle,
  checking,
  requestingPermission,
  locating,
  resolved,
  manual,
  error,
}

class LocationState {
  const LocationState({
    this.status = LocationControllerStatus.idle,
    this.currentLocation,
    this.permissionState = LocationPermissionState.unknown,
    this.errorCode,
    this.errorMessage,
    this.lastRequestWasGps = false,
  });

  final LocationControllerStatus status;
  final AppLocation? currentLocation;
  final LocationPermissionState permissionState;
  final String? errorCode;
  final String? errorMessage;
  final bool lastRequestWasGps;

  bool get hasLocation => currentLocation != null;
  bool get isApproximate => currentLocation?.approximate ?? false;
  LocationSource? get currentSource => currentLocation?.source;

  LocationState copyWith({
    LocationControllerStatus? status,
    AppLocation? currentLocation,
    bool clearLocation = false,
    LocationPermissionState? permissionState,
    String? errorCode,
    String? errorMessage,
    bool clearError = false,
    bool? lastRequestWasGps,
  }) {
    return LocationState(
      status: status ?? this.status,
      currentLocation: clearLocation ? null : (currentLocation ?? this.currentLocation),
      permissionState: permissionState ?? this.permissionState,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastRequestWasGps: lastRequestWasGps ?? this.lastRequestWasGps,
    );
  }
}

class LocationController extends StateNotifier<LocationState> {
  LocationController(LocationService service, {DateTime Function()? now})
      : this._(service, now);

  LocationController._(this._service, this._now) : super(const LocationState());

  final LocationService _service;
  final DateTime Function()? _now;

  int _requestId = 0;
  bool _activeGpsRequest = false;
  bool _disposed = false;

  Future<bool> resolveCurrentLocation() async {
    if (_activeGpsRequest) return false;
    _activeGpsRequest = true;
    final requestId = ++_requestId;
    _set(
      state.copyWith(
        status: LocationControllerStatus.checking,
        clearError: true,
        lastRequestWasGps: true,
      ),
    );

    final permission = await _service.checkPermissionState();
    if (requestId != _requestId) {
      return false;
    }

    _set(
      state.copyWith(
        status: permission == LocationPermissionState.denied
            ? LocationControllerStatus.requestingPermission
            : LocationControllerStatus.locating,
        permissionState: permission,
      ),
    );

    final result = await _service.resolveCurrentLocation();
    if (requestId != _requestId) {
      return false;
    }

    _activeGpsRequest = false;
    final location = result.location;
    if (location != null) {
      _set(
        state.copyWith(
          status: LocationControllerStatus.resolved,
          currentLocation: location,
          permissionState: LocationPermissionState.granted,
          clearError: true,
        ),
      );
      return true;
    }

    final failure = result.failure;
    _set(
      state.copyWith(
        status: LocationControllerStatus.error,
        permissionState: failure?.permissionState ?? permission,
        errorCode: failure?.code.name ?? LocationFailureCode.unexpected.name,
        errorMessage: failure?.message ?? 'location_unexpected',
      ),
    );
    return false;
  }

  void selectManualMapPoint(double latitude, double longitude) {
    _requestId += 1;
    _activeGpsRequest = false;
    _set(
      state.copyWith(
        status: LocationControllerStatus.manual,
        currentLocation: AppLocation(
          latitude: latitude,
          longitude: longitude,
          source: LocationSource.manualMap,
          resolvedAt: _now?.call() ?? DateTime.now(),
          approximate: false,
        ),
        clearError: true,
        lastRequestWasGps: false,
      ),
    );
  }

  void selectManualDistrict(ManualDistrictLocation district) {
    _requestId += 1;
    _activeGpsRequest = false;
    _set(
      state.copyWith(
        status: LocationControllerStatus.manual,
        currentLocation: district.toAppLocation(resolvedAt: _now?.call() ?? DateTime.now()),
        clearError: true,
        lastRequestWasGps: false,
      ),
    );
  }

  void clearLocation() {
    _requestId += 1;
    _activeGpsRequest = false;
    _set(
      state.copyWith(
        status: LocationControllerStatus.idle,
        clearLocation: true,
        clearError: true,
        lastRequestWasGps: false,
      ),
    );
  }

  Future<bool> retry() {
    if (!state.lastRequestWasGps) return Future.value(false);
    return resolveCurrentLocation();
  }

  Future<bool> openAppSettings() => _service.openAppSettings();

  Future<bool> openLocationSettings() => _service.openLocationSettings();

  void _set(LocationState next) {
    if (!_disposed) state = next;
  }

  @override
  void dispose() {
    _disposed = true;
    _requestId += 1;
    super.dispose();
  }
}

final locationControllerProvider = StateNotifierProvider<LocationController, LocationState>(
  (ref) => LocationController(ref.watch(locationServiceProvider)),
);

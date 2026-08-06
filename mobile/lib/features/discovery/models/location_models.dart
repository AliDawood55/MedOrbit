enum LocationPermissionState {
  unknown,
  serviceDisabled,
  denied,
  deniedForever,
  granted,
}

enum LocationSource {
  gps,
  manualMap,
  manualDistrict,
}

enum LocationFailureCode {
  serviceDisabled,
  denied,
  deniedForever,
  timeout,
  unavailable,
  unexpected,
}

class AppLocation {
  const AppLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.source,
    required this.resolvedAt,
    this.approximate = false,
  });

  final double latitude;
  final double longitude;
  final double? accuracy;
  final LocationSource source;
  final DateTime resolvedAt;
  final bool approximate;

  String get displayLatitude => latitude.toStringAsFixed(4);
  String get displayLongitude => longitude.toStringAsFixed(4);
}

class LocationFailure {
  const LocationFailure({
    required this.code,
    required this.message,
    this.permissionState = LocationPermissionState.unknown,
  });

  final LocationFailureCode code;
  final String message;
  final LocationPermissionState permissionState;
}

class LocationResult {
  const LocationResult._({this.location, this.failure});

  final AppLocation? location;
  final LocationFailure? failure;

  bool get isSuccess => location != null;

  factory LocationResult.success(AppLocation location) => LocationResult._(location: location);

  factory LocationResult.failure(LocationFailure failure) => LocationResult._(failure: failure);
}

class ManualDistrictLocation {
  const ManualDistrictLocation({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String nameEn;
  final String nameAr;
  final double latitude;
  final double longitude;

  AppLocation toAppLocation({DateTime? resolvedAt}) {
    return AppLocation(
      latitude: latitude,
      longitude: longitude,
      source: LocationSource.manualDistrict,
      resolvedAt: resolvedAt ?? DateTime.now(),
      approximate: true,
    );
  }
}

const nablusDefaultLatitude = 32.2211;
const nablusDefaultLongitude = 35.2544;

const manualDistrictLocations = [
  ManualDistrictLocation(
    id: 'nablus_city_center',
    nameEn: 'Nablus City Center',
    nameAr: 'مركز مدينة نابلس',
    latitude: 32.2211,
    longitude: 35.2544,
  ),
  ManualDistrictLocation(
    id: 'rafidia',
    nameEn: 'Rafidia',
    nameAr: 'رفيديا',
    latitude: 32.2258,
    longitude: 35.2280,
  ),
  ManualDistrictLocation(
    id: 'askar_camp',
    nameEn: 'Askar Camp',
    nameAr: 'مخيم عسكر',
    latitude: 32.2350,
    longitude: 35.2930,
  ),
  ManualDistrictLocation(
    id: 'balata_camp',
    nameEn: 'Balata Camp',
    nameAr: 'مخيم بلاطة',
    latitude: 32.2080,
    longitude: 35.2862,
  ),
  ManualDistrictLocation(
    id: 'huwara',
    nameEn: 'Huwara',
    nameAr: 'حوارة',
    latitude: 32.1520,
    longitude: 35.2590,
  ),
  ManualDistrictLocation(
    id: 'beit_furik',
    nameEn: 'Beit Furik',
    nameAr: 'بيت فوريك',
    latitude: 32.1760,
    longitude: 35.3350,
  ),
  ManualDistrictLocation(
    id: 'sabastia',
    nameEn: 'Sabastia',
    nameAr: 'سبسطية',
    latitude: 32.2770,
    longitude: 35.1940,
  ),
];

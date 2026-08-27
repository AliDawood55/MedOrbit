class SavedPlace {
  const SavedPlace({
    required this.id,
    this.placeName,
    this.placeType,
    this.address,
    this.phone,
    this.distanceKm,
    this.rating,
    this.createdAt,
  });

  final String id;
  final String? placeName;
  final String? placeType;
  final String? address;
  final String? phone;
  final double? distanceKm;
  final double? rating;
  final DateTime? createdAt;

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
    id: json['id']?.toString() ?? '',
    placeName: _text(json['place_name']),
    placeType: _text(json['place_type']),
    address: _text(json['address']),
    phone: _text(json['phone']),
    distanceKm: _number(json['distance_km']),
    rating: _number(json['rating']),
    createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
  );
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;
double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

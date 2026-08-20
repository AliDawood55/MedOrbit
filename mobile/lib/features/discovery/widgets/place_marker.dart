import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum DiscoveryPlaceType {
  clinic,
  pharmacy,
  hospital,
  laboratory,
  dental,
  radiology,
  emergency,
  doctor,
  unknown;

  static DiscoveryPlaceType fromString(String? value) {
    return switch (value) {
      'clinic' => DiscoveryPlaceType.clinic,
      'pharmacy' => DiscoveryPlaceType.pharmacy,
      'hospital' => DiscoveryPlaceType.hospital,
      'laboratory' => DiscoveryPlaceType.laboratory,
      'dental' => DiscoveryPlaceType.dental,
      'radiology' => DiscoveryPlaceType.radiology,
      'emergency' => DiscoveryPlaceType.emergency,
      'doctor' => DiscoveryPlaceType.doctor,
      _ => DiscoveryPlaceType.unknown,
    };
  }
}

class PlaceMarker extends StatelessWidget {
  const PlaceMarker({
    super.key,
    required this.type,
    this.isUserLocation = false,
    this.semanticLabel,
  });

  final DiscoveryPlaceType type;
  final bool isUserLocation;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = isUserLocation ? AppTheme.primary : _colorFor(type, context);
    final icon = isUserLocation ? Icons.my_location_rounded : _iconFor(type);

    return Semantics(
      label: semanticLabel ?? (isUserLocation ? 'User location marker' : '${type.name} marker'),
      child: Container(
        key: ValueKey(isUserLocation ? 'user-location-marker' : 'place-marker-${type.name}'),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: AppTheme.shadowSmOf(context),
        ),
        child: Icon(icon, color: Colors.white, size: AppTheme.iconMd),
      ),
    );
  }

  IconData _iconFor(DiscoveryPlaceType type) {
    return switch (type) {
      DiscoveryPlaceType.clinic => Icons.local_hospital_rounded,
      DiscoveryPlaceType.pharmacy => Icons.local_pharmacy_rounded,
      DiscoveryPlaceType.hospital => Icons.emergency_rounded,
      DiscoveryPlaceType.laboratory => Icons.science_rounded,
      DiscoveryPlaceType.dental => Icons.medical_services_rounded,
      DiscoveryPlaceType.radiology => Icons.biotech_rounded,
      DiscoveryPlaceType.emergency => Icons.warning_rounded,
      DiscoveryPlaceType.doctor => Icons.person_pin_circle_rounded,
      DiscoveryPlaceType.unknown => Icons.place_rounded,
    };
  }

  Color _colorFor(DiscoveryPlaceType type, BuildContext context) {
    return switch (type) {
      DiscoveryPlaceType.clinic => AppTheme.secondary,
      DiscoveryPlaceType.pharmacy => AppTheme.info,
      DiscoveryPlaceType.hospital => AppTheme.danger,
      DiscoveryPlaceType.laboratory => AppTheme.violet,
      DiscoveryPlaceType.dental => AppTheme.primaryLight,
      DiscoveryPlaceType.radiology => AppTheme.accent,
      DiscoveryPlaceType.emergency => AppTheme.danger,
      DiscoveryPlaceType.doctor => Theme.of(context).colorScheme.primary,
      DiscoveryPlaceType.unknown => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}

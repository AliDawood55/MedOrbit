import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../routes/route_paths.dart';
import '../models/doctor_models.dart';
import 'discovery_map.dart';
import 'doctor_result_card.dart';
import 'place_marker.dart';

class ClinicMiniMap extends StatelessWidget {
  const ClinicMiniMap({super.key, required this.clinics});
  final List<DoctorClinicSummary> clinics;
  @override
  Widget build(BuildContext context) {
    final places = clinics.where((clinic) => clinic.latitude != null && clinic.longitude != null).map((clinic) => DiscoveryMapPlace(id: clinic.id, latitude: clinic.latitude!, longitude: clinic.longitude!, type: DiscoveryPlaceType.clinic, label: clinicDisplayName(clinic, Directionality.of(context)))).toList();
    if (places.isEmpty) return const Text('No map coordinates are listed for these clinics.');
    return SizedBox(
      height: 260,
      child: DiscoveryMap(
        places: places,
        initialCenter: LatLng(places.first.latitude, places.first.longitude),
        initialZoom: 14,
        showControls: false,
        onPlaceTap: (place) => context.push(RoutePaths.clinicDetailPath(place.id)),
      ),
    );
  }
}

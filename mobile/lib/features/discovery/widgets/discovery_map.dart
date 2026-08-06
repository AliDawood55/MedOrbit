import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../models/location_models.dart';
import 'place_marker.dart';

class DiscoveryMapPlace {
  const DiscoveryMapPlace({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    this.label,
  });

  final String id;
  final double latitude;
  final double longitude;
  final DiscoveryPlaceType type;
  final String? label;

  LatLng get point => LatLng(latitude, longitude);
}

class DiscoveryMap extends StatefulWidget {
  const DiscoveryMap({
    super.key,
    this.places = const [],
    this.userLocation,
    this.onMapTap,
    this.onPlaceTap,
    this.initialCenter = const LatLng(nablusDefaultLatitude, nablusDefaultLongitude),
    this.initialZoom = 13,
    this.showControls = true,
  });

  final List<DiscoveryMapPlace> places;
  final AppLocation? userLocation;
  final ValueChanged<LatLng>? onMapTap;
  final ValueChanged<DiscoveryMapPlace>? onPlaceTap;
  final LatLng initialCenter;
  final double initialZoom;
  final bool showControls;

  @override
  State<DiscoveryMap> createState() => _DiscoveryMapState();
}

class _DiscoveryMapState extends State<DiscoveryMap> {
  late final MapController _controller;

  @override
  void initState() {
    super.initState();
    _controller = MapController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userLocation = widget.userLocation;
    final userPoint = userLocation == null
        ? null
        : LatLng(userLocation.latitude, userLocation.longitude);
    final userCoordinates = userPoint == null ? null : <LatLng>[userPoint];
    final placeMarkers = [
      for (final place in widget.places)
        Marker(
          point: place.point,
          width: 48,
          height: 48,
          child: GestureDetector(
            key: ValueKey('discovery-map-place-${place.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onPlaceTap?.call(place),
            child: PlaceMarker(
              type: place.type,
              semanticLabel: place.label == null ? null : '${place.label} marker',
            ),
          ),
        ),
    ];
    final allCoordinates = [
      for (final place in widget.places) place.point,
      ...?userCoordinates,
    ];

    final userMarkers = userPoint == null
        ? null
        : <Marker>[
            Marker(
              point: userPoint,
              width: 54,
              height: 54,
              child: const PlaceMarker(
                type: DiscoveryPlaceType.unknown,
                isUserLocation: true,
              ),
            ),
          ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      child: Stack(
        children: [
          FlutterMap(
            key: const ValueKey('discovery-flutter-map'),
            mapController: _controller,
            options: MapOptions(
              initialCenter: widget.initialCenter,
              initialZoom: widget.initialZoom,
              minZoom: 3,
              maxZoom: 18,
              backgroundColor: theme.colorScheme.surface,
              onTap: (_, point) => widget.onMapTap?.call(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.medorbit.mobile',
              ),
              MarkerClusterLayerWidget(
                options: MarkerClusterLayerOptions(
                  markers: placeMarkers,
                  markerChildBehavior: true,
                  maxClusterRadius: 48,
                  size: const Size(44, 44),
                  maxZoom: 17,
                  padding: const EdgeInsets.all(AppTheme.spaceXl),
                  showPolygon: false,
                  builder: (context, clusteredMarkers) {
                    return Container(
                      key: const ValueKey('place-marker-cluster'),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        clusteredMarkers.length.toString(),
                        style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),
              if (userMarkers != null) MarkerLayer(markers: userMarkers),
            ],
          ),
          const PositionedDirectional(
            start: AppTheme.spaceSm,
            bottom: AppTheme.spaceSm,
            child: _OsmAttribution(),
          ),
          if (widget.showControls)
            PositionedDirectional(
              top: AppTheme.spaceMd,
              end: AppTheme.spaceMd,
              child: _MapControls(
                onFitMarkers: allCoordinates.isEmpty ? null : _fitMarkers,
                onRecenter: userPoint == null ? null : () => _controller.move(userPoint, 15),
              ),
            ),
        ],
      ),
    );
  }

  void _fitMarkers() {
    final userLocation = widget.userLocation;
    final userCoordinate = userLocation == null
        ? null
        : <LatLng>[LatLng(userLocation.latitude, userLocation.longitude)];
    final coordinates = <LatLng>[
      for (final place in widget.places) place.point,
      ...?userCoordinate,
    ];
    if (coordinates.isEmpty) return;
    if (coordinates.length == 1) {
      _controller.move(coordinates.single, 15);
      return;
    }
    _controller.fitCamera(
      CameraFit.coordinates(
        coordinates: coordinates,
        padding: const EdgeInsets.all(64),
        maxZoom: 15,
      ),
    );
  }
}

class _OsmAttribution extends StatelessWidget {
  const _OsmAttribution();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spaceSm,
          vertical: AppTheme.spaceXs,
        ),
        child: Text(
          '© OpenStreetMap',
          key: const ValueKey('osm-attribution'),
          softWrap: true,
          overflow: TextOverflow.visible,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onFitMarkers,
    required this.onRecenter,
  });

  final VoidCallback? onFitMarkers;
  final VoidCallback? onRecenter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: const ValueKey('fit-map-markers-button'),
            tooltip: 'Fit markers',
            onPressed: onFitMarkers,
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
          IconButton(
            key: const ValueKey('recenter-user-location-button'),
            tooltip: 'Recenter to your location',
            onPressed: onRecenter,
            icon: const Icon(Icons.my_location_rounded),
          ),
        ],
      ),
    );
  }
}

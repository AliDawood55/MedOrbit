import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/page_sections.dart';
import '../providers/location_provider.dart';
import '../widgets/discovery_map.dart';
import '../widgets/location_picker_sheet.dart';

class MapFoundationScreen extends ConsumerStatefulWidget {
  const MapFoundationScreen({super.key});

  @override
  ConsumerState<MapFoundationScreen> createState() => _MapFoundationScreenState();
}

class _MapFoundationScreenState extends ConsumerState<MapFoundationScreen> {
  bool _selectingMapPoint = false;

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);
    final location = locationState.currentLocation;

    return AppScaffold(
      appBar: AppBar(title: const Text('Map foundation')),
      useSafeArea: true,
      body: Column(
        children: [
          Expanded(
            child: DiscoveryMap(
              userLocation: location,
              onMapTap: _selectingMapPoint
                  ? (point) {
                      controller.selectManualMapPoint(point.latitude, point.longitude);
                      setState(() => _selectingMapPoint = false);
                    }
                  : null,
            ),
          ),
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: ResponsiveContent(
              padding: const EdgeInsets.all(AppTheme.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LocationSummary(state: locationState),
                  if (_selectingMapPoint) ...[
                    const SizedBox(height: AppTheme.spaceSm),
                    const InlineMessage(
                      message: 'Tap the map to select a manual point.',
                      tone: InlineMessageTone.info,
                    ),
                  ],
                  const SizedBox(height: AppTheme.spaceMd),
                  Wrap(
                    spacing: AppTheme.spaceSm,
                    runSpacing: AppTheme.spaceSm,
                    children: [
                      FilledButton.icon(
                        onPressed: locationState.status == LocationControllerStatus.locating ||
                                locationState.status == LocationControllerStatus.checking ||
                                locationState.status == LocationControllerStatus.requestingPermission
                            ? null
                            : controller.resolveCurrentLocation,
                        icon: const Icon(Icons.my_location_rounded),
                        label: const Text('Use GPS'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _selectingMapPoint = true),
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('Pick on map'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _showPicker(context, locationState, controller),
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('More options'),
                      ),
                      TextButton.icon(
                        onPressed: controller.clearLocation,
                        icon: const Icon(Icons.clear_rounded),
                        label: const Text('Clear'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPicker(
    BuildContext context,
    LocationState state,
    LocationController controller,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return LocationPickerSheet(
          permissionState: state.permissionState,
          errorMessage: state.errorMessage,
          isBusy: state.status == LocationControllerStatus.locating ||
              state.status == LocationControllerStatus.checking ||
              state.status == LocationControllerStatus.requestingPermission,
          onUseCurrentLocation: () {
            Navigator.pop(context);
            controller.resolveCurrentLocation();
          },
          onSelectMapPoint: () {
            Navigator.pop(context);
            setState(() => _selectingMapPoint = true);
          },
          onSelectDistrict: (district) {
            Navigator.pop(context);
            controller.selectManualDistrict(district);
          },
          onOpenAppSettings: controller.openAppSettings,
          onOpenLocationSettings: controller.openLocationSettings,
          onClear: () {
            Navigator.pop(context);
            controller.clearLocation();
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }
}

class _LocationSummary extends StatelessWidget {
  const _LocationSummary({required this.state});

  final LocationState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = state.currentLocation;
    final errorMessage = state.errorMessage;
    final status = state.status.name;
    final source = location?.source.name ?? 'none';
    final precision = location == null
        ? 'No location selected'
        : '${location.approximate ? 'Approximate' : 'Exact'} · ${location.displayLatitude}, ${location.displayLongitude}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Location state',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppTheme.spaceSm),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                precision,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: AppTheme.spaceXs),
            Text(
              'Status: $status · Source: $source',
              style: theme.textTheme.bodySmall,
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              InlineMessage(
                message: errorMessage,
                tone: InlineMessageTone.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

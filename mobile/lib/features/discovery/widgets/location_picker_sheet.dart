import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/location_models.dart';

class LocationPickerSheet extends StatelessWidget {
  const LocationPickerSheet({
    super.key,
    required this.permissionState,
    this.errorMessage,
    required this.onUseCurrentLocation,
    required this.onSelectMapPoint,
    required this.onSelectDistrict,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
    required this.onClear,
    required this.onCancel,
    this.isBusy = false,
  });

  final LocationPermissionState permissionState;
  final String? errorMessage;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onSelectMapPoint;
  final ValueChanged<ManualDistrictLocation> onSelectDistrict;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;
  final VoidCallback onClear;
  final VoidCallback onCancel;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.spaceLg,
          AppTheme.spaceMd,
          AppTheme.spaceLg,
          AppTheme.spaceLg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: LayoutBuilder(
          builder: (context, _) {
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
              child: SingleChildScrollView(
                key: const ValueKey('location-picker-scrollable'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Choose location',
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: AppTheme.weightBold),
                    ),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(
                      'Use GPS, select a point, or choose an approximate Nablus-area district.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: AppTheme.spaceMd),
                      _GuidanceCard(
                        message: _errorGuidance(permissionState, errorMessage!),
                        onOpenAppSettings: onOpenAppSettings,
                        onOpenLocationSettings: onOpenLocationSettings,
                      ),
                    ],
                    const SizedBox(height: AppTheme.spaceLg),
                    FilledButton.icon(
                      onPressed: isBusy ? null : onUseCurrentLocation,
                      icon: isBusy
                          ? const SizedBox.square(
                              dimension: AppTheme.iconMd,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location_rounded),
                      label: const Text('Use current location'),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    OutlinedButton.icon(
                      onPressed: onSelectMapPoint,
                      icon: const Icon(Icons.add_location_alt_rounded),
                      label: const Text('Select point on map'),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    Text(
                      'Approximate district',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    Wrap(
                      spacing: AppTheme.spaceSm,
                      runSpacing: AppTheme.spaceSm,
                      children: [
                        for (final district in manualDistrictLocations)
                          ActionChip(
                            key: ValueKey('location-district-${_districtKeyId(district)}'),
                            avatar: const Icon(Icons.location_city_rounded, size: AppTheme.iconSm),
                            label: Text(
                              '${isArabic ? district.nameAr : district.nameEn} · approximate',
                              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                            ),
                            onPressed: () => onSelectDistrict(district),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    _PrivacyNote(theme: theme),
                    const SizedBox(height: AppTheme.spaceMd),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppTheme.spaceSm,
                      runSpacing: AppTheme.spaceSm,
                      children: [
                        TextButton(onPressed: onClear, child: const Text('Clear')),
                        TextButton(onPressed: onCancel, child: const Text('Cancel')),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _errorGuidance(LocationPermissionState state, String fallback) {
    return switch (state) {
      LocationPermissionState.serviceDisabled => 'Location services are off. Turn them on or choose a manual location.',
      LocationPermissionState.denied => 'Location permission was denied. You can retry or choose a manual location.',
      LocationPermissionState.deniedForever => 'Location permission is blocked. Open app settings or choose a manual location.',
      _ => fallback,
    };
  }
}

String _districtKeyId(ManualDistrictLocation district) {
  if (district.id == 'nablus_city_center') return 'nablus-center';
  return district.id.replaceAll('_', '-');
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({
    required this.message,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final String message;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.28)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppTheme.spaceSm),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenAppSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('App settings'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenLocationSettings,
                  icon: const Icon(Icons.location_searching_rounded),
                  label: const Text('Location settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.info.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.info.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceMd),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.privacy_tip_outlined, size: AppTheme.iconMd, color: AppTheme.info),
            const SizedBox(width: AppTheme.spaceSm),
            Expanded(
              child: Text(
                'Location is used for nearby results. Exact location is not persisted by the mobile app. External map or routing providers may receive location later when those actions are used.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

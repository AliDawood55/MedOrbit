import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../models/location_models.dart';

class LocationPickerSheet extends ConsumerWidget {
  const LocationPickerSheet({
    super.key,
    required this.permissionState,
    this.errorCode,
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

  /// Name of the [LocationFailureCode] the state layer reported (e.g.
  /// `serviceDisabled`, `denied`, `deniedForever`, `timeout`, `unavailable`,
  /// `unexpected`). Used to pick a distinct localized message per failure
  /// kind. Falls back to [permissionState] when unset.
  final String? errorCode;
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
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final theme = Theme.of(context);
    final isArabic = strings.isArabic;
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
                      strings.chooseLocationTitle,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: AppTheme.weightBold),
                    ),
                    const SizedBox(height: AppTheme.spaceXs),
                    Text(
                      strings.chooseLocationSubtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: AppTheme.spaceMd),
                      _GuidanceCard(
                        message: _errorGuidance(strings),
                        appSettingsLabel: strings.appSettingsButton,
                        locationSettingsLabel: strings.locationSettingsButton,
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
                      label: Text(strings.useCurrentLocationButton),
                    ),
                    const SizedBox(height: AppTheme.spaceSm),
                    OutlinedButton.icon(
                      onPressed: onSelectMapPoint,
                      icon: const Icon(Icons.add_location_alt_rounded),
                      label: Text(strings.selectPointOnMapButton),
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    Text(
                      strings.approximateDistrictTitle,
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
                              '${isArabic ? district.nameAr : district.nameEn} · ${strings.districtApproximateSuffix}',
                              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                            ),
                            onPressed: () => onSelectDistrict(district),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    _PrivacyNote(theme: theme, text: strings.locationPrivacyNote),
                    const SizedBox(height: AppTheme.spaceMd),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppTheme.spaceSm,
                      runSpacing: AppTheme.spaceSm,
                      children: [
                        TextButton(onPressed: onClear, child: Text(strings.clearLocationButton)),
                        TextButton(onPressed: onCancel, child: Text(strings.cancel)),
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

  String _errorGuidance(AppStrings strings) {
    final code = errorCode ?? switch (permissionState) {
      LocationPermissionState.serviceDisabled => 'serviceDisabled',
      LocationPermissionState.denied => 'denied',
      LocationPermissionState.deniedForever => 'deniedForever',
      _ => null,
    };
    if (code == null) return errorMessage ?? strings.locationUnexpectedMessage;
    return strings.locationErrorForCode(code);
  }
}

String _districtKeyId(ManualDistrictLocation district) {
  if (district.id == 'nablus_city_center') return 'nablus-center';
  return district.id.replaceAll('_', '-');
}

class _GuidanceCard extends StatelessWidget {
  const _GuidanceCard({
    required this.message,
    required this.appSettingsLabel,
    required this.locationSettingsLabel,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final String message;
  final String appSettingsLabel;
  final String locationSettingsLabel;
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
                  label: Text(appSettingsLabel),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenLocationSettings,
                  icon: const Icon(Icons.location_searching_rounded),
                  label: Text(locationSettingsLabel),
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
  const _PrivacyNote({required this.theme, required this.text});

  final ThemeData theme;
  final String text;

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
                text,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

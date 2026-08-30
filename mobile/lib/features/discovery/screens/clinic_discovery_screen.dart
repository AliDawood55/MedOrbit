import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';

import '../../../routes/route_paths.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';

import '../models/clinic_models.dart';
import '../models/location_models.dart';
import '../providers/discovery_provider.dart';
import '../providers/location_provider.dart';
import '../widgets/clinic_filter_sheet.dart';
import '../widgets/clinic_result_card.dart';
import '../widgets/discovery_map.dart';
import '../widgets/location_picker_sheet.dart';
import '../widgets/place_marker.dart';

enum _ClinicViewMode { list, map }

class ClinicDiscoveryScreen extends ConsumerStatefulWidget {
  const ClinicDiscoveryScreen({super.key});

  @override
  ConsumerState<ClinicDiscoveryScreen> createState() => _ClinicDiscoveryScreenState();
}

class _ClinicDiscoveryScreenState extends ConsumerState<ClinicDiscoveryScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  _ClinicViewMode _mode = _ClinicViewMode.list;
  bool _nearbyMode = false;
  bool _pickingMapPoint = false;
  double _radius = 5;
  Clinic? _selectedMapClinic;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(discoveryControllerProvider.notifier).loadClinics();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final discovery = ref.watch(discoveryControllerProvider);

    final location = ref.watch(locationControllerProvider);
    final clinics = _nearbyMode ? discovery.nearbyClinics : discovery.clinics;
    final loading = _nearbyMode ? discovery.isLoadingNearbyClinics : discovery.isLoadingClinics;
    final error = _nearbyMode ? discovery.nearbyError : discovery.clinicListError;

    return AppScaffold(

      appBar: AppBar(title: Text(strings.clinicDiscoveryScreenTitle)),

      useSafeArea: true,
      keyboardAware: true,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const PageStorageKey<String>('clinic-discovery-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              maxWidth: 960,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageIntro(

                    title: strings.clinicDiscoveryTitle,
                    subtitle: strings.clinicDiscoverySubtitle,

                    icon: Icons.local_hospital_outlined,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  _SearchAndViewControls(
                    strings: strings,
                    controller: _searchController,
                    mode: _mode,
                    onSearchChanged: _onSearchChanged,
                    onClearSearch: _clearSearch,
                    onModeChanged: (mode) => setState(() => _mode = mode),
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  _FacilityTypeQuickFilter(
                    strings: strings,
                    selected: discovery.clinicFilters.type,
                    onSelected: _onFacilityTypeChanged,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  _NearbyCard(
                    strings: strings,
                    locationState: location,
                    nearbyMode: _nearbyMode,
                    radius: _radius,
                    onUseLocation: () {
                      _useCurrentLocation();
                    },
                    onPickLocation: () {
                      _showLocationPicker(location);
                    },
                    onRadiusChanged: (value) {
                      setState(() => _radius = value);
                      _loadNearbyFromState();
                    },
                    onExitNearby: _exitNearby,
                  ),
                  if (_pickingMapPoint) ...[
                    const SizedBox(height: AppTheme.spaceMd),
                    InlineMessage(
                      message: strings.pickMapPointHint,
                      tone: InlineMessageTone.info,
                    ),
                  ],
                  const SizedBox(height: AppTheme.spaceLg),
                  _FilterSummary(
                    strings: strings,
                    filters: discovery.clinicFilters,
                    nearbyMode: _nearbyMode,
                    resultCount: clinics.length,
                    onOpenFilters: () {
                      _showFilters(discovery);
                    },
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  if (loading)
                    _LoadingClinicList(strings: strings)
                  else if (error != null)
                    Card(
                      child: ErrorRetryState(
                        title: strings.clinicCouldNotLoadClinics,
                        message: error.message,
                        retryLabel: strings.retry,
                        onRetry: () {
                          _refresh();
                        },
                        variant: ErrorRetryVariant.compact,
                        retryKey: const ValueKey('clinic-discovery-retry'),
                      ),
                    )
                  else if (_mode == _ClinicViewMode.list)
                    _ClinicListResults(
                      strings: strings,
                      clinics: clinics,
                      nearbyMode: _nearbyMode,
                      canLoadMore: !_nearbyMode && discovery.canLoadMoreClinics,
                      isLoadingMore: discovery.isLoadingMoreClinics,
                      onLoadMore: () {
                        ref.read(discoveryControllerProvider.notifier).loadMoreClinics();
                      },
                    )
                  else
                    _ClinicMapResults(
                      strings: strings,
                      clinics: clinics,
                      nearbyMode: _nearbyMode,
                      userLocation: _nearbyMode ? location.currentLocation : null,
                      selectedClinic: _selectedMapClinic,
                      onMapTap: _pickingMapPoint ? _selectManualPoint : null,
                      onMarkerTap: (clinic) => setState(() => _selectedMapClinic = clinic),
                      onOpenDetail: (clinic) => context.push(RoutePaths.clinicDetailPath(clinic.id)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    if (_nearbyMode) {
      await _loadNearbyFromState();
    } else {
      await ref.read(discoveryControllerProvider.notifier).loadClinics();
    }
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final query = value.trim();
      if (query.length == 1) return;
      final current = ref.read(discoveryControllerProvider).clinicFilters;
      final filters = current.copyWith(
        search: query.isEmpty ? null : query,
        clearSearch: query.isEmpty,
        page: 1,
      );
      ref.read(discoveryControllerProvider.notifier).loadClinics(filters: filters);
      if (_nearbyMode) setState(() => _nearbyMode = false);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _onFacilityTypeChanged(String? type) {
    final current = ref.read(discoveryControllerProvider).clinicFilters;
    final filters = current.copyWith(
      type: type,
      clearType: type == null,
      page: 1,
    );
    if (_nearbyMode) {
      ref.read(discoveryControllerProvider.notifier).updateClinicFilters(filters);
      _loadNearbyFromState();
    } else {
      ref.read(discoveryControllerProvider.notifier).loadClinics(filters: filters);
    }
  }

  Future<void> _showFilters(DiscoveryState discovery) async {
    final clinics = [...discovery.clinics, ...discovery.nearbyClinics];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ClinicFilterSheet(
        initialFilters: discovery.clinicFilters,
        regions: _derive(clinics, (clinic) => clinic.region),
        services: clinics.expand((clinic) => clinic.services).toSet().toList(),
        insuranceOptions: clinics.expand((clinic) => clinic.insuranceAccepted).toSet().toList(),
        onApply: (filters) {
          ref.read(discoveryControllerProvider.notifier).loadClinics(filters: filters);
          setState(() => _nearbyMode = false);
        },
        onClear: () {
          ref.read(discoveryControllerProvider.notifier).loadClinics(filters: const ClinicFilters());
          setState(() => _nearbyMode = false);
        },
      ),
    );
  }

  Future<void> _showLocationPicker(LocationState state) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => LocationPickerSheet(
        permissionState: state.permissionState,
        errorCode: state.errorCode,
        errorMessage: state.errorMessage,
        isBusy: state.status == LocationControllerStatus.locating ||
            state.status == LocationControllerStatus.checking ||
            state.status == LocationControllerStatus.requestingPermission,
        onUseCurrentLocation: () {
          Navigator.pop(context);
          _useCurrentLocation();
        },
        onSelectMapPoint: () {
          Navigator.pop(context);
          setState(() {
            _mode = _ClinicViewMode.map;
            _pickingMapPoint = true;
          });
        },
        onSelectDistrict: (district) {
          Navigator.pop(context);
          ref.read(locationControllerProvider.notifier).selectManualDistrict(district);
          _loadNearbyFromState();
        },
        onOpenAppSettings: () {
          ref.read(locationControllerProvider.notifier).openAppSettings();
        },
        onOpenLocationSettings: () {
          ref.read(locationControllerProvider.notifier).openLocationSettings();
        },
        onClear: () {
          Navigator.pop(context);
          _exitNearby();
        },
        onCancel: () => Navigator.pop(context),
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    final ok = await ref.read(locationControllerProvider.notifier).resolveCurrentLocation();
    if (!mounted) return;
    if (ok) {
      await _loadNearbyFromState();
    } else {
      await _showLocationPicker(ref.read(locationControllerProvider));
    }
  }

  void _selectManualPoint(LatLng point) {
    ref.read(locationControllerProvider.notifier).selectManualMapPoint(point.latitude, point.longitude);
    setState(() => _pickingMapPoint = false);
    _loadNearbyFromState();
  }

  Future<void> _loadNearbyFromState() async {
    final location = ref.read(locationControllerProvider).currentLocation;
    if (location == null) return;
    final type = ref.read(discoveryControllerProvider).clinicFilters.type;
    setState(() {
      _nearbyMode = true;
      _selectedMapClinic = null;
    });
    await ref.read(discoveryControllerProvider.notifier).loadNearbyClinics(
          lat: location.latitude,
          lng: location.longitude,
          radius: _radius,
          type: type,
        );
  }

  void _exitNearby() {
    ref.read(locationControllerProvider.notifier).clearLocation();
    setState(() {
      _nearbyMode = false;
      _pickingMapPoint = false;
      _selectedMapClinic = null;
    });
  }
}

class _SearchAndViewControls extends StatelessWidget {
  const _SearchAndViewControls({
    required this.strings,
    required this.controller,
    required this.mode,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onModeChanged,
  });

  final AppStrings strings;
  final TextEditingController controller;
  final _ClinicViewMode mode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_ClinicViewMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          children: [
            AppTextField(
              label: strings.searchClinicsLabel,
              hintText: strings.searchClinicsFieldHint,
              controller: controller,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: strings.clearSearch,
                      onPressed: onClearSearch,
                      icon: const Icon(Icons.close_rounded),
                    ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: AppTheme.spaceMd),
            SegmentedButton<_ClinicViewMode>(
              segments: [
                ButtonSegment(value: _ClinicViewMode.list, icon: const Icon(Icons.list_alt_rounded), label: Text(strings.discoveryViewModeList)),
                ButtonSegment(value: _ClinicViewMode.map, icon: const Icon(Icons.map_outlined), label: Text(strings.discoveryViewModeMap)),
              ],
              selected: {mode},
              onSelectionChanged: (selection) => onModeChanged(selection.single),
            ),
          ],
        ),
      ),
    );
  }
}

/// Always-visible compact facility-type filter, mirroring the web filter bar
/// (All / Clinic / Dental / Pharmacy / Hospital). The advanced bottom sheet
/// still exposes the full set of facility types; both write the same
/// [ClinicFilters.type] so they stay in sync.
class _FacilityTypeQuickFilter extends StatelessWidget {
  const _FacilityTypeQuickFilter({
    required this.strings,
    required this.selected,
    required this.onSelected,
  });

  final AppStrings strings;
  final String? selected;
  final ValueChanged<String?> onSelected;

  static const _types = <String, IconData>{
    'clinic': Icons.local_hospital_outlined,
    'dental': Icons.medical_services_outlined,
    'pharmacy': Icons.local_pharmacy_outlined,
    'hospital': Icons.emergency_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: strings.clinicFilterFacilityType,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceLg),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceXs),
              child: ChoiceChip(
                key: const ValueKey('facility-type-quick-all'),
                label: Text(strings.clinicFilterAllTypes),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
            ),
            for (final entry in _types.entries)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceXs),
                child: ChoiceChip(
                  key: ValueKey('facility-type-quick-${entry.key}'),
                  avatar: Icon(entry.value, size: AppTheme.iconSm),
                  label: Text(strings.clinicTypeLabelFor(entry.key)),
                  selected: selected == entry.key,
                  onSelected: (_) => onSelected(entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NearbyCard extends StatelessWidget {
  const _NearbyCard({
    required this.strings,
    required this.locationState,
    required this.nearbyMode,
    required this.radius,
    required this.onUseLocation,
    required this.onPickLocation,
    required this.onRadiusChanged,
    required this.onExitNearby,
  });

  final AppStrings strings;
  final LocationState locationState;
  final bool nearbyMode;
  final double radius;
  final VoidCallback onUseLocation;
  final VoidCallback onPickLocation;
  final ValueChanged<double> onRadiusChanged;
  final VoidCallback onExitNearby;

  @override
  Widget build(BuildContext context) {
    final location = locationState.currentLocation;
    final source = switch (location?.source) {
      LocationSource.gps => strings.locationSourceGps,
      LocationSource.manualMap => strings.locationSourceManualMap,
      LocationSource.manualDistrict => strings.locationSourceManualDistrict,
      null => strings.locationSourceNone,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: strings.nearbySearchTitle,
              subtitle: nearbyMode
                  ? strings.nearbySearchSubtitleActive(source, location?.approximate == true)
                  : strings.nearbySearchSubtitleInactive,
            ),
            Wrap(
              spacing: AppTheme.spaceSm,
              runSpacing: AppTheme.spaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PrimaryButton(label: strings.useGpsButton, icon: Icons.my_location_rounded, onPressed: onUseLocation),
                OutlinedButton.icon(
                  onPressed: onPickLocation,
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: Text(strings.chooseLocationButton),
                ),
                if (nearbyMode)
                  TextButton.icon(
                    onPressed: onExitNearby,
                    icon: const Icon(Icons.clear_rounded),
                    label: Text(strings.exitNearbyButton),
                  ),
              ],
            ),
            if (nearbyMode) ...[
              const SizedBox(height: AppTheme.spaceMd),
              Wrap(
                spacing: AppTheme.spaceXs,
                runSpacing: AppTheme.spaceXs,
                children: [
                  for (final value in const [2.0, 5.0, 10.0])
                    ChoiceChip(
                      label: Text(strings.radiusKmValue(value.toStringAsFixed(0))),
                      selected: radius == value,
                      onSelected: (_) => onRadiusChanged(value),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterSummary extends StatelessWidget {
  const _FilterSummary({
    required this.strings,
    required this.filters,
    required this.nearbyMode,
    required this.resultCount,
    required this.onOpenFilters,
  });

  final AppStrings strings;
  final ClinicFilters filters;
  final bool nearbyMode;
  final int resultCount;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) {
    final active = [
      if (filters.type != null) strings.discoveryFilterSummaryTypeValue(strings.clinicTypeLabelFor(filters.type)),
      if (filters.region != null) strings.discoveryFilterSummaryRegion(filters.region!),
      if (filters.service != null) strings.discoveryFilterSummaryService(filters.service!),
      if (filters.insurance != null) strings.discoveryFilterSummaryInsurance(filters.insurance!),
      if (filters.search != null) strings.discoverySearchActiveLabel,
      if (nearbyMode) strings.discoveryFilterSummaryNearby,
    ];
    return SectionHeader(
      title: strings.clinicResultsCount(resultCount),
      subtitle: active.isEmpty ? strings.discoveryNoActiveFilters : active.join(' · '),
      trailing: OutlinedButton.icon(
        onPressed: onOpenFilters,
        icon: const Icon(Icons.filter_list_rounded),
        label: Text(strings.discoveryFiltersButton),
      ),
    );
  }
}

class _ClinicListResults extends StatelessWidget {
  const _ClinicListResults({
    required this.strings,
    required this.clinics,
    required this.nearbyMode,
    required this.canLoadMore,
    required this.isLoadingMore,
    required this.onLoadMore,
  });

  final AppStrings strings;
  final List<Clinic> clinics;
  final bool nearbyMode;
  final bool canLoadMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (clinics.isEmpty) {
      return Card(
        key: const ValueKey('clinic-discovery-empty-state'),
        child: EmptyState(
          icon: Icons.local_hospital_outlined,
          title: strings.clinicEmptyTitle,
          hint: strings.clinicEmptyHint,
          variant: EmptyStateVariant.compact,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final clinic in clinics) ...[
          ClinicResultCard(clinic: clinic, nearbyMode: nearbyMode),
          const SizedBox(height: AppTheme.spaceSm),
        ],
        if (canLoadMore)
          PrimaryButton(
            label: strings.discoveryLoadMoreButton,
            isLoading: isLoadingMore,
            onPressed: onLoadMore,
          ),
      ],
    );
  }
}

class _ClinicMapResults extends StatelessWidget {
  const _ClinicMapResults({
    required this.strings,
    required this.clinics,
    required this.nearbyMode,
    required this.userLocation,
    required this.selectedClinic,
    required this.onMapTap,
    required this.onMarkerTap,
    required this.onOpenDetail,
  });

  final AppStrings strings;
  final List<Clinic> clinics;
  final bool nearbyMode;
  final AppLocation? userLocation;
  final Clinic? selectedClinic;
  final ValueChanged<LatLng>? onMapTap;
  final ValueChanged<Clinic> onMarkerTap;
  final ValueChanged<Clinic> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final selected = selectedClinic;
    final direction = Directionality.of(context);
    final places = clinics.map((clinic) => _clinicMapPlace(clinic, direction, strings)).whereType<DiscoveryMapPlace>().toList();
    return SizedBox(
      height: 520,
      child: Stack(
        children: [
          DiscoveryMap(
            key: ValueKey('clinic-map-${places.length}'),
            places: places,
            userLocation: nearbyMode ? userLocation : null,
            onMapTap: onMapTap,
            onPlaceTap: (place) {
                  Clinic? clinic;
                  for (final item in clinics) {
                    if (item.id == place.id) {
                      clinic = item;
                      break;
                    }
                  }
              if (clinic != null) onMarkerTap(clinic);
            },
          ),
          if (places.isEmpty)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spaceLg),
                      child: Text(strings.clinicNoMappedResults),
                    ),
                  ),
                ),
              ),
            ),
          if (selected != null)
            PositionedDirectional(
              start: AppTheme.spaceMd,
              end: AppTheme.spaceMd,
              bottom: AppTheme.spaceMd,
              child: ClinicResultCard(
                clinic: selected,
                nearbyMode: nearbyMode,
                onTap: () => onOpenDetail(selected),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadingClinicList extends StatelessWidget {
  const _LoadingClinicList({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Row(
          children: [
            const SizedBox.square(dimension: AppTheme.iconLg, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: AppTheme.spaceMd),
            Expanded(child: Text(strings.clinicLoadingClinics)),
          ],
        ),
      ),
    );
  }
}

List<String> _derive(List<Clinic> clinics, String? Function(Clinic clinic) read) {
  return clinics.map(read).whereType<String>().where((value) => value.trim().isNotEmpty).toSet().toList()..sort();
}

DiscoveryMapPlace? _clinicMapPlace(Clinic clinic, TextDirection direction, AppStrings strings) {
  final latitude = clinic.latitude;
  final longitude = clinic.longitude;
  if (latitude == null || longitude == null) return null;
  return DiscoveryMapPlace(
    id: clinic.id,
    latitude: latitude,
    longitude: longitude,
    type: DiscoveryPlaceType.fromString(clinic.type),
    label: clinicDisplayName(clinic, direction, strings),
  );
}

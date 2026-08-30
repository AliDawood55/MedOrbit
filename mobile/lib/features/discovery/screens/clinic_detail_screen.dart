import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/clinic_models.dart';
import '../providers/discovery_provider.dart';
import '../widgets/clinic_detail_sections.dart';
import '../widgets/discovery_map.dart';
import '../widgets/place_marker.dart';


class ClinicDetailScreen extends ConsumerStatefulWidget {
  const ClinicDetailScreen({super.key, required this.clinicId});

  final String clinicId;

  @override
  ConsumerState<ClinicDetailScreen> createState() => _ClinicDetailScreenState();
}

class _ClinicDetailScreenState extends ConsumerState<ClinicDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void didUpdateWidget(covariant ClinicDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clinicId != widget.clinicId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _load();
      });
    }
  }

  Future<void> _load() async {
    await ref.read(discoveryControllerProvider.notifier).loadClinicDetail(widget.clinicId);
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(discoveryControllerProvider);
    final detail = state.selectedClinicDetail;
    final clinic = detail?.clinic;
    final error = state.clinicDetailError;


    return AppScaffold(

      appBar: AppBar(title: Text(strings.clinicDetailTitle)),

      useSafeArea: true,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              maxWidth: 960,
              child: state.isLoadingClinicDetail && clinic == null
                  ? _LoadingDetail(strings: strings)
                  : error != null
                      ? Card(
                          child: ErrorRetryState(

                            title: strings.clinicDetailLoadErrorTitle,
                            message: error.message,
                            retryLabel: strings.retry,
                            
                            onRetry: () {
                              _load();
                            },
                            variant: ErrorRetryVariant.compact,
                          ),
                        )
                      : clinic == null
                          ? Card(
                              child: EmptyState(
                                icon: Icons.local_hospital_outlined,

                                title: strings.clinicDetailNotFoundTitle,
                                hint: strings.clinicDetailNotFoundHint,

                                variant: EmptyStateVariant.compact,
                              ),
                            )
                          : _LoadedClinicDetail(clinic: clinic, doctors: detail?.doctors ?? const [], strings: strings),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedClinicDetail extends StatelessWidget {
  const _LoadedClinicDetail({required this.clinic, required this.doctors, required this.strings});

  final Clinic clinic;
  final List<ClinicDoctorSummary> doctors;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final latitude = clinic.latitude;
    final longitude = clinic.longitude;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClinicDetailSections(clinic: clinic, doctors: doctors),
        const SizedBox(height: AppTheme.spaceLg),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spaceLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: strings.clinicMapSectionTitle,
                  subtitle: strings.clinicMapRoutingNote,
                ),
                SizedBox(
                  height: 280,
                  child: latitude != null && longitude != null
                      ? DiscoveryMap(
                          places: [
                            DiscoveryMapPlace(
                              id: clinic.id,
                              latitude: latitude,
                              longitude: longitude,
                              type: DiscoveryPlaceType.fromString(clinic.type),
                            ),
                          ],
                          initialCenter: LatLng(latitude, longitude),
                          initialZoom: 15,
                          showControls: false,
                        )
                      : Center(child: Text(strings.clinicNoCoordinates)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingDetail extends StatelessWidget {
  const _LoadingDetail({required this.strings});

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
            Expanded(child: Text(strings.clinicLoadingDetails)),
          ],
        ),
      ),
    );
  }
}

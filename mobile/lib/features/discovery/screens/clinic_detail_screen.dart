import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/locale/locale_controller.dart';
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
    final state = ref.watch(discoveryControllerProvider);
    final detail = state.selectedClinicDetail;
    final clinic = detail?.clinic;
    final error = state.clinicDetailError;
    final ar = ref.watch(localeControllerProvider).languageCode == 'ar';

    return AppScaffold(
      appBar: AppBar(title: Text(ar ? 'تفاصيل العيادة' : 'Clinic details')),
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
                  ? const _LoadingDetail()
                  : error != null
                      ? Card(
                          child: ErrorRetryState(
                            title: ar ? 'تعذر تحميل العيادة' : 'Could not load clinic',
                            message: error.message,
                            retryLabel: ar ? 'إعادة المحاولة' : 'Retry',
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
                                title: ar ? 'العيادة غير موجودة' : 'Clinic not found',
                                hint: ar ? 'قد لا تكون هذه العيادة متاحة بعد الآن.' : 'This clinic may no longer be available.',
                                variant: EmptyStateVariant.compact,
                              ),
                            )
                          : _LoadedClinicDetail(clinic: clinic, doctors: detail?.doctors ?? const []),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedClinicDetail extends StatelessWidget {
  const _LoadedClinicDetail({required this.clinic, required this.doctors});

  final Clinic clinic;
  final List<ClinicDoctorSummary> doctors;

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
                const SectionHeader(
                  title: 'Map',
                  subtitle: 'Routing and directions are not enabled in this phase.',
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
                      : const Center(child: Text('No map coordinates are listed for this clinic.')),
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
  const _LoadingDetail();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(AppTheme.spaceLg),
        child: Row(
          children: [
            SizedBox.square(dimension: AppTheme.iconLg, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: AppTheme.spaceMd),
            Expanded(child: Text('Loading clinic details...')),
          ],
        ),
      ),
    );
  }
}

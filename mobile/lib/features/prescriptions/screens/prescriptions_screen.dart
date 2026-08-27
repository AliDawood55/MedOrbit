import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/date_formatting.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/status_badge.dart';
import '../models/prescription_model.dart';
import '../providers/prescriptions_provider.dart';
import '../widgets/prescription_detail_sheet.dart';

enum _PrescriptionDateFilter { any, last30Days, lastYear }

class PrescriptionsScreen extends ConsumerStatefulWidget {
  const PrescriptionsScreen({super.key});

  @override
  ConsumerState<PrescriptionsScreen> createState() =>
      _PrescriptionsScreenState();
}

class _PrescriptionsScreenState extends ConsumerState<PrescriptionsScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  String _query = '';
  String _status = 'all';
  _PrescriptionDateFilter _dateFilter = _PrescriptionDateFilter.any;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final _ = await ref.refresh(prescriptionsListProvider.future);
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _status = 'all';
      _dateFilter = _PrescriptionDateFilter.any;
    });
  }

  List<PrescriptionModel> _filteredPrescriptions(
    List<PrescriptionModel> prescriptions,
    String effectiveStatus,
  ) {
    final now = DateTime.now();
    final threshold = switch (_dateFilter) {
      _PrescriptionDateFilter.any => null,
      _PrescriptionDateFilter.last30Days => now.subtract(
        const Duration(days: 30),
      ),
      _PrescriptionDateFilter.lastYear => now.subtract(
        const Duration(days: 365),
      ),
    };

    final filtered =
        prescriptions.where((prescription) {
            final medicineNames = prescription.items.expand(
              (item) => [item.medicationNameAr, item.medicationNameEn],
            );
            final haystack = [
              prescription.prescriptionNumber,
              prescription.diagnosis,
              ...medicineNames,
            ].whereType<String>().join(' ').toLowerCase();
            final matchesQuery = _query.isEmpty || haystack.contains(_query);
            final matchesStatus =
                effectiveStatus == 'all' ||
                prescription.status == effectiveStatus;

            var matchesDate = true;
            if (threshold != null) {
              try {
                matchesDate = parseDateOnly(
                  prescription.prescriptionDate,
                ).isAfter(threshold);
              } catch (_) {
                matchesDate = false;
              }
            }
            return matchesQuery && matchesStatus && matchesDate;
          }).toList()
          ..sort((a, b) => b.prescriptionDate.compareTo(a.prescriptionDate));
    return filtered;
  }

  Future<void> _openPdf(PrescriptionModel prescription) async {
    final strings = ref.read(appStringsProvider);
    try {
      final bytes = await ref
          .read(prescriptionsApiProvider)
          .downloadPdf(prescription.id);
      final directory = await getTemporaryDirectory();
      final safeNumber = prescription.prescriptionNumber.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );
      final file = File(
        '${directory.path}/medorbit_prescription_$safeNumber.pdf',
      );
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (!mounted || result.type == ResultType.done) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.prescriptionPdfOpenError)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.prescriptionPdfDownloadError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final strings = ref.watch(appStringsProvider);
    final isArabic = ref.watch(localeControllerProvider).languageCode == 'ar';
    final listAsync = ref.watch(prescriptionsListProvider);

    return AppScaffold(
      appBar: AppBar(title: Text(strings.appName)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: AppTheme.spaceLg),
              child: ResponsiveContent(
                child: PageIntro(
                  title: strings.prescriptionsTitle,
                  subtitle: strings.prescriptionsSubtitle,
                  icon: Icons.medication_outlined,
                  color: AppTheme.accent,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            Expanded(
              child: listAsync.when(
                data: (prescriptions) {
                  final statuses =
                      prescriptions
                          .map((item) => item.status)
                          .where((status) => status.isNotEmpty)
                          .toSet()
                          .toList()
                        ..sort();
                  final effectiveStatus = statuses.contains(_status)
                      ? _status
                      : 'all';
                  final filtered = _filteredPrescriptions(
                    prescriptions,
                    effectiveStatus,
                  );

                  return _PrescriptionsData(
                    allPrescriptions: prescriptions,
                    filteredPrescriptions: filtered,
                    statuses: statuses,
                    selectedStatus: effectiveStatus,
                    selectedDateFilter: _dateFilter,
                    searchController: _searchController,
                    query: _query,
                    strings: strings,
                    isArabic: isArabic,
                    onSearchChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                    onClearSearch: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    onStatusChanged: (value) => setState(() => _status = value),
                    onDateChanged: (value) =>
                        setState(() => _dateFilter = value),
                    onClearFilters: _clearFilters,
                    onRefresh: _refresh,
                    onOpenPdf: _openPdf,
                  );
                },
                loading: () => _PrescriptionsLoading(
                  label: strings.loadingPrescriptions,
                  onRefresh: _refresh,
                ),
                error: (error, stackTrace) => _PrescriptionsError(
                  strings: strings,
                  onRetry: () => ref.invalidate(prescriptionsListProvider),
                  onRefresh: _refresh,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionsData extends StatelessWidget {
  const _PrescriptionsData({
    required this.allPrescriptions,
    required this.filteredPrescriptions,
    required this.statuses,
    required this.selectedStatus,
    required this.selectedDateFilter,
    required this.searchController,
    required this.query,
    required this.strings,
    required this.isArabic,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStatusChanged,
    required this.onDateChanged,
    required this.onClearFilters,
    required this.onRefresh,
    required this.onOpenPdf,
  });

  final List<PrescriptionModel> allPrescriptions;
  final List<PrescriptionModel> filteredPrescriptions;
  final List<String> statuses;
  final String selectedStatus;
  final _PrescriptionDateFilter selectedDateFilter;
  final TextEditingController searchController;
  final String query;
  final AppStrings strings;
  final bool isArabic;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<_PrescriptionDateFilter> onDateChanged;
  final VoidCallback onClearFilters;
  final Future<void> Function() onRefresh;
  final Future<void> Function(PrescriptionModel prescription) onOpenPdf;

  bool get hasActiveFilters =>
      query.isNotEmpty ||
      selectedStatus != 'all' ||
      selectedDateFilter != _PrescriptionDateFilter.any;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppTheme.pageHorizontalPadding(
      MediaQuery.sizeOf(context).width,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey<String>('prescriptions-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsetsDirectional.fromSTEB(
          horizontal,
          0,
          horizontal,
          AppTheme.spaceXl,
        ),
        children: [
          Align(
            alignment: AlignmentDirectional.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTheme.maxPhoneContentWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PrescriptionFilters(
                    statuses: statuses,
                    selectedStatus: selectedStatus,
                    selectedDateFilter: selectedDateFilter,
                    searchController: searchController,
                    query: query,
                    strings: strings,
                    onSearchChanged: onSearchChanged,
                    onClearSearch: onClearSearch,
                    onStatusChanged: onStatusChanged,
                    onDateChanged: onDateChanged,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  if (allPrescriptions.isEmpty)
                    Card(
                      child: EmptyState(
                        icon: Icons.medication_outlined,
                        title: strings.prescriptionsEmptyTitle,
                        hint: strings.prescriptionsEmptyHint,
                      ),
                    )
                  else if (filteredPrescriptions.isEmpty)
                    Card(
                      child: EmptyState(
                        icon: Icons.search_off_rounded,
                        title: strings.prescriptionsNoResultsTitle,
                        hint: strings.prescriptionsNoResultsHint,
                        action: hasActiveFilters
                            ? OutlinedButton.icon(
                                onPressed: onClearFilters,
                                icon: const Icon(Icons.filter_alt_off_rounded),
                                label: Text(strings.clearFilters),
                              )
                            : null,
                      ),
                    )
                  else ...[
                    SectionHeader(
                      title: strings.prescriptionResultsTitle,
                      trailing: StatusBadge(
                        label: strings.prescriptionResultsCount(
                          filteredPrescriptions.length,
                        ),
                        color: AppTheme.primary,
                      ),
                    ),
                    for (
                      var index = 0;
                      index < filteredPrescriptions.length;
                      index++
                    ) ...[
                      _PrescriptionCard(
                        prescription: filteredPrescriptions[index],
                        strings: strings,
                        isArabic: isArabic,
                        onViewDetails: () => showPrescriptionDetailSheet(
                          context,
                          filteredPrescriptions[index],
                          strings,
                          isArabic,
                          onOpenPdf,
                        ),
                      ),
                      if (index != filteredPrescriptions.length - 1)
                        const SizedBox(height: AppTheme.spaceMd),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrescriptionFilters extends StatelessWidget {
  const _PrescriptionFilters({
    required this.statuses,
    required this.selectedStatus,
    required this.selectedDateFilter,
    required this.searchController,
    required this.query,
    required this.strings,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onStatusChanged,
    required this.onDateChanged,
  });

  final List<String> statuses;
  final String selectedStatus;
  final _PrescriptionDateFilter selectedDateFilter;
  final TextEditingController searchController;
  final String query;
  final AppStrings strings;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<_PrescriptionDateFilter> onDateChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: strings.prescriptionFiltersLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: strings.prescriptionFiltersTitle,
                padding: const EdgeInsets.only(bottom: AppTheme.spaceMd),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final largeText = AppTheme.usesLargeText(context);
                  final useRow =
                      constraints.maxWidth >= AppTheme.wideBreakpoint &&
                      !largeText;
                  final search = AppTextField(
                    label: strings.prescriptionSearchLabel,
                    hintText: strings.prescriptionSearchPlaceholder,
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: strings.clearSearch,
                            onPressed: onClearSearch,
                            icon: const Icon(Icons.close_rounded),
                          ),
                    semanticLabel: strings.prescriptionSearchLabel,
                    onChanged: onSearchChanged,
                  );
                  final date = DropdownButtonFormField<_PrescriptionDateFilter>(
                    key: ValueKey(selectedDateFilter),
                    initialValue: selectedDateFilter,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.prescriptionDateFilterLabel,
                      prefixIcon: const Icon(Icons.date_range_outlined),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: _PrescriptionDateFilter.any,
                        child: Text(strings.filterAnyDate),
                      ),
                      DropdownMenuItem(
                        value: _PrescriptionDateFilter.last30Days,
                        child: Text(strings.filterLast30Days),
                      ),
                      DropdownMenuItem(
                        value: _PrescriptionDateFilter.lastYear,
                        child: Text(strings.filterLastYear),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) onDateChanged(value);
                    },
                  );

                  if (useRow) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: search),
                        const SizedBox(width: AppTheme.spaceMd),
                        Expanded(child: date),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      search,
                      const SizedBox(height: AppTheme.spaceMd),
                      date,
                    ],
                  );
                },
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Text(
                strings.prescriptionStatusFilterLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Wrap(
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceSm,
                children: [
                  _StatusFilterChip(
                    status: 'all',
                    label: strings.filterAllPrescriptions,
                    selected: selectedStatus == 'all',
                    onSelected: onStatusChanged,
                  ),
                  for (final status in statuses)
                    _StatusFilterChip(
                      status: status,
                      label: prescriptionStatusVisual(status, strings).$1,
                      selected: selectedStatus == status,
                      onSelected: onStatusChanged,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({
    required this.status,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String status;
  final String label;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) => onSelected(status),
      ),
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({
    required this.prescription,
    required this.strings,
    required this.isArabic,
    required this.onViewDetails,
  });

  final PrescriptionModel prescription;
  final AppStrings strings;
  final bool isArabic;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (statusLabel, statusColor) = prescriptionStatusVisual(
      prescription.status,
      strings,
    );
    final title = prescriptionDisplayTitle(prescription, isArabic, strings);
    final issuedDate = formatDate(
      parseDateOnly(prescription.prescriptionDate),
      localeCode: isArabic ? 'ar' : 'en',
    );
    final validUntil = prescription.validUntil == null
        ? null
        : formatDate(
            parseDateOnly(prescription.validUntil!),
            localeCode: isArabic ? 'ar' : 'en',
          );
    final preview = prescription.instructions?.trim().isNotEmpty == true
        ? prescription.instructions!.trim()
        : prescription.doctorNotes?.trim().isNotEmpty == true
        ? prescription.doctorNotes!.trim()
        : null;
    final semanticLabel = [
      strings.prescriptionNumberValue(prescription.prescriptionNumber),
      title,
      statusLabel,
      strings.issuedDateValue(issuedDate),
      strings.medicationCount(prescription.items.length),
    ].join('. ');

    return Semantics(
      container: true,
      label: semanticLabel,
      child: Card(
        elevation: AppTheme.elevation1,
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final largeText = AppTheme.usesLargeText(context);
                  final stack =
                      constraints.maxWidth < AppTheme.compactBreakpoint ||
                      largeText;
                  final icon = Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    ),
                    child: const Icon(
                      Icons.medication_outlined,
                      color: AppTheme.accent,
                      size: AppTheme.iconLg,
                    ),
                  );
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(
                          prescription.prescriptionNumber,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spaceXs),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: AppTheme.weightExtraBold,
                        ),
                      ),
                    ],
                  );

                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            icon,
                            const SizedBox(width: AppTheme.spaceMd),
                            Expanded(child: heading),
                          ],
                        ),
                        const SizedBox(height: AppTheme.spaceMd),
                        StatusBadge(label: statusLabel, color: statusColor),
                      ],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      icon,
                      const SizedBox(width: AppTheme.spaceMd),
                      Expanded(child: heading),
                      const SizedBox(width: AppTheme.spaceSm),
                      StatusBadge(label: statusLabel, color: statusColor),
                    ],
                  );
                },
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Wrap(
                spacing: AppTheme.spaceMd,
                runSpacing: AppTheme.spaceSm,
                children: [
                  _PrescriptionMeta(
                    icon: Icons.calendar_today_outlined,
                    label: strings.issuedDateLabel,
                    value: issuedDate,
                    textDirection: TextDirection.ltr,
                  ),
                  if (validUntil != null)
                    _PrescriptionMeta(
                      icon: Icons.event_available_outlined,
                      label: strings.detailValidUntil,
                      value: validUntil,
                      textDirection: TextDirection.ltr,
                    ),
                  _PrescriptionMeta(
                    icon: Icons.medication_liquid_outlined,
                    label: strings.detailMedications,
                    value: strings.medicationCount(prescription.items.length),
                  ),
                ],
              ),
              if (prescription.diagnosis?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppTheme.spaceMd),
                _TextPreview(
                  label: strings.detailDiagnosis,
                  value: prescription.diagnosis!.trim(),
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: AppTheme.spaceSm),
                _TextPreview(
                  label: prescription.instructions?.trim().isNotEmpty == true
                      ? strings.detailInstructions
                      : strings.doctorNotes,
                  value: preview,
                ),
              ],
              const SizedBox(height: AppTheme.spaceMd),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: onViewDetails,
                  iconAlignment: IconAlignment.end,
                  icon: Icon(
                    AppTheme.directionalForwardIconOf(context),
                    size: AppTheme.iconSm,
                  ),
                  label: Text(strings.viewPrescriptionDetails),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrescriptionMeta extends StatelessWidget {
  const _PrescriptionMeta({
    required this.icon,
    required this.label,
    required this.value,
    this.textDirection,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.iconSm, color: AppTheme.primary),
          const SizedBox(width: AppTheme.spaceXs),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
                Directionality(
                  textDirection: textDirection ?? Directionality.of(context),
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spaceMd),
      decoration: BoxDecoration(
        color: AppTheme.mutedSurfaceOf(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spaceXs),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _PrescriptionsLoading extends StatelessWidget {
  const _PrescriptionsLoading({required this.label, required this.onRefresh});

  final String label;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppTheme.spaceXl),
        children: [
          ResponsiveContent(
            child: Semantics(
              liveRegion: true,
              label: label,
              child: Column(
                children: [
                  const _FilterSkeleton(),
                  const SizedBox(height: AppTheme.spaceLg),
                  for (var index = 0; index < 3; index++) ...[
                    const _PrescriptionSkeletonCard(),
                    if (index != 2) const SizedBox(height: AppTheme.spaceMd),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSkeleton extends StatelessWidget {
  const _FilterSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          children: [
            const _SkeletonLine(widthFactor: 0.35),
            const SizedBox(height: AppTheme.spaceMd),
            const _SkeletonLine(widthFactor: 1, height: 48),
            const SizedBox(height: AppTheme.spaceMd),
            Row(
              children: [
                for (var index = 0; index < 3; index++) ...[
                  const Expanded(
                    child: _SkeletonLine(widthFactor: 1, height: 32),
                  ),
                  if (index != 2) const SizedBox(width: AppTheme.spaceSm),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionSkeletonCard extends StatelessWidget {
  const _PrescriptionSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.mutedSurfaceOf(context),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
            ),
            const SizedBox(width: AppTheme.spaceMd),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonLine(widthFactor: 0.45),
                  SizedBox(height: AppTheme.spaceSm),
                  _SkeletonLine(widthFactor: 0.75),
                  SizedBox(height: AppTheme.spaceMd),
                  _SkeletonLine(widthFactor: 1),
                  SizedBox(height: AppTheme.spaceSm),
                  _SkeletonLine(widthFactor: 0.7),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor, this.height = 14});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.mutedSurfaceOf(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        ),
      ),
    );
  }
}

class _PrescriptionsError extends StatelessWidget {
  const _PrescriptionsError({
    required this.strings,
    required this.onRetry,
    required this.onRefresh,
  });

  final AppStrings strings;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppTheme.spaceXl),
        children: [
          ResponsiveContent(
            child: Card(
              child: ErrorRetryState(
                title: strings.prescriptionsLoadErrorTitle,
                message: strings.errorGeneric,
                retryLabel: strings.retry,
                onRetry: onRetry,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

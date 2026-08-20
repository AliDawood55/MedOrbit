import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../models/record_entry_model.dart';
import '../providers/records_provider.dart';
import '../widgets/record_detail_sheet.dart';

enum _RecordDateFilter { any, last30Days, lastYear }

class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchController = TextEditingController();
  String _query = '';
  String _entryType = 'all';
  _RecordDateFilter _dateFilter = _RecordDateFilter.any;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final _ = await ref.refresh(recordsTimelineProvider.future);
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _entryType = 'all';
      _dateFilter = _RecordDateFilter.any;
    });
  }

  List<RecordEntryModel> _filterEntries(
    List<RecordEntryModel> entries,
    String effectiveType,
    bool isArabic,
    AppStrings strings,
  ) {
    final now = DateTime.now();
    final threshold = switch (_dateFilter) {
      _RecordDateFilter.any => null,
      _RecordDateFilter.last30Days =>
        now.subtract(const Duration(days: 30)),
      _RecordDateFilter.lastYear =>
        now.subtract(const Duration(days: 365)),
    };

    return entries.where((entry) {
      final medicineNames = entry.items.expand(
        (item) => [item.medicationNameAr, item.medicationNameEn],
      );
      final haystack = [
        recordEntryTitle(entry, strings, isArabic),
        recordEntryIdentifier(entry),
        entry.id,
        entry.diagnosis,
        entry.doctorFullName(isArabic),
        entry.doctorFirstNameAr,
        entry.doctorFirstNameEn,
        entry.doctorLastNameAr,
        entry.doctorLastNameEn,
        entry.chiefComplaint,
        entry.reasonForVisit,
        ...medicineNames,
      ].whereType<String>().join(' ').toLowerCase();
      final matchesQuery = _query.isEmpty || haystack.contains(_query);
      final matchesType =
          effectiveType == 'all' || entry.entryType == effectiveType;

      var matchesDate = true;
      if (threshold != null) {
        final dateValue = recordEntryDate(entry);
        if (dateValue == null) {
          matchesDate = false;
        } else {
          try {
            matchesDate = parseDateOnly(dateValue).isAfter(threshold);
          } catch (_) {
            matchesDate = false;
          }
        }
      }
      return matchesQuery && matchesType && matchesDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final strings = ref.watch(appStringsProvider);
    final isArabic =
        ref.watch(localeControllerProvider).languageCode == 'ar';
    final timelineAsync = ref.watch(recordsTimelineProvider);

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
                  title: strings.recordsTitle,
                  subtitle: strings.recordsSubtitle,
                  icon: Icons.monitor_heart_outlined,
                  color: AppTheme.secondary,
                ),
              ),
            ),
            const SizedBox(height: AppTheme.spaceLg),
            Expanded(
              child: timelineAsync.when(
                data: (entries) {
                  final entryTypes = entries
                      .map((entry) => entry.entryType)
                      .where((type) => type.isNotEmpty)
                      .toSet()
                      .toList();
                  final effectiveType = entryTypes.contains(_entryType)
                      ? _entryType
                      : 'all';
                  final filtered = _filterEntries(
                    entries,
                    effectiveType,
                    isArabic,
                    strings,
                  );

                  return _RecordsData(
                    allEntries: entries,
                    filteredEntries: filtered,
                    entryTypes: entryTypes,
                    selectedType: effectiveType,
                    selectedDateFilter: _dateFilter,
                    searchController: _searchController,
                    query: _query,
                    strings: strings,
                    isArabic: isArabic,
                    onSearchChanged: (value) => setState(
                      () => _query = value.trim().toLowerCase(),
                    ),
                    onClearSearch: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    onTypeChanged: (value) =>
                        setState(() => _entryType = value),
                    onDateChanged: (value) =>
                        setState(() => _dateFilter = value),
                    onClearFilters: _clearFilters,
                    onRefresh: _refresh,
                  );
                },
                loading: () => _RecordsLoading(
                  label: strings.loadingMedicalRecords,
                  onRefresh: _refresh,
                ),
                error: (error, stackTrace) => _RecordsError(
                  strings: strings,
                  onRetry: () => ref.invalidate(recordsTimelineProvider),
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

class _RecordsData extends StatelessWidget {
  const _RecordsData({
    required this.allEntries,
    required this.filteredEntries,
    required this.entryTypes,
    required this.selectedType,
    required this.selectedDateFilter,
    required this.searchController,
    required this.query,
    required this.strings,
    required this.isArabic,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onTypeChanged,
    required this.onDateChanged,
    required this.onClearFilters,
    required this.onRefresh,
  });

  final List<RecordEntryModel> allEntries;
  final List<RecordEntryModel> filteredEntries;
  final List<String> entryTypes;
  final String selectedType;
  final _RecordDateFilter selectedDateFilter;
  final TextEditingController searchController;
  final String query;
  final AppStrings strings;
  final bool isArabic;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<_RecordDateFilter> onDateChanged;
  final VoidCallback onClearFilters;
  final Future<void> Function() onRefresh;

  bool get hasActiveFilters => query.isNotEmpty ||
      selectedType != 'all' ||
      selectedDateFilter != _RecordDateFilter.any;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppTheme.pageHorizontalPadding(
      MediaQuery.sizeOf(context).width,
    );
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey<String>('medical-records-timeline'),
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
                  _RecordFilters(
                    entryTypes: entryTypes,
                    selectedType: selectedType,
                    selectedDateFilter: selectedDateFilter,
                    searchController: searchController,
                    query: query,
                    strings: strings,
                    onSearchChanged: onSearchChanged,
                    onClearSearch: onClearSearch,
                    onTypeChanged: onTypeChanged,
                    onDateChanged: onDateChanged,
                  ),
                  const SizedBox(height: AppTheme.spaceLg),
                  if (allEntries.isEmpty)
                    Card(
                      child: Semantics(
                        liveRegion: true,
                        child: EmptyState(
                          icon: Icons.folder_open_outlined,
                          title: strings.recordsEmptyTitle,
                          hint: strings.recordsEmptyHint,
                        ),
                      ),
                    )
                  else if (filteredEntries.isEmpty)
                    Card(
                      child: Semantics(
                        liveRegion: true,
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          title: strings.recordsNoResultsTitle,
                          hint: strings.recordsNoResultsHint,
                          action: hasActiveFilters
                              ? OutlinedButton.icon(
                                  onPressed: onClearFilters,
                                  icon: const Icon(
                                    Icons.filter_alt_off_rounded,
                                  ),
                                  label: Text(strings.clearFilters),
                                )
                              : null,
                        ),
                      ),
                    )
                  else ...[
                    SectionHeader(
                      title: strings.medicalTimelineTitle,
                      subtitle: strings.medicalTimelineSubtitle,
                      trailing: StatusBadge(
                        label: strings.recordResultsCount(
                          filteredEntries.length,
                        ),
                        color: AppTheme.primary,
                      ),
                    ),
                    _ChronologicalTimeline(
                      entries: filteredEntries,
                      strings: strings,
                      isArabic: isArabic,
                    ),
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

class _RecordFilters extends StatelessWidget {
  const _RecordFilters({
    required this.entryTypes,
    required this.selectedType,
    required this.selectedDateFilter,
    required this.searchController,
    required this.query,
    required this.strings,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onTypeChanged,
    required this.onDateChanged,
  });

  final List<String> entryTypes;
  final String selectedType;
  final _RecordDateFilter selectedDateFilter;
  final TextEditingController searchController;
  final String query;
  final AppStrings strings;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<_RecordDateFilter> onDateChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: strings.recordFiltersLabel,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(
                title: strings.recordFiltersTitle,
                padding: const EdgeInsets.only(
                  bottom: AppTheme.spaceMd,
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final largeText = AppTheme.usesLargeText(context);
                  final useRow = constraints.maxWidth >=
                          AppTheme.wideBreakpoint &&
                      !largeText;
                  final search = AppTextField(
                    label: strings.recordSearchLabel,
                    hintText: strings.recordSearchPlaceholder,
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
                    semanticLabel: strings.recordSearchLabel,
                    onChanged: onSearchChanged,
                  );
                  final date = DropdownButtonFormField<_RecordDateFilter>(
                    key: ValueKey(selectedDateFilter),
                    initialValue: selectedDateFilter,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.recordDateFilterLabel,
                      prefixIcon: const Icon(Icons.date_range_outlined),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: _RecordDateFilter.any,
                        child: Text(strings.filterAnyDate),
                      ),
                      DropdownMenuItem(
                        value: _RecordDateFilter.last30Days,
                        child: Text(strings.filterLast30Days),
                      ),
                      DropdownMenuItem(
                        value: _RecordDateFilter.lastYear,
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
                strings.recordTypeFilterLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: AppTheme.spaceSm),
              Wrap(
                spacing: AppTheme.spaceSm,
                runSpacing: AppTheme.spaceSm,
                children: [
                  _TypeFilterChip(
                    value: 'all',
                    label: strings.filterAllRecordTypes,
                    selected: selectedType == 'all',
                    onSelected: onTypeChanged,
                  ),
                  for (final type in entryTypes)
                    _TypeFilterChip(
                      value: type,
                      label: recordEntryTypeLabel(type, strings),
                      selected: selectedType == type,
                      onSelected: onTypeChanged,
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

class _TypeFilterChip extends StatelessWidget {
  const _TypeFilterChip({
    required this.value,
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String value;
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
        onSelected: (_) => onSelected(value),
      ),
    );
  }
}

class _ChronologicalTimeline extends StatelessWidget {
  const _ChronologicalTimeline({
    required this.entries,
    required this.strings,
    required this.isArabic,
  });

  final List<RecordEntryModel> entries;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    String? previousDateKey;
    final children = <Widget>[];

    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final dateValue = recordEntryDate(entry);
      final dateKey = dateValue?.split('T').first ?? '';
      final startsGroup = dateKey != previousDateKey;
      final nextDate = index + 1 < entries.length
          ? recordEntryDate(entries[index + 1])?.split('T').first
          : null;
      final connectsToNext = dateKey.isNotEmpty && dateKey == nextDate;

      if (startsGroup) {
        if (children.isNotEmpty) {
          children.add(const SizedBox(height: AppTheme.spaceLg));
        }
        children.add(
          _TimelineDateHeader(
            dateValue: dateValue,
            strings: strings,
            isArabic: isArabic,
          ),
        );
        children.add(const SizedBox(height: AppTheme.spaceMd));
      }

      children.add(
        _TimelineEntry(
          entry: entry,
          strings: strings,
          isArabic: isArabic,
          showConnector: connectsToNext,
          onViewDetails: () => showRecordDetailSheet(
            context,
            entry,
            strings,
            isArabic,
          ),
        ),
      );
      if (connectsToNext) {
        children.add(const SizedBox(height: AppTheme.spaceMd));
      }
      previousDateKey = dateKey;
    }

    return Column(children: children);
  }
}

class _TimelineDateHeader extends StatelessWidget {
  const _TimelineDateHeader({
    required this.dateValue,
    required this.strings,
    required this.isArabic,
  });

  final String? dateValue;
  final AppStrings strings;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    String label = strings.dateUnavailable;
    if (dateValue != null) {
      try {
        label = formatDate(
          parseDateOnly(dateValue!),
          localeCode: isArabic ? 'ar' : 'en',
        );
      } catch (_) {
        label = dateValue!;
      }
    }
    return Semantics(
      header: true,
      label: label,
      child: Row(
        children: [
          const Icon(
            Icons.calendar_month_outlined,
            size: AppTheme.iconMd,
            color: AppTheme.primary,
          ),
          const SizedBox(width: AppTheme.spaceSm),
          Flexible(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: AppTheme.weightBold,
                    ),
              ),
            ),
          ),
          Expanded(child: Divider(color: Theme.of(context).dividerColor)),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.entry,
    required this.strings,
    required this.isArabic,
    required this.showConnector,
    required this.onViewDetails,
  });

  final RecordEntryModel entry;
  final AppStrings strings;
  final bool isArabic;
  final bool showConnector;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final visual = recordEntryVisual(entry, strings);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (showConnector)
          PositionedDirectional(
            start: 21,
            top: 44,
            bottom: -AppTheme.spaceMd,
            child: Container(
              width: 2,
              color: visual.color.withValues(alpha: 0.25),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: visual.color.withValues(alpha: 0.28),
                ),
              ),
              child: Icon(
                visual.icon,
                color: visual.color,
                size: AppTheme.iconMd,
              ),
            ),
            const SizedBox(width: AppTheme.spaceMd),
            Expanded(
              child: _RecordCard(
                entry: entry,
                strings: strings,
                isArabic: isArabic,
                visual: visual,
                onViewDetails: onViewDetails,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.entry,
    required this.strings,
    required this.isArabic,
    required this.visual,
    required this.onViewDetails,
  });

  final RecordEntryModel entry;
  final AppStrings strings;
  final bool isArabic;
  final RecordEntryVisual visual;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = recordEntryTitle(entry, strings, isArabic);
    final doctor = entry.doctorFullName(isArabic);
    final specialty = entry.specialty(isArabic);
    final identifier = recordEntryIdentifier(entry);
    final statusVisual = recordStatusVisual(
      entry.status,
      strings,
      entryType: entry.entryType,
    );
    final note = recordEntryNotePreview(entry);
    final semanticLabel = [
      visual.label,
      title,
      ?doctor,
      if (statusVisual != null) statusVisual.$1,
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
                  final stack = constraints.maxWidth <
                          AppTheme.compactBreakpoint ||
                      AppTheme.usesLargeText(context);
                  final heading = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        visual.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: visual.color,
                          fontWeight: AppTheme.weightBold,
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
                  final badge = statusVisual == null
                      ? null
                      : StatusBadge(
                          label: statusVisual.$1,
                          color: statusVisual.$2,
                        );
                  if (stack) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        heading,
                        if (badge != null) ...[
                          const SizedBox(height: AppTheme.spaceSm),
                          badge,
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: heading),
                      if (badge != null) ...[
                        const SizedBox(width: AppTheme.spaceSm),
                        badge,
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: AppTheme.spaceMd),
              Wrap(
                spacing: AppTheme.spaceMd,
                runSpacing: AppTheme.spaceSm,
                children: [
                  if (identifier != null)
                    _RecordMeta(
                      icon: Icons.tag_rounded,
                      value: identifier,
                      textDirection: TextDirection.ltr,
                    ),
                  if (doctor != null)
                    _RecordMeta(
                      icon: Icons.medical_information_outlined,
                      value: doctor,
                    ),
                  if (specialty != null)
                    _RecordMeta(
                      icon: Icons.local_hospital_outlined,
                      value: specialty,
                    ),
                  if (entry.entryType == 'prescription')
                    _RecordMeta(
                      icon: Icons.medication_outlined,
                      value: strings.medicationCount(entry.items.length),
                    ),
                ],
              ),
              if (entry.diagnosis?.trim().isNotEmpty == true) ...[
                const SizedBox(height: AppTheme.spaceMd),
                _RecordTextPreview(
                  label: strings.detailDiagnosis,
                  value: entry.diagnosis!.trim(),
                ),
              ],
              if (note != null && note != entry.diagnosis?.trim()) ...[
                const SizedBox(height: AppTheme.spaceSm),
                _RecordTextPreview(
                  label: strings.recordNotesPreviewLabel,
                  value: note,
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
                  label: Text(strings.viewRecordDetails),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordMeta extends StatelessWidget {
  const _RecordMeta({
    required this.icon,
    required this.value,
    this.textDirection,
  });

  final IconData icon;
  final String value;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppTheme.iconSm, color: AppTheme.primary),
          const SizedBox(width: AppTheme.spaceXs),
          Flexible(
            child: Directionality(
              textDirection:
                  textDirection ?? Directionality.of(context),
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTextPreview extends StatelessWidget {
  const _RecordTextPreview({required this.label, required this.value});

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

class _RecordsLoading extends StatelessWidget {
  const _RecordsLoading({required this.label, required this.onRefresh});

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
                    const _TimelineSkeleton(),
                    if (index != 2)
                      const SizedBox(height: AppTheme.spaceMd),
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
                  if (index != 2)
                    const SizedBox(width: AppTheme.spaceSm),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.mutedSurfaceOf(context),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppTheme.spaceMd),
        const Expanded(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(AppTheme.spaceLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonLine(widthFactor: 0.35),
                  SizedBox(height: AppTheme.spaceSm),
                  _SkeletonLine(widthFactor: 0.75),
                  SizedBox(height: AppTheme.spaceMd),
                  _SkeletonLine(widthFactor: 1),
                  SizedBox(height: AppTheme.spaceSm),
                  _SkeletonLine(widthFactor: 0.65),
                ],
              ),
            ),
          ),
        ),
      ],
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

class _RecordsError extends StatelessWidget {
  const _RecordsError({
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
                title: strings.recordsLoadErrorTitle,
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

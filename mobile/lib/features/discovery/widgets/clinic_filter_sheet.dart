import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/discovery_provider.dart';

const clinicFacilityTypes = <String>[
  'clinic',
  'pharmacy',
  'hospital',
  'laboratory',
  'dental',
  'radiology',
  'emergency',
];

class ClinicFilterSheet extends ConsumerStatefulWidget {
  const ClinicFilterSheet({
    super.key,
    required this.initialFilters,
    required this.regions,
    required this.services,
    required this.insuranceOptions,
    required this.onApply,
    required this.onClear,
  });

  final ClinicFilters initialFilters;
  final List<String> regions;
  final List<String> services;
  final List<String> insuranceOptions;
  final ValueChanged<ClinicFilters> onApply;
  final VoidCallback onClear;

  @override
  ConsumerState<ClinicFilterSheet> createState() => _ClinicFilterSheetState();
}

class _ClinicFilterSheetState extends ConsumerState<ClinicFilterSheet> {
  late ClinicFilters _filters;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppTheme.spaceLg,
          AppTheme.spaceLg,
          AppTheme.spaceLg,
          AppTheme.spaceLg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.82),
          child: SingleChildScrollView(
            key: const ValueKey('clinic-filter-scrollable'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.clinicFilterSheetTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTheme.spaceMd),
                _ChoiceSection(
                  title: strings.clinicFilterFacilityType,
                  selected: _filters.type,
                  values: clinicFacilityTypes,
                  allLabel: strings.clinicFilterAllTypes,
                  valueLabel: (value) => strings.clinicTypeLabelFor(value),
                  keyPrefix: 'clinic-filter-type',
                  onSelected: (value) => setState(() => _filters = _filters.copyWith(type: value, clearType: value == null)),
                ),
                _ChoiceSection(
                  title: strings.doctorFilterRegionLabel,
                  selected: _filters.region,
                  values: widget.regions,
                  allLabel: strings.clinicFilterAnyRegion,
                  onSelected: (value) => setState(() => _filters = _filters.copyWith(region: value, clearRegion: value == null)),
                ),
                _ChoiceSection(
                  title: strings.clinicFilterService,
                  selected: _filters.service,
                  values: widget.services,
                  allLabel: strings.clinicFilterAnyService,
                  onSelected: (value) => setState(() => _filters = _filters.copyWith(service: value, clearService: value == null)),
                ),
                _ChoiceSection(
                  title: strings.clinicFilterInsurance,
                  selected: _filters.insurance,
                  values: widget.insuranceOptions,
                  allLabel: strings.clinicFilterAnyInsurance,
                  onSelected: (value) => setState(() => _filters = _filters.copyWith(insurance: value, clearInsurance: value == null)),
                ),
                const SizedBox(height: AppTheme.spaceLg),
                Wrap(
                  spacing: AppTheme.spaceSm,
                  runSpacing: AppTheme.spaceSm,
                  alignment: WrapAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        widget.onClear();
                        Navigator.pop(context);
                      },
                      child: Text(strings.clearFilters),
                    ),
                    PrimaryButton(
                      key: const ValueKey('clinic-filter-apply'),
                      label: strings.discoveryApplyFiltersButton,
                      icon: Icons.check_rounded,
                      onPressed: () {
                        widget.onApply(_filters.copyWith(page: 1));
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceSection extends StatelessWidget {
  const _ChoiceSection({
    required this.title,
    required this.selected,
    required this.values,
    required this.allLabel,
    required this.onSelected,
    this.keyPrefix,
    this.valueLabel,
  });

  final String title;
  final String? selected;
  final List<String> values;
  final String allLabel;
  final ValueChanged<String?> onSelected;
  final String? keyPrefix;
  final String Function(String value)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final items = values.where((value) => value.trim().isNotEmpty).toSet().toList()..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spaceLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppTheme.spaceSm),
          Wrap(
            spacing: AppTheme.spaceXs,
            runSpacing: AppTheme.spaceXs,
            children: [
              ChoiceChip(
                key: keyPrefix == null ? null : ValueKey('$keyPrefix-all'),
                label: Text(allLabel),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
              for (final item in items)
                ChoiceChip(
                  key: keyPrefix == null ? null : ValueKey('$keyPrefix-$item'),
                  label: Text(valueLabel == null ? item : valueLabel!(item)),
                  selected: selected == item,
                  onSelected: (_) => onSelected(item),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

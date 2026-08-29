import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../providers/discovery_provider.dart';

class DoctorFilterSheet extends ConsumerStatefulWidget {
  const DoctorFilterSheet({super.key, required this.initialFilters, required this.regions, required this.onApply, required this.onClear});
  final DoctorFilters initialFilters;
  final List<String> regions;
  final ValueChanged<DoctorFilters> onApply;
  final VoidCallback onClear;
  @override
  ConsumerState<DoctorFilterSheet> createState() => _DoctorFilterSheetState();
}

class _DoctorFilterSheetState extends ConsumerState<DoctorFilterSheet> {
  late DoctorFilters _filters;
  late final TextEditingController _minFee;
  late final TextEditingController _maxFee;
  @override
  void initState() { super.initState(); _filters = widget.initialFilters; _minFee = TextEditingController(text: _filters.minFee?.toString()); _maxFee = TextEditingController(text: _filters.maxFee?.toString()); }
  @override
  void dispose() { _minFee.dispose(); _maxFee.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final invalidFee = _filters.minFee != null && _filters.maxFee != null && _filters.minFee! > _filters.maxFee!;
    return SafeArea(child: Padding(
      padding: EdgeInsets.fromLTRB(AppTheme.spaceLg, AppTheme.spaceLg, AppTheme.spaceLg, AppTheme.spaceLg + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82), child: SingleChildScrollView(
        key: const ValueKey('doctor-filter-scrollable'), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(strings.doctorFilterSheetTitle, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: AppTheme.spaceMd),
          _Choices(title: strings.doctorFilterRegionLabel, anyLabel: strings.discoveryAnyOption, selected: _filters.region, items: widget.regions, onChanged: (v) => setState(() => _filters = _filters.copyWith(region: v, clearRegion: v == null))),
          _Choices(title: strings.doctorFilterMinRatingLabel, anyLabel: strings.discoveryAnyOption, selected: _filters.minRating?.toString(), items: const ['3', '4', '4.5'], onChanged: (v) => setState(() => _filters = _filters.copyWith(minRating: double.tryParse(v ?? ''), clearMinRating: v == null))),
          Row(children: [Expanded(child: AppTextField(label: strings.doctorFilterMinFeeLabel, controller: _minFee, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => setState(() => _filters = _filters.copyWith(minFee: double.tryParse(v), clearMinFee: v.isEmpty)))), const SizedBox(width: AppTheme.spaceSm), Expanded(child: AppTextField(label: strings.doctorFilterMaxFeeLabel, controller: _maxFee, keyboardType: const TextInputType.numberWithOptions(decimal: true), errorText: invalidFee ? strings.doctorFilterFeeRangeError : null, onChanged: (v) => setState(() => _filters = _filters.copyWith(maxFee: double.tryParse(v), clearMaxFee: v.isEmpty))))]),
          const SizedBox(height: AppTheme.spaceLg), Wrap(alignment: WrapAlignment.end, spacing: AppTheme.spaceSm, runSpacing: AppTheme.spaceSm, children: [TextButton(onPressed: () { widget.onClear(); Navigator.pop(context); }, child: Text(strings.clearFilters)), PrimaryButton(key: const ValueKey('doctor-filter-apply'), label: strings.discoveryApplyFiltersButton, icon: Icons.check_rounded, onPressed: invalidFee ? null : () { widget.onApply(_filters.copyWith(page: 1)); Navigator.pop(context); })]),
        ]),
      )),
    ));
  }
}

class _Choices extends StatelessWidget {
  const _Choices({required this.title, required this.anyLabel, required this.selected, required this.items, required this.onChanged});
  final String title; final String anyLabel; final String? selected; final List<String> items; final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) { final values = items.where((item) => item.trim().isNotEmpty).toSet().toList()..sort(); return Padding(padding: const EdgeInsets.only(bottom: AppTheme.spaceLg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleSmall), const SizedBox(height: AppTheme.spaceSm), Wrap(spacing: AppTheme.spaceXs, runSpacing: AppTheme.spaceXs, children: [ChoiceChip(label: Text(anyLabel), selected: selected == null, onSelected: (_) => onChanged(null)), for (final item in values) ChoiceChip(key: ValueKey('doctor-filter-$title-$item'), label: Text(item), selected: selected == item, onSelected: (_) => onChanged(item))]) ])); }
}

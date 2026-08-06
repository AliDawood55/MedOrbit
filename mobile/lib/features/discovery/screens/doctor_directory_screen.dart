import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../../../shared/widgets/primary_button.dart';
import '../models/doctor_models.dart';
import '../providers/discovery_provider.dart';
import '../widgets/doctor_filter_sheet.dart';
import '../widgets/doctor_result_card.dart';

class DoctorDirectoryScreen extends ConsumerStatefulWidget { const DoctorDirectoryScreen({super.key}); @override ConsumerState<DoctorDirectoryScreen> createState() => _DoctorDirectoryScreenState(); }
class _DoctorDirectoryScreenState extends ConsumerState<DoctorDirectoryScreen> { final _search = TextEditingController(); Timer? _debounce;
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(discoveryControllerProvider.notifier).loadDoctors()); }
  @override void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoveryControllerProvider);
    return AppScaffold(
      appBar: AppBar(title: const Text('Doctor directory')),
      useSafeArea: true,
      keyboardAware: true,
      body: RefreshIndicator(
        onRefresh: () => ref.read(discoveryControllerProvider.notifier).loadDoctors(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
          children: [
            ResponsiveContent(
              maxWidth: 960,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const PageIntro(title: 'Find a doctor', subtitle: 'Browse doctors listed by healthcare facilities around Nablus.', icon: Icons.person_search_outlined),
                const SizedBox(height: AppTheme.spaceLg),
                Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: AppTextField(label: 'Search doctors', hintText: 'Name or specialty', controller: _search, prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _clear, icon: const Icon(Icons.close_rounded), tooltip: 'Clear search'), onChanged: _onSearch))),
                const SizedBox(height: AppTheme.spaceLg),
                _Summary(filters: state.doctorFilters, count: state.doctors.length, onFilters: () => _filters(state)),
                const SizedBox(height: AppTheme.spaceLg),
                if (state.isLoadingDoctors) const _Loading()
                else if (state.doctorListError != null) Card(child: ErrorRetryState(title: 'Could not load doctors', message: state.doctorListError!.message, retryLabel: 'Retry', onRetry: () => ref.read(discoveryControllerProvider.notifier).loadDoctors(), variant: ErrorRetryVariant.compact))
                else if (state.doctors.isEmpty) const Card(child: EmptyState(icon: Icons.person_search_outlined, title: 'No doctors found', hint: 'Try clearing filters or using a different search.', variant: EmptyStateVariant.compact))
                else ...[
                  for (final doctor in state.doctors) ...[DoctorResultCard(doctor: doctor), const SizedBox(height: AppTheme.spaceSm)],
                  if (state.canLoadMoreDoctors) PrimaryButton(label: 'Load more', isLoading: state.isLoadingMoreDoctors, onPressed: () => ref.read(discoveryControllerProvider.notifier).loadMoreDoctors()),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
  void _onSearch(String value) { setState(() {}); _debounce?.cancel(); _debounce = Timer(const Duration(milliseconds: 400), () { final query = value.trim(); if (query.length == 1) return; final filters = ref.read(discoveryControllerProvider).doctorFilters.copyWith(search: query.isEmpty ? null : query, clearSearch: query.isEmpty, page: 1); ref.read(discoveryControllerProvider.notifier).loadDoctors(filters: filters); }); }
  void _clear() { _search.clear(); _onSearch(''); }
  Future<void> _filters(DiscoveryState state) async { final doctors = state.doctors; await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => DoctorFilterSheet(initialFilters: state.doctorFilters, specialties: _derive(doctors, (d) => d.specialtyNameEn ?? d.specialtyEn ?? d.specialtyNameAr ?? d.specialtyAr), regions: doctors.expand((d) => d.clinics.map((c) => c.region)).whereType<String>().toSet().toList(), onApply: (filters) => ref.read(discoveryControllerProvider.notifier).loadDoctors(filters: filters), onClear: () => ref.read(discoveryControllerProvider.notifier).loadDoctors(filters: const DoctorFilters()))); }
}
class _Summary extends StatelessWidget { const _Summary({required this.filters, required this.count, required this.onFilters}); final DoctorFilters filters; final int count; final VoidCallback onFilters; @override Widget build(BuildContext context) { final active = [if (filters.specialty != null) 'Specialty: ${filters.specialty}', if (filters.region != null) 'Region: ${filters.region}', if (filters.minRating != null) 'Rating ${filters.minRating}+', if (filters.minFee != null || filters.maxFee != null) 'Fee filter active', if (filters.search != null) 'Search active']; return SectionHeader(title: '$count doctor result${count == 1 ? '' : 's'}', subtitle: active.isEmpty ? 'No active filters' : active.join(' · '), trailing: OutlinedButton.icon(onPressed: onFilters, icon: const Icon(Icons.filter_list_rounded), label: const Text('Filters'))); } }
class _Loading extends StatelessWidget { const _Loading(); @override Widget build(BuildContext context) => const Card(child: Padding(padding: EdgeInsets.all(AppTheme.spaceLg), child: Row(children: [SizedBox.square(dimension: AppTheme.iconLg, child: CircularProgressIndicator(strokeWidth: 2)), SizedBox(width: AppTheme.spaceMd), Expanded(child: Text('Loading doctors...'))]))); }
List<String> _derive(List<Doctor> doctors, String? Function(Doctor) getter) => doctors.map(getter).whereType<String>().where((value) => value.trim().isNotEmpty).toSet().toList()..sort();

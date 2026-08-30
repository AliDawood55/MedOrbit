import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/localization/app_strings.dart';
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

class DoctorDirectoryScreen extends ConsumerStatefulWidget {
  const DoctorDirectoryScreen({super.key, this.initialSearch, this.initialSpecialty});

  /// Deep-link seeds from `/doctors?search=&specialty=` (see [AppRouter]).
  /// [initialSpecialty] is the raw backend wire value (English specialty
  /// name). Both are applied exactly once, on first load.
  final String? initialSearch;
  final String? initialSpecialty;

  @override
  ConsumerState<DoctorDirectoryScreen> createState() => _DoctorDirectoryScreenState();
}
class _DoctorDirectoryScreenState extends ConsumerState<DoctorDirectoryScreen> { final _search = TextEditingController(); Timer? _debounce;
  /// Personalized recommendations are held in the shared [DiscoveryState] and
  /// may belong to a previous viewer. The strip stays hidden until
  /// [_bootstrap] has dropped any retained list and (re)loaded for the
  /// current viewer, so stale personalization can never paint.
  bool _recommendationsInitialized = false;
  @override void initState() {
    super.initState();
    final seedSearch = widget.initialSearch?.trim();
    final seedSpecialty = widget.initialSpecialty?.trim();
    if (seedSearch != null && seedSearch.isNotEmpty) _search.text = seedSearch;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap(
          seedSearch != null && seedSearch.isNotEmpty ? seedSearch : null,
          seedSpecialty != null && seedSpecialty.isNotEmpty ? seedSpecialty : null,
        ));
  }
  Future<void> _bootstrap(String? seedSearch, String? seedSpecialty) async {
    final notifier = ref.read(discoveryControllerProvider.notifier);
    // Drop any recommendations retained from a previous session/user before
    // this screen can present them as the current viewer's data.
    notifier.clearRecommendedDoctors();
    if (seedSearch != null || seedSpecialty != null) {
      notifier.loadDoctors(
        filters: ref.read(discoveryControllerProvider).doctorFilters.copyWith(
              search: seedSearch, clearSearch: seedSearch == null,
              specialty: seedSpecialty, clearSpecialty: seedSpecialty == null,
              page: 1,
            ),
      );
    } else {
      notifier.loadDoctors();
    }
    final authed = ref.read(discoveryViewerAuthenticatedProvider);
    if (authed) notifier.loadRecommendedDoctors();
    if (mounted) setState(() => _recommendationsInitialized = true);
    await notifier.loadSpecialties();
    if (mounted && authed && seedSpecialty != null) _recordSpecialty(seedSpecialty);
  }
  @override void dispose() { _debounce?.cancel(); _search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final state = ref.watch(discoveryControllerProvider);
    // React to auth changes while the screen stays mounted: sign-out wipes
    // the personalized strip immediately; sign-in (re)loads it. The
    // [_recommendationsInitialized] guard keeps this from firing a second
    // initial request alongside [_bootstrap].
    ref.listen<bool>(discoveryViewerAuthenticatedProvider, (previous, authenticated) {
      if (!mounted) return;
      final notifier = ref.read(discoveryControllerProvider.notifier);
      if (!authenticated) {
        notifier.clearRecommendedDoctors();
      } else if (_recommendationsInitialized) {
        notifier.loadRecommendedDoctors();
      }
    });
    return AppScaffold(
      appBar: AppBar(title: Text(strings.doctorDirectoryScreenTitle)),
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
                PageIntro(title: strings.doctorDirectoryTitle, subtitle: strings.doctorDirectorySubtitle, icon: Icons.person_search_outlined),
                if (_recommendationsInitialized && ref.watch(discoveryViewerAuthenticatedProvider) && (state.isLoadingRecommendedDoctors || state.recommendedDoctorsError != null || state.recommendedDoctors.isNotEmpty)) ...[
                  const SizedBox(height: AppTheme.spaceLg),
                  _RecommendedStrip(strings: strings, state: state, onRetry: () => ref.read(discoveryControllerProvider.notifier).loadRecommendedDoctors()),
                ],
                const SizedBox(height: AppTheme.spaceLg),
                Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: AppTextField(label: strings.searchDoctorsLabel, hintText: strings.searchDoctorsFieldHint, controller: _search, prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _search.text.isEmpty ? null : IconButton(onPressed: _clear, icon: const Icon(Icons.close_rounded), tooltip: strings.clearSearch), onChanged: _onSearch))),
                const SizedBox(height: AppTheme.spaceLg),
                _SpecialtyQuickFilter(strings: strings, specialties: state.specialties.isEmpty ? kDoctorSpecialtyFallback : state.specialties, selected: state.doctorFilters.specialty, onSelected: _onSpecialty),
                const SizedBox(height: AppTheme.spaceLg),
                _Summary(strings: strings, filters: state.doctorFilters, count: state.doctors.length, onFilters: () => _filters(state)),
                const SizedBox(height: AppTheme.spaceLg),
                if (state.isLoadingDoctors) _Loading(strings: strings)
                else if (state.doctorListError != null) Card(child: ErrorRetryState(title: strings.couldNotLoadDoctors, message: state.doctorListError!.message, retryLabel: strings.retry, onRetry: () => ref.read(discoveryControllerProvider.notifier).loadDoctors(), variant: ErrorRetryVariant.compact))
                else if (state.doctors.isEmpty) Card(child: EmptyState(icon: Icons.person_search_outlined, title: strings.doctorEmptyTitle, hint: strings.doctorEmptyHint, variant: EmptyStateVariant.compact))
                else ...[
                  for (final doctor in state.doctors) ...[DoctorResultCard(doctor: doctor), const SizedBox(height: AppTheme.spaceSm)],
                  if (state.canLoadMoreDoctors) PrimaryButton(label: strings.discoveryLoadMoreButton, isLoading: state.isLoadingMoreDoctors, onPressed: () => ref.read(discoveryControllerProvider.notifier).loadMoreDoctors()),
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
  void _onSpecialty(String? value) {
    final filters = ref.read(discoveryControllerProvider).doctorFilters.copyWith(specialty: value, clearSpecialty: value == null, page: 1);
    ref.read(discoveryControllerProvider.notifier).loadDoctors(filters: filters);
    if (value != null && ref.read(discoveryViewerAuthenticatedProvider)) _recordSpecialty(value);
  }
  /// Fires the best-effort specialty-search telemetry ping, resolving the
  /// English name to its backend id via the loaded specialty list. Skips
  /// silently when the id is unknown (e.g. offline fallback list).
  void _recordSpecialty(String nameEn) {
    final match = ref.read(discoveryControllerProvider).specialties
        .where((s) => s.nameEn == nameEn && (s.id?.isNotEmpty ?? false));
    if (match.isEmpty) return;
    ref.read(discoveryControllerProvider.notifier).recordSpecialtySearch(match.first.id!);
  }
  Future<void> _filters(DiscoveryState state) async { final doctors = state.doctors; await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => DoctorFilterSheet(initialFilters: state.doctorFilters, regions: doctors.expand((d) => d.clinics.map((c) => c.region)).whereType<String>().toSet().toList(), onApply: (filters) => ref.read(discoveryControllerProvider.notifier).loadDoctors(filters: filters), onClear: () => ref.read(discoveryControllerProvider.notifier).loadDoctors(filters: state.doctorFilters.copyWith(clearRegion: true, clearMinRating: true, clearMinFee: true, clearMaxFee: true, page: 1)))); }
}
class _SpecialtyQuickFilter extends StatelessWidget {
  const _SpecialtyQuickFilter({required this.strings, required this.specialties, required this.selected, required this.onSelected});
  final AppStrings strings; final List<Specialty> specialties; final String? selected; final ValueChanged<String?> onSelected;
  @override
  Widget build(BuildContext context) {
    return Semantics(container: true, label: strings.doctorFilterSpecialtyLabel, child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceLg), child: Row(children: [
      Padding(padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceXs), child: ChoiceChip(key: const ValueKey('doctor-specialty-quick-all'), label: Text(strings.doctorSpecialtyFilterAll), selected: selected == null, onSelected: (_) => onSelected(null))),
      for (final specialty in specialties) Padding(padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceXs), child: ChoiceChip(key: ValueKey('doctor-specialty-quick-${specialty.nameEn}'), label: Text(specialty.label(strings.isArabic)), selected: selected == specialty.nameEn, onSelected: (_) => onSelected(selected == specialty.nameEn ? null : specialty.nameEn))),
    ])));
  }
}
/// Authenticated "Recommended doctors" strip — the mobile equivalent of the
/// web page's `recommendedDoctorsSection`. Visually secondary (a compact
/// horizontal carousel above the directory), fully isolated: its loading
/// and error states never touch the main list.
class _RecommendedStrip extends StatelessWidget {
  const _RecommendedStrip({required this.strings, required this.state, required this.onRetry});
  final AppStrings strings;
  final DiscoveryState state;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (state.isLoadingRecommendedDoctors && state.recommendedDoctors.isEmpty) {
      content = const Card(child: Padding(padding: EdgeInsets.all(AppTheme.spaceLg), child: Center(child: SizedBox.square(dimension: AppTheme.iconLg, child: CircularProgressIndicator(strokeWidth: 2)))));
    } else if (state.recommendedDoctorsError != null && state.recommendedDoctors.isEmpty) {
      content = Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Row(children: [
        Expanded(child: Text(strings.doctorRecommendedUnavailable)),
        const SizedBox(width: AppTheme.spaceSm),
        TextButton(key: const ValueKey('doctor-recommended-retry'), onPressed: onRetry, child: Text(strings.retry)),
      ])));
    } else {
      content = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceLg),
        child: IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final doctor in state.recommendedDoctors)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppTheme.spaceSm),
              child: SizedBox(width: 288, child: DoctorResultCard(key: ValueKey('doctor-recommended-${doctor.id}'), doctor: doctor, reasonLabel: doctorRecommendationReason(doctor, strings))),
            ),
        ])),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title: strings.doctorRecommendedTitle, subtitle: strings.doctorRecommendedSubtitle),
      content,
    ]);
  }
}
class _Summary extends StatelessWidget { const _Summary({required this.strings, required this.filters, required this.count, required this.onFilters}); final AppStrings strings; final DoctorFilters filters; final int count; final VoidCallback onFilters; @override Widget build(BuildContext context) { final active = [if (filters.specialty != null) strings.discoveryFilterSummarySpecialty(filters.specialty!), if (filters.region != null) strings.discoveryFilterSummaryRegion(filters.region!), if (filters.minRating != null) strings.discoveryFilterSummaryMinRating(filters.minRating.toString()), if (filters.minFee != null || filters.maxFee != null) strings.discoveryFilterSummaryFeeActive, if (filters.search != null) strings.discoverySearchActiveLabel]; return SectionHeader(title: strings.doctorResultsCount(count), subtitle: active.isEmpty ? strings.discoveryNoActiveFilters : active.join(' · '), trailing: OutlinedButton.icon(onPressed: onFilters, icon: const Icon(Icons.filter_list_rounded), label: Text(strings.discoveryFiltersButton))); } }
class _Loading extends StatelessWidget { const _Loading({required this.strings}); final AppStrings strings; @override Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(AppTheme.spaceLg), child: Row(children: [const SizedBox.square(dimension: AppTheme.iconLg, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: AppTheme.spaceMd), Expanded(child: Text(strings.doctorLoadingDoctors))]))); }

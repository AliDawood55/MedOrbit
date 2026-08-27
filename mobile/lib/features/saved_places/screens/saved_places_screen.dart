import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/page_sections.dart';
import '../models/saved_place.dart';
import '../providers/saved_places_provider.dart';

class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    final places = ref.watch(savedPlacesProvider);
    return AppScaffold(
      appBar: AppBar(title: Text(strings.savedPlacesTitle)),
      body: places.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ErrorRetryState(
          title: strings.savedPlacesLoadErrorTitle,
          message: strings.savedPlacesLoadErrorHint,
          retryLabel: strings.retry,
          onRetry: () => ref.invalidate(savedPlacesProvider),
        ),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(savedPlacesProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceLg),
            children: [
              ResponsiveContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PageIntro(
                      title: strings.savedPlacesTitle,
                      subtitle: strings.savedPlacesSubtitle,
                      icon: Icons.bookmark_outline_rounded,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(height: AppTheme.spaceLg),
                    if (items.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppTheme.spaceXl),
                          child: EmptyState(
                            icon: Icons.bookmark_border_rounded,
                            title: strings.savedPlacesEmptyTitle,
                            hint: strings.savedPlacesEmptyHint,
                          ),
                        ),
                      )
                    else
                      for (final place in items) ...[
                        _PlaceCard(place: place, strings: strings),
                        const SizedBox(height: AppTheme.spaceMd),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.place, required this.strings});
  final SavedPlace place;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.all(AppTheme.spaceLg),
      leading: const CircleAvatar(child: Icon(Icons.place_outlined)),
      title: Text(place.placeName ?? strings.savedPlaceFallbackName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (place.placeType != null) Text(place.placeType!),
          if (place.address != null) Text(place.address!),
          if (place.distanceKm != null)
            Text(strings.savedPlaceDistance(place.distanceKm!)),
        ],
      ),
    ),
  );
}

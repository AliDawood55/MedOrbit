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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = place.placeName ?? strings.savedPlaceFallbackName;
    final type = place.placeType;
    final address = place.address;
    final phone = place.phone;
    final rating = place.rating;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(child: Icon(Icons.place_outlined)),
                const SizedBox(width: AppTheme.spaceMd),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: AppTheme.weightBold,
                    ),
                  ),
                ),
              ],
            ),
            if (type != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              Text(type, style: theme.textTheme.labelMedium),
            ],
            if (address != null) ...[
              const SizedBox(height: AppTheme.spaceXs),
              _PlaceDetail(icon: Icons.location_on_outlined, text: address),
            ],
            if (phone != null) ...[
              const SizedBox(height: AppTheme.spaceXs),
              Directionality(
                textDirection: TextDirection.ltr,
                child: _PlaceDetail(icon: Icons.phone_outlined, text: phone),
              ),
            ],
            if (rating != null || place.distanceKm != null) ...[
              const SizedBox(height: AppTheme.spaceSm),
              Wrap(
                spacing: AppTheme.spaceMd,
                runSpacing: AppTheme.spaceXs,
                children: [
                  if (rating != null)
                    _PlaceDetail(
                      icon: Icons.star_rounded,
                      text: rating.toStringAsFixed(1),
                    ),
                  if (place.distanceKm != null)
                    _PlaceDetail(
                      icon: Icons.near_me_outlined,
                      text: strings.savedPlaceDistance(place.distanceKm!),
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

class _PlaceDetail extends StatelessWidget {
  const _PlaceDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: AppTheme.iconSm,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: AppTheme.spaceXs),
      Flexible(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
    ],
  );
}

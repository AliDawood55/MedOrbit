import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/saved_places_api.dart';
import '../models/saved_place.dart';

final savedPlacesApiProvider = Provider<SavedPlacesApi>(
  (ref) => SavedPlacesApi(ref.watch(dioProvider)),
);
final savedPlacesProvider = FutureProvider.autoDispose<List<SavedPlace>>(
  (ref) => ref.watch(savedPlacesApiProvider).list(),
);

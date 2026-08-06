import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../data/user_api.dart';
import '../models/user_profile_model.dart';

final userApiProvider = Provider<UserApi>((ref) => UserApi(ref.watch(dioProvider)));

final currentUserProfileProvider = FutureProvider.autoDispose<UserProfileModel>((ref) {
  return ref.watch(userApiProvider).getMe();
});

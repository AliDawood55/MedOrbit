import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../auth/providers/app_role_capabilities_provider.dart';
import '../data/user_api.dart';
import '../models/user_profile_model.dart';

final userApiProvider = Provider<UserApi>(
  (ref) => UserApi(ref.watch(dioProvider)),
);

final currentUserProfileProvider = FutureProvider.autoDispose<UserProfileModel>(
  (ref) {
    ref.watch(appAccountSessionKeyProvider);
    return ref.watch(userApiProvider).getMe();
  },
);

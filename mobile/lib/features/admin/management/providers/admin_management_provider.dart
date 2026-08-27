import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/core_providers.dart';
import '../data/admin_management_api.dart';
import '../models/admin_management_models.dart';

final adminManagementApiProvider = Provider<AdminManagementApi>(
  (ref) => AdminManagementApi(ref.watch(dioProvider)),
);
final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>(
  (ref) => ref.watch(adminManagementApiProvider).users(),
);
final adminUsersByRoleProvider = FutureProvider.autoDispose
    .family<List<AdminUser>, String>(
      (ref, role) => ref.watch(adminManagementApiProvider).users(role: role),
    );
final adminActivityProvider = FutureProvider.autoDispose
    .family<List<AdminActivityItem>, String>(
      (ref, kind) => ref.watch(adminManagementApiProvider).activity(kind),
    );
final adminInvitationsProvider =
    FutureProvider.autoDispose<List<AdminInvitation>>(
      (ref) => ref.watch(adminManagementApiProvider).invitations(),
    );
final doctorApplicationsProvider = FutureProvider.autoDispose
    .family<List<DoctorApplication>, bool>(
      (ref, isArabic) => ref
          .watch(adminManagementApiProvider)
          .applications(isArabic: isArabic),
    );

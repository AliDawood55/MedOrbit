import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

enum AppUserRole { patient, doctor, admin, superAdmin, unknown }

/// Presentation capabilities derived from the canonical authenticated user.
///
/// This registry controls only what the mobile UI advertises and how it
/// routes. It is never persisted and does not replace backend authorization.
class AppRoleCapabilities {
  const AppRoleCapabilities._({
    required this.isAuthenticated,
    required this.role,
  });

  factory AppRoleCapabilities.fromRole(
    String? rawRole, {
    bool isAuthenticated = true,
  }) {
    final role = switch (rawRole?.trim().toLowerCase()) {
      'patient' => AppUserRole.patient,
      'doctor' => AppUserRole.doctor,
      'admin' => AppUserRole.admin,
      'super_admin' => AppUserRole.superAdmin,
      _ => AppUserRole.unknown,
    };
    return AppRoleCapabilities._(isAuthenticated: isAuthenticated, role: role);
  }

  final bool isAuthenticated;
  final AppUserRole role;

  bool get isPatient => role == AppUserRole.patient;
  bool get isDoctor => role == AppUserRole.doctor;
  bool get isAdmin =>
      role == AppUserRole.admin || role == AppUserRole.superAdmin;
  bool get isSuperAdmin => role == AppUserRole.superAdmin;

  // Shared authenticated MedOrbit product surfaces.
  bool get canUseSharedHome => isAuthenticated;
  bool get canUseSocialFeed => isAuthenticated;
  bool get canUsePublicDiscovery => isAuthenticated;
  bool get canUseNotifications => isAuthenticated;
  bool get canUseAccountProfile => isAuthenticated;
  bool get canUseBilling => isAuthenticated;
  bool get canUseAiChat => isAuthenticated;

  // Web deliberately suppresses these consumer/care surfaces for operational
  // accounts even though several underlying endpoints authenticate broadly.
  bool get canUseCareMessages => isAuthenticated && (isPatient || isDoctor);
  bool get canUseConsumerAi => isAuthenticated && (isPatient || isDoctor);
  bool get canUseContactAndFeedback =>
      isAuthenticated && (isPatient || isDoctor);

  // Additive role overlays.
  bool get canUsePatientCare => isAuthenticated && isPatient;
  bool get canApplyAsDoctor => isAuthenticated && isPatient;
  bool get canAcceptAdminInvitation =>
      isAuthenticated && (isPatient || isDoctor);
  bool get canUseDoctorWorkspace => isAuthenticated && isDoctor;
  bool get canCreateDoctorPosts => isAuthenticated && isDoctor;
  bool get canUseAdminTools => isAuthenticated && isAdmin;
  bool get canUseSuperAdminTools => isAuthenticated && isSuperAdmin;
}

final appRoleCapabilitiesProvider = Provider<AppRoleCapabilities>((ref) {
  final auth = ref.watch(authControllerProvider);
  return AppRoleCapabilities.fromRole(
    auth.user?.role,
    isAuthenticated: auth.status == AuthStatus.authenticated,
  );
});

/// Canonical identity boundary for account-owned presentation state.
///
/// Providers that can survive inside the indexed navigation shell watch this
/// value so an in-process logout/login or role change reconstructs them before
/// another account's data can be rendered.
final appAccountSessionKeyProvider = Provider<String>((ref) {
  final auth = ref.watch(authControllerProvider);
  return '${auth.status.name}:${auth.user?.id ?? ''}:${auth.user?.role ?? ''}';
});

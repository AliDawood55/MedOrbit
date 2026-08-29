import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/providers/auth_provider.dart';

/// What the signed-in account may do in the administration area.
///
/// Derived from the canonical [authControllerProvider] state on every read —
/// never persisted or cached separately, so a cleared session (a failed token
/// refresh, a logout, an `authorization_version` bump on the backend) removes
/// administration access in the same frame it removes the session.
///
/// The backend remains the authority: `authorizeAdmin` accepts `admin` and
/// `super_admin`, `authorizeSuperAdmin` accepts only `super_admin`
/// (`backend/src/middleware/auth.js:61-62`). This enum keeps those two
/// distinct rather than collapsing them into one "is admin" boolean.
enum AdminAccess {
  /// The splash bootstrap has not finished reading the persisted session.
  /// Screens must render a neutral placeholder here — never admin data, and
  /// never a "not authorized" message about an account that may well be one.
  unknown,

  /// Signed out, or signed in as a patient/doctor.
  none,

  /// `admin`: every `authorizeAdmin` surface.
  admin,

  /// `super_admin`: everything an admin can do, plus the invitation registry.
  superAdmin;

  /// True for the `authorizeAdmin` surfaces (admin **or** super admin).
  bool get canUseAdminTools =>
      this == AdminAccess.admin || this == AdminAccess.superAdmin;

  /// True only for the `authorizeSuperAdmin` surfaces.
  bool get canUseSuperAdminTools => this == AdminAccess.superAdmin;

  /// True once the session is resolved and it is not an administrator.
  bool get isDeniedDefinitively => this == AdminAccess.none;
}

AdminAccess adminAccessFor({required AuthStatus status, required String? role}) {
  if (status == AuthStatus.unknown) return AdminAccess.unknown;
  if (status == AuthStatus.unauthenticated) return AdminAccess.none;
  return switch (role?.trim().toLowerCase()) {
    'super_admin' => AdminAccess.superAdmin,
    'admin' => AdminAccess.admin,
    _ => AdminAccess.none,
  };
}

final adminAccessProvider = Provider<AdminAccess>((ref) {
  final auth = ref.watch(authControllerProvider);
  return adminAccessFor(status: auth.status, role: auth.user?.role);
});

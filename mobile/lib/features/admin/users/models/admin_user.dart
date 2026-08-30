import '../../common/models/admin_parsing.dart';
import '../../common/providers/admin_access_provider.dart';

/// The four roles the backend's `users.role` column allows. `unknown` keeps a
/// role the app does not recognize renderable (as its raw value) instead of
/// mislabelling it as a patient.
enum AdminUserRole { patient, doctor, admin, superAdmin, unknown }

AdminUserRole adminUserRoleFromWire(String value) => switch (value) {
  'patient' => AdminUserRole.patient,
  'doctor' => AdminUserRole.doctor,
  'admin' => AdminUserRole.admin,
  'super_admin' => AdminUserRole.superAdmin,
  _ => AdminUserRole.unknown,
};

/// The `role` query value each filter sends, or `null` for "all roles".
/// Mirrors `admin-users.html`'s `<select id="userRoleFilter">` options.
String? adminUserRoleWireValue(AdminUserRole? role) => switch (role) {
  AdminUserRole.patient => 'patient',
  AdminUserRole.doctor => 'doctor',
  AdminUserRole.admin => 'admin',
  AdminUserRole.superAdmin => 'super_admin',
  _ => null,
};

/// One row of `GET /api/admin/users`
/// (`backend/src/routes/admin.routes.js:25-58`).
///
/// The query joins `user_profiles` for **English** names only, plus phone and
/// city — there are no Arabic name columns in this projection, so the display
/// name falls back to the email exactly as the web page does.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.role,
    required this.roleValue,
    required this.isActive,
    required this.emailVerified,
    this.firstNameEn,
    this.lastNameEn,
    this.phone,
    this.city,
  });

  final String id;
  final String email;
  final AdminUserRole role;

  /// The unmodified server value, so an unrecognized role is still shown.
  final String roleValue;
  final bool isActive;
  final bool emailVerified;
  final String? firstNameEn;
  final String? lastNameEn;
  final String? phone;
  final String? city;

  String get displayName {
    final full = adminJoinName(firstNameEn, lastNameEn);
    return full.isEmpty ? email : full;
  }

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    final roleValue = adminRequireString(json, 'role');
    return AdminUser(
      id: adminRequireString(json, 'id'),
      email: adminRequireString(json, 'email'),
      role: adminUserRoleFromWire(roleValue),
      roleValue: roleValue,
      isActive: adminBool(json['is_active']),
      emailVerified: adminBool(json['email_verified']),
      firstNameEn: adminOptionalString(json, 'first_name_en'),
      lastNameEn: adminOptionalString(json, 'last_name_en'),
      phone: adminOptionalString(json, 'phone'),
      city: adminOptionalString(json, 'city'),
    );
  }

  AdminUser copyWith({bool? isActive, bool? emailVerified}) => AdminUser(
    id: id,
    email: email,
    role: role,
    roleValue: roleValue,
    isActive: isActive ?? this.isActive,
    emailVerified: emailVerified ?? this.emailVerified,
    firstNameEn: firstNameEn,
    lastNameEn: lastNameEn,
    phone: phone,
    city: city,
  );
}

/// What the activation endpoints return.
///
/// `PUT /admin/users/:id/(de|re)activate` answers with `SAFE_USER_COLUMNS`
/// only — id, email, role, flags and timestamps, **no profile names**. Merging
/// this into the listed row (rather than replacing it) is what keeps the card's
/// name and city from blanking out after a successful action; the web page
/// spreads the same partial object over its cached row.
class AdminUserStateUpdate {
  const AdminUserStateUpdate({
    required this.id,
    required this.isActive,
    required this.emailVerified,
  });

  final String id;
  final bool isActive;
  final bool emailVerified;

  factory AdminUserStateUpdate.fromJson(Map<String, dynamic> json) =>
      AdminUserStateUpdate(
        id: adminRequireString(json, 'id'),
        isActive: adminBool(json['is_active']),
        emailVerified: adminBool(json['email_verified']),
      );
}

/// The activation action a card may offer, or why it may not offer one.
enum AdminUserAction {
  deactivate,
  reactivate,

  /// The administrator's own account — the backend refuses
  /// (`req.user.sub === target.id`).
  blockedSelfAccount,

  /// A `super_admin` target, or an `admin` target being viewed by a plain
  /// `admin`. Both are refused by `mutationBlocked`.
  blockedProtectedAccount,
}

/// Client-side mirror of `mutationBlocked`
/// (`backend/src/routes/admin.routes.js:13-18`).
///
/// Presentation only: the backend re-checks every rule and answers `403
/// FORBIDDEN` regardless of what the app renders. Its purpose is to avoid
/// offering a button that is guaranteed to fail, and to say *why* — the same
/// three cases the web page distinguishes.
AdminUserAction adminUserAction({
  required AdminUser user,
  required String? actorId,
  required AdminAccess access,
}) {
  if (actorId != null && user.id == actorId) {
    return AdminUserAction.blockedSelfAccount;
  }
  if (user.role == AdminUserRole.superAdmin) {
    return AdminUserAction.blockedProtectedAccount;
  }
  if (user.role == AdminUserRole.admin && !access.canUseSuperAdminTools) {
    return AdminUserAction.blockedProtectedAccount;
  }
  return user.isActive
      ? AdminUserAction.deactivate
      : AdminUserAction.reactivate;
}

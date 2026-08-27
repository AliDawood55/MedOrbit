import '../../../shared/utils/json_parsing.dart';

/// Mirrors the `user` object returned by `/auth/login` and `/auth/register`.
/// Backend `id` is a Postgres UUID, so it's always a string here.
class UserModel {
  const UserModel({required this.id, required this.email, required this.role, this.name});

  final String id;
  final String email;
  final String role;
  final String? name;

  /// Throws a [FormatException] if [json] doesn't carry a usable `id`,
  /// `email`, and `role` — silently inventing an identity for a malformed
  /// payload would be worse than failing loudly. Callers persist and act on
  /// this model, so it must never represent data that never actually
  /// arrived. `id`/`email`/`role` are `UUID`/`VARCHAR NOT NULL` columns
  /// (`db/01_base_tables.sql`'s `users` table) — never numeric or boolean
  /// in a well-formed response, so no scalar coercion is applied here.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: requireExactString(json, 'id'),
      email: requireExactString(json, 'email'),
      role: requireExactString(json, 'role'),
      name: optionalExactString(json, 'name'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'role': role, 'name': name};
}

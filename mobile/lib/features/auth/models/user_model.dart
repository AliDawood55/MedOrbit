/// Mirrors the `user` object returned by `/auth/login` and `/auth/register`.
/// Backend `id` is a Postgres UUID, so it's always a string here.
class UserModel {
  const UserModel({required this.id, required this.email, required this.role, this.name});

  final String id;
  final String email;
  final String role;
  final String? name;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'role': role, 'name': name};
}

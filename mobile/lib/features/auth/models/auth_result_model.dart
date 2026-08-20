import 'user_model.dart';

/// Mirrors the `data` payload of a successful `/auth/login` response.
class AuthResultModel {
  const AuthResultModel({required this.user, required this.accessToken, required this.refreshToken});

  final UserModel user;
  final String accessToken;
  final String refreshToken;

  factory AuthResultModel.fromJson(Map<String, dynamic> json) {
    return AuthResultModel(
      user: UserModel.fromJson(json['user'] as Map<String, dynamic>),
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }
}

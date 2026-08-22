import '../../../shared/utils/json_parsing.dart';
import 'user_model.dart';

/// Mirrors the `data` payload of a successful `/auth/login` response.
class AuthResultModel {
  const AuthResultModel({required this.user, required this.accessToken, required this.refreshToken});

  final UserModel user;
  final String accessToken;
  final String refreshToken;

  /// Throws a [FormatException] for a malformed `user` object or a missing
  /// token. Tokens are security-sensitive: [requireExactString] never
  /// coerces a number/object into a string, and there is no `''` fallback —
  /// a malformed auth result must fail before an unusable session is ever
  /// persisted.
  factory AuthResultModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    if (userJson is! Map<String, dynamic>) {
      throw const FormatException('Missing or invalid required field "user"');
    }
    return AuthResultModel(
      user: UserModel.fromJson(userJson),
      accessToken: requireExactString(json, 'accessToken'),
      refreshToken: requireExactString(json, 'refreshToken'),
    );
  }
}

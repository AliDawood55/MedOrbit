import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/config/app_config.dart';

/// Thin wrapper around the `google_sign_in` 7.x Credential Manager API.
///
/// [GoogleSignIn.initialize] must be called exactly once before any other
/// method — this caches the future so repeated sign-in attempts don't
/// re-initialize.
class GoogleAuthService {
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    return _initFuture ??= GoogleSignIn.instance.initialize(
      serverClientId: AppConfig.googleServerClientId,
    );
  }

  /// Returns the Google ID token to send to `/auth/google`, or null if the
  /// user cancelled the sign-in flow.
  Future<String?> signInAndGetIdToken() async {
    await _ensureInitialized();
    try {
      final account = await GoogleSignIn.instance.authenticate();
      return account.authentication.idToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }
}

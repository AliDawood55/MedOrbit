import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../data/auth_api.dart';
import '../data/google_auth_service.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

final googleAuthServiceProvider = Provider<GoogleAuthService>(
  (ref) => GoogleAuthService(),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(dioProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(authApiProvider),
    ref.watch(secureStorageProvider),
  ),
);

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isSubmitting = false,
    this.errorMessage,
    this.errorCode,
  });

  final AuthStatus status;
  final UserModel? user;
  final bool isSubmitting;
  final String? errorMessage;
  final String? errorCode;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    bool? isSubmitting,
    String? errorMessage,
    String? errorCode,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._repository, this._googleAuthService, this._storage)
    : super(const AuthState()) {
    _sessionClearedSub = _storage.onSessionCleared.listen((_) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    });
  }

  final AuthRepository _repository;
  final GoogleAuthService _googleAuthService;
  final SecureStorageService _storage;
  late final StreamSubscription<void> _sessionClearedSub;

  /// Called once from the splash screen to decide the initial route.
  Future<void> checkAuthStatus() async {
    final hasSession = await _repository.hasValidSession();
    if (!hasSession) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    final user = await _repository.getPersistedUser();
    if (user == null) {
      // Token present but the cached user snapshot is missing/corrupt: an
      // "authenticated" state with no identity isn't a safe state to route
      // into, so drop the session and send the user back through login.
      await _storage.clear();
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    state = state.copyWith(status: AuthStatus.authenticated, user: user);
  }

  Future<bool> login({required String email, required String password}) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final result = await _repository.login(email: email, password: password);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isSubmitting: false,
      );
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
        errorCode: e.code,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Unexpected error occurred. Please try again.',
        errorCode: ApiException.codeUnknown,
      );
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    required String firstNameAr,
    required String lastNameAr,
    required String firstNameEn,
    required String lastNameEn,
    String? phone,
    String? gender,
  }) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.register(
        email: email,
        password: password,
        firstNameAr: firstNameAr,
        lastNameAr: lastNameAr,
        firstNameEn: firstNameEn,
        lastNameEn: lastNameEn,
        phone: phone,
        gender: gender,
      );
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
        errorCode: e.code,
      );
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.forgotPassword(email);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
        errorCode: e.code,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Unexpected error occurred. Please try again.',
        errorCode: ApiException.codeUnknown,
      );
      return false;
    }
  }

  Future<bool> verifyEmail({required String token, String? email}) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.verifyEmail(token: token, email: email);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
        errorCode: e.code,
      );
      return false;
    }
  }

  Future<bool> resendVerification(String email) async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.resendVerification(email);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
        errorCode: e.code,
      );
      return false;
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  Future<bool> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      await _repository.resetPassword(token: token, newPassword: newPassword);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(isSubmitting: false, errorMessage: e.message);
      return false;
    }
  }

  /// Returns true on success, false if the user cancelled the Google
  /// account picker (no error shown) or if sign-in/login failed (error
  /// message set on state).
  Future<bool> loginWithGoogle() async {
    if (state.isSubmitting) return false;
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final idToken = await _googleAuthService.signInAndGetIdToken();
      if (idToken == null) {
        state = state.copyWith(isSubmitting: false);
        return false;
      }
      final result = await _repository.loginWithGoogle(idToken);
      state = state.copyWith(
        status: AuthStatus.authenticated,
        user: result.user,
        isSubmitting: false,
      );
      return true;
    } on GoogleSignInException catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Google sign-in failed. Please try again.',
        errorCode: 'GOOGLE_SIGN_IN_FAILED',
      );
      return false;
    } on ApiException catch (e) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: e.message,
        errorCode: e.code,
      );
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        errorMessage: 'Google sign-in failed. Please try again.',
        errorCode: 'GOOGLE_SIGN_IN_FAILED',
      );
      return false;
    }
  }

  Future<void> logout() async {
    await _repository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  @override
  void dispose() {
    _sessionClearedSub.cancel();
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(
    ref.watch(authRepositoryProvider),
    ref.watch(googleAuthServiceProvider),
    ref.watch(secureStorageProvider),
  ),
);

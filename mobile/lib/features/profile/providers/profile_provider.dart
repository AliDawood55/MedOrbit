import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/models/user_profile_model.dart';
import '../../home/providers/user_provider.dart';
import '../data/profile_api.dart';
import '../models/profile_edit_model.dart';

final profileApiProvider = Provider<ProfileApi>(
  (ref) => ProfileApi(ref.watch(dioProvider)),
);

const int maxAvatarBytes = 2 * 1024 * 1024;
const List<String> allowedAvatarExtensions = ['jpg', 'jpeg', 'png'];

enum ProfileErrorKind { timeout, serviceUnavailable, generic }

enum PasswordChangeErrorKind {
  wrongCurrentPassword,
  weakPassword,
  timeout,
  serviceUnavailable,
  generic,
}

enum AvatarErrorKind {
  invalidType,
  tooLarge,
  timeout,
  serviceUnavailable,
  generic,
}

class ProfileState {
  const ProfileState({
    this.profile = const AsyncValue.loading(),
    this.isSaving = false,
    this.saveError,
    this.isSyncingLanguage = false,
    this.languageSyncFailed = false,
    this.isChangingPassword = false,
    this.passwordError,
    this.passwordChanged = false,
    this.isUploadingAvatar = false,
    this.avatarError,
  });

  final AsyncValue<UserProfileModel> profile;

  final bool isSaving;
  final ProfileErrorKind? saveError;

  final bool isSyncingLanguage;

  /// The locale has already switched locally regardless — this only flags
  /// that the account-level sync didn't stick, so a retry affordance can be
  /// shown without ever reverting the language the user is looking at.
  final bool languageSyncFailed;

  final bool isChangingPassword;
  final PasswordChangeErrorKind? passwordError;

  /// Set once a password change succeeds. The backend revokes every session
  /// at that point, so the screen is expected to navigate to login once this
  /// flips true.
  final bool passwordChanged;

  final bool isUploadingAvatar;
  final AvatarErrorKind? avatarError;

  ProfileState copyWith({
    AsyncValue<UserProfileModel>? profile,
    bool? isSaving,
    ProfileErrorKind? saveError,
    bool clearSaveError = false,
    bool? isSyncingLanguage,
    bool? languageSyncFailed,
    bool? isChangingPassword,
    PasswordChangeErrorKind? passwordError,
    bool clearPasswordError = false,
    bool? passwordChanged,
    bool? isUploadingAvatar,
    AvatarErrorKind? avatarError,
    bool clearAvatarError = false,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      isSaving: isSaving ?? this.isSaving,
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
      isSyncingLanguage: isSyncingLanguage ?? this.isSyncingLanguage,
      languageSyncFailed: languageSyncFailed ?? this.languageSyncFailed,
      isChangingPassword: isChangingPassword ?? this.isChangingPassword,
      passwordError: clearPasswordError
          ? null
          : (passwordError ?? this.passwordError),
      passwordChanged: passwordChanged ?? this.passwordChanged,
      isUploadingAvatar: isUploadingAvatar ?? this.isUploadingAvatar,
      avatarError: clearAvatarError ? null : (avatarError ?? this.avatarError),
    );
  }
}

class ProfileController extends StateNotifier<ProfileState> {
  ProfileController(this._ref)
    : _api = _ref.read(profileApiProvider),
      super(const ProfileState()) {
    load();
  }

  final Ref _ref;
  final ProfileApi _api;
  bool _disposed = false;

  Future<void> load() async {
    state = state.copyWith(profile: const AsyncValue.loading());
    final result = await AsyncValue.guard(() => _api.getMe());
    if (_disposed) return;
    state = state.copyWith(profile: result);
  }

  Future<void> retry() => load();

  /// `PUT /users/me` returns `data: null`, so a successful save re-fetches
  /// via `GET /users/me` to pick up the saved values, then invalidates
  /// [currentUserProfileProvider] so Home reflects the change too.
  Future<bool> save(ProfileEditModel draft) async {
    if (state.isSaving) return false;
    state = state.copyWith(isSaving: true, clearSaveError: true);
    try {
      await _api.updateMe(draft);
      final refreshed = await _api.getMe();
      if (_disposed) return true;
      state = state.copyWith(
        isSaving: false,
        profile: AsyncValue.data(refreshed),
      );
      _refreshHomeProfile();
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(isSaving: false, saveError: _categorize(error));
      return false;
    }
  }

  /// Switches the app locale immediately, independent of network reachability
  /// — the visible language never depends on the server call succeeding.
  /// Only the account-level sync (so the choice is remembered on another
  /// device) can fail, and that failure never rolls the local switch back,
  /// matching the web app's "non-critical, swallowed" behavior.
  Future<bool> setLanguage(String languageCode) async {
    if (languageCode != 'ar' && languageCode != 'en') return false;

    await _ref
        .read(localeControllerProvider.notifier)
        .setLocale(Locale(languageCode));
    if (_disposed) return true;

    state = state.copyWith(isSyncingLanguage: true, languageSyncFailed: false);
    try {
      await _api.updateLanguagePreference(languageCode);
      if (_disposed) return true;
      state = state.copyWith(isSyncingLanguage: false);
      return true;
    } catch (_) {
      if (_disposed) return false;
      state = state.copyWith(
        isSyncingLanguage: false,
        languageSyncFailed: true,
      );
      return false;
    }
  }

  /// On success, forces a full logout — the backend revokes every session's
  /// refresh token on a password change, so staying "logged in" locally would
  /// only work until the current access token naturally expires. The screen
  /// is expected to navigate to login once [ProfileState.passwordChanged]
  /// flips true.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (state.isChangingPassword) return false;
    state = state.copyWith(
      isChangingPassword: true,
      clearPasswordError: true,
      passwordChanged: false,
    );
    try {
      await _api.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (_disposed) return true;
      state = state.copyWith(isChangingPassword: false, passwordChanged: true);
      await _ref.read(authControllerProvider.notifier).logout();
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isChangingPassword: false,
        passwordError: _categorizePassword(error),
      );
      return false;
    }
  }

  /// Validates type/size locally first — the backend accepts any file type
  /// or size and only fails with a generic 500, so client-side validation is
  /// the only source of a clean error message here (matches the web app).
  Future<bool> uploadAvatar({
    required String filePath,
    required String fileName,
    required int fileSizeBytes,
  }) async {
    if (state.isUploadingAvatar) return false;

    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (!allowedAvatarExtensions.contains(extension)) {
      state = state.copyWith(avatarError: AvatarErrorKind.invalidType);
      return false;
    }
    if (fileSizeBytes > maxAvatarBytes) {
      state = state.copyWith(avatarError: AvatarErrorKind.tooLarge);
      return false;
    }

    state = state.copyWith(isUploadingAvatar: true, clearAvatarError: true);
    try {
      await _api.uploadAvatar(filePath: filePath, fileName: fileName);
      final refreshed = await _api.getMe();
      if (_disposed) return true;
      state = state.copyWith(
        isUploadingAvatar: false,
        profile: AsyncValue.data(refreshed),
      );
      _refreshHomeProfile();
      return true;
    } catch (error) {
      if (_disposed) return false;
      state = state.copyWith(
        isUploadingAvatar: false,
        avatarError: _categorizeAvatar(error),
      );
      return false;
    }
  }

  /// `currentUserProfileProvider` is `autoDispose`. Only invalidate it if
  /// it's already alive (the home screen is mounted somewhere beneath this
  /// one and currently watching it) — invalidating it when nothing watches
  /// it would construct a fresh instance just to have Riverpod dispose it
  /// again moments later, racing its own constructor-time fetch (the same
  /// class of bug fixed in the booking wizard's post-submit refresh). If
  /// it isn't alive, there's nothing to refresh: home always fetches fresh
  /// data the next time it's watched anyway.
  void _refreshHomeProfile() {
    if (_ref.exists(currentUserProfileProvider)) {
      _ref.invalidate(currentUserProfileProvider);
    }
  }

  ProfileErrorKind _categorize(Object error) {
    final api = ApiException.from(error);
    return switch (api) {
      _ when api.isTimeout => ProfileErrorKind.timeout,
      _ when api.code == ApiException.codeServiceUnavailable => ProfileErrorKind.serviceUnavailable,
      _ => ProfileErrorKind.generic,
    };
  }

  PasswordChangeErrorKind _categorizePassword(Object error) {
    final api = ApiException.from(error);
    return switch (api) {
      _ when api.code == 'INVALID_CREDENTIALS' => PasswordChangeErrorKind.wrongCurrentPassword,
      _ when api.code == 'VALIDATION_ERROR' => PasswordChangeErrorKind.weakPassword,
      _ when api.isTimeout => PasswordChangeErrorKind.timeout,
      _ when api.code == ApiException.codeServiceUnavailable => PasswordChangeErrorKind.serviceUnavailable,
      _ => PasswordChangeErrorKind.generic,
    };
  }

  AvatarErrorKind _categorizeAvatar(Object error) {
    final api = ApiException.from(error);
    return switch (api) {
      _ when api.isTimeout => AvatarErrorKind.timeout,
      _ when api.code == ApiException.codeServiceUnavailable => AvatarErrorKind.serviceUnavailable,
      _ => AvatarErrorKind.generic,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final profileControllerProvider =
    StateNotifierProvider.autoDispose<ProfileController, ProfileState>(
      (ref) => ProfileController(ref),
    );

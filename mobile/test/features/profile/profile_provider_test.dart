import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/locale/locale_controller.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/providers/auth_provider.dart';
import 'package:mobile/features/home/data/user_api.dart';
import 'package:mobile/features/home/models/user_profile_model.dart';
import 'package:mobile/features/home/providers/user_provider.dart';
import 'package:mobile/features/profile/data/profile_api.dart';
import 'package:mobile/features/profile/models/profile_edit_model.dart';
import 'package:mobile/features/profile/providers/profile_provider.dart';

UserProfileModel _profile({
  String id = 'user-1',
  String? firstNameEn = 'Sara',
  String? avatarUrl,
}) {
  return UserProfileModel(
    id: id,
    email: 'sara@example.com',
    role: 'patient',
    firstNameAr: 'سارة',
    lastNameAr: 'أحمد',
    firstNameEn: firstNameEn,
    lastNameEn: 'Ahmad',
    avatarUrl: avatarUrl,
    createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
  );
}

const _draft = ProfileEditModel(
  firstNameAr: 'سارة',
  lastNameAr: 'أحمد',
  firstNameEn: 'Sara',
  lastNameEn: 'Ahmad',
);

void main() {
  test('initial load succeeds and populates the profile', () async {
    final api = _FakeProfileApi()
      ..getMeResults.add(_profile(firstNameEn: 'Sara'));
    final container = _container(api);
    addTearDown(container.dispose);

    container.read(profileControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(profileControllerProvider);
    expect(state.profile.hasValue, isTrue);
    expect(state.profile.value?.firstNameEn, 'Sara');
  });

  test(
    'a load failure surfaces as an error state, and retry recovers',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(
          const ApiException(
            message: 'Network down',
            code: ApiException.codeServiceUnavailable,
          ),
        )
        ..getMeResults.add(_profile());
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(profileControllerProvider).profile.hasError,
        isTrue,
      );

      await container.read(profileControllerProvider.notifier).retry();

      expect(
        container.read(profileControllerProvider).profile.hasValue,
        isTrue,
      );
    },
  );

  test(
    'a successful save re-fetches the profile and clears any previous error',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile(firstNameEn: 'Sara'))
        ..updateMeResults.add(null)
        ..getMeResults.add(_profile(firstNameEn: 'Sarah'));
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .save(_draft);

      expect(ok, isTrue);
      final state = container.read(profileControllerProvider);
      expect(state.profile.value?.firstNameEn, 'Sarah');
      expect(state.saveError, isNull);
      expect(api.updateMeCalls.single, _draft);
    },
  );

  test(
    'a save failure keeps the previous profile value (safe rollback) and sets saveError',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile(firstNameEn: 'Sara'))
        ..updateMeResults.add(
          const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
        );
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .save(_draft);

      expect(ok, isFalse);
      final state = container.read(profileControllerProvider);
      expect(state.saveError, ProfileErrorKind.generic);
      expect(
        state.profile.value?.firstNameEn,
        'Sara',
        reason: 'an unsaved change must not corrupt the displayed profile',
      );
    },
  );

  test('a second save while one is in flight is ignored', () async {
    final completer = Completer<void>();
    final api = _FakeProfileApi()
      ..getMeResults.add(_profile())
      ..updateMeResults.add(completer.future)
      ..getMeResults.add(_profile());
    final container = _container(api);
    addTearDown(container.dispose);
    container.read(profileControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(profileControllerProvider.notifier);

    final first = notifier.save(_draft);
    final second = await notifier.save(_draft);

    expect(second, isFalse);
    completer.complete();
    await first;
    expect(api.updateMeCalls, hasLength(1));
  });

  test(
    'a successful save refreshes the home profile provider when it is being watched',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile(firstNameEn: 'Sara'))
        ..updateMeResults.add(null)
        ..getMeResults.add(_profile(firstNameEn: 'Sarah'));
      final userApi = _FakeUserApi()
        ..results.add(_profile(firstNameEn: 'Sara'));
      final container = _container(api, userApi: userApi);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      // Simulates the home screen already being mounted beneath this one and
      // watching `currentUserProfileProvider` — that live watch is what keeps
      // the autoDispose provider alive to be invalidated.
      final sub = container.listen(
        currentUserProfileProvider,
        (previous, next) {},
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      final callsBeforeSave = userApi.callCount;

      await container.read(profileControllerProvider.notifier).save(_draft);
      await Future<void>.delayed(Duration.zero);

      expect(userApi.callCount, greaterThan(callsBeforeSave));
    },
  );

  test(
    'setLanguage switches the locale immediately and syncs to the server on success',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..updateLanguageResults.add(null);
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .setLanguage('en');

      expect(ok, isTrue);
      expect(container.read(localeControllerProvider).languageCode, 'en');
      expect(
        container.read(profileControllerProvider).languageSyncFailed,
        isFalse,
      );
      expect(api.updateLanguageCalls, ['en']);
    },
  );

  test(
    'setLanguage keeps the local switch even when the server sync fails',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..updateLanguageResults.add(
          const ApiException(
            message: 'Network down',
            code: ApiException.codeServiceUnavailable,
          ),
        );
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .setLanguage('en');

      expect(ok, isFalse);
      expect(
        container.read(localeControllerProvider).languageCode,
        'en',
        reason:
            'the visible language must never roll back because of a network failure',
      );
      expect(
        container.read(profileControllerProvider).languageSyncFailed,
        isTrue,
      );
    },
  );

  test(
    'a successful password change logs the user out — the backend revokes every session',
    () async {
      final storage = _FakeSecureStorage();
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..changePasswordResults.add(null);
      final container = _container(api, storage: storage);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .changePassword(
            currentPassword: 'Old1!aaaa',
            newPassword: 'New1!aaaa',
          );

      expect(ok, isTrue);
      expect(container.read(profileControllerProvider).passwordChanged, isTrue);
      expect(storage.cleared, isTrue);
      expect(
        container.read(authControllerProvider).status,
        AuthStatus.unauthenticated,
      );
    },
  );

  test(
    'a wrong current password fails without logging out, and maps to wrongCurrentPassword',
    () async {
      final storage = _FakeSecureStorage();
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..changePasswordResults.add(
          const ApiException(
            message: 'Current password is incorrect',
            code: 'INVALID_CREDENTIALS',
          ),
        );
      final container = _container(api, storage: storage);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .changePassword(currentPassword: 'wrong', newPassword: 'New1!aaaa');

      expect(ok, isFalse);
      expect(
        container.read(profileControllerProvider).passwordError,
        PasswordChangeErrorKind.wrongCurrentPassword,
      );
      expect(storage.cleared, isFalse);
    },
  );

  test('a weak new password maps to weakPassword', () async {
    final api = _FakeProfileApi()
      ..getMeResults.add(_profile())
      ..changePasswordResults.add(
        const ApiException(
          message: 'Password must be at least 8 characters',
          code: 'VALIDATION_ERROR',
        ),
      );
    final container = _container(api);
    addTearDown(container.dispose);
    container.read(profileControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final ok = await container
        .read(profileControllerProvider.notifier)
        .changePassword(currentPassword: 'Old1!aaaa', newPassword: 'weak');

    expect(ok, isFalse);
    expect(
      container.read(profileControllerProvider).passwordError,
      PasswordChangeErrorKind.weakPassword,
    );
  });

  test('a second changePassword while one is in flight is ignored', () async {
    final completer = Completer<void>();
    final api = _FakeProfileApi()
      ..getMeResults.add(_profile())
      ..changePasswordResults.add(completer.future);
    final container = _container(api);
    addTearDown(container.dispose);
    container.read(profileControllerProvider);
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(profileControllerProvider.notifier);

    final first = notifier.changePassword(
      currentPassword: 'Old1!aaaa',
      newPassword: 'New1!aaaa',
    );
    final second = await notifier.changePassword(
      currentPassword: 'Old1!aaaa',
      newPassword: 'New1!aaaa',
    );

    expect(second, isFalse);
    completer.complete();
    await first;
    expect(api.changePasswordCalls, hasLength(1));
  });

  test(
    'uploadAvatar rejects an unsupported file type without calling the API',
    () async {
      final api = _FakeProfileApi()..getMeResults.add(_profile());
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .uploadAvatar(
            filePath: '/tmp/x.gif',
            fileName: 'x.gif',
            fileSizeBytes: 100,
          );

      expect(ok, isFalse);
      expect(
        container.read(profileControllerProvider).avatarError,
        AvatarErrorKind.invalidType,
      );
      expect(api.uploadAvatarCalls, isEmpty);
    },
  );

  test(
    'uploadAvatar rejects a file over 2MB without calling the API',
    () async {
      final api = _FakeProfileApi()..getMeResults.add(_profile());
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .uploadAvatar(
            filePath: '/tmp/x.png',
            fileName: 'x.png',
            fileSizeBytes: 3 * 1024 * 1024,
          );

      expect(ok, isFalse);
      expect(
        container.read(profileControllerProvider).avatarError,
        AvatarErrorKind.tooLarge,
      );
      expect(api.uploadAvatarCalls, isEmpty);
    },
  );

  test(
    'uploadAvatar succeeds and refreshes the profile with the new avatar',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile(avatarUrl: null))
        ..uploadAvatarResults.add('/uploads/avatars/1.jpg')
        ..getMeResults.add(_profile(avatarUrl: '/uploads/avatars/1.jpg'));
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .uploadAvatar(
            filePath: '/tmp/x.png',
            fileName: 'x.png',
            fileSizeBytes: 1024,
          );

      expect(ok, isTrue);
      expect(
        container.read(profileControllerProvider).profile.value?.avatarUrl,
        '/uploads/avatars/1.jpg',
      );
      expect(api.uploadAvatarCalls.single.fileName, 'x.png');
    },
  );

  test(
    'a failed avatar upload keeps the previous avatar and categorizes the error',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile(avatarUrl: '/uploads/avatars/old.jpg'))
        ..uploadAvatarResults.add(
          const ApiException(message: 'Server error', code: 'INTERNAL_ERROR'),
        );
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      final ok = await container
          .read(profileControllerProvider.notifier)
          .uploadAvatar(
            filePath: '/tmp/x.png',
            fileName: 'x.png',
            fileSizeBytes: 1024,
          );

      expect(ok, isFalse);
      final state = container.read(profileControllerProvider);
      expect(state.avatarError, AvatarErrorKind.generic);
      expect(state.profile.value?.avatarUrl, '/uploads/avatars/old.jpg');
    },
  );

  test(
    'invalidating the provider (the logout hook in main.dart) forces a fresh load next time it is read',
    () async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..getMeResults.add(_profile());
      final container = _container(api);
      addTearDown(container.dispose);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      container.invalidate(profileControllerProvider);
      container.read(profileControllerProvider);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(profileControllerProvider).profile.hasValue,
        isTrue,
      );
      expect(
        api.getMeResults,
        isEmpty,
        reason: 'both queued responses were consumed — load ran twice',
      );
    },
  );

  test('profile fields, addresses, and passwords are never printed', () async {
    final api = _FakeProfileApi()
      ..getMeResults.add(_profile())
      ..updateMeResults.add(null)
      ..getMeResults.add(_profile())
      ..changePasswordResults.add(null);
    final printed = <String>[];

    await runZoned(
      () async {
        final container = _container(api);
        addTearDown(container.dispose);
        container.read(profileControllerProvider);
        await Future<void>.delayed(Duration.zero);
        final notifier = container.read(profileControllerProvider.notifier);
        await notifier.save(_draft);
        await notifier.changePassword(
          currentPassword: 'Secret-Current1!',
          newPassword: 'Secret-New1!aaaa',
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

ProviderContainer _container(
  ProfileApi api, {
  SecureStorageService? storage,
  UserApi? userApi,
}) {
  final container = ProviderContainer(
    overrides: [
      profileApiProvider.overrideWithValue(api),
      secureStorageProvider.overrideWithValue(storage ?? _FakeSecureStorage()),
      if (userApi != null) userApiProvider.overrideWithValue(userApi),
    ],
  );
  // `profileControllerProvider` is `autoDispose` — a bare `container.read()`
  // doesn't keep it alive across `await` boundaries (same fix as the booking
  // and notifications provider tests).
  container.listen(profileControllerProvider, (previous, next) {});
  return container;
}

class _FakeSecureStorage extends SecureStorageService {
  bool cleared = false;

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> clear() async {
    cleared = true;
  }

  @override
  Future<String?> getLanguageCode() async => null;

  @override
  Future<void> saveLanguageCode(String code) async {}
}

class _FakeUserApi extends UserApi {
  _FakeUserApi() : super(Dio());

  final results = <UserProfileModel>[];
  int callCount = 0;

  @override
  Future<UserProfileModel> getMe() async {
    callCount++;
    return results.removeAt(0);
  }
}

class _FakeProfileApi extends ProfileApi {
  _FakeProfileApi() : super(Dio());

  final getMeResults = <Object>[];
  final updateMeResults = <Object?>[];
  final updateLanguageResults = <Object?>[];
  final uploadAvatarResults = <Object>[];
  final changePasswordResults = <Object?>[];

  final updateMeCalls = <ProfileEditModel>[];
  final updateLanguageCalls = <String>[];
  final uploadAvatarCalls = <({String filePath, String fileName})>[];
  final changePasswordCalls = <({String current, String next})>[];

  @override
  Future<UserProfileModel> getMe() {
    final next = getMeResults.removeAt(0);
    if (next is Future<UserProfileModel>) return next;
    if (next is UserProfileModel) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<void> updateMe(ProfileEditModel draft) {
    updateMeCalls.add(draft);
    final next = updateMeResults.removeAt(0);
    if (next is Future) return next as Future<void>;
    if (next == null) return Future.value();
    return Future.error(next);
  }

  @override
  Future<void> updateLanguagePreference(String language) {
    updateLanguageCalls.add(language);
    final next = updateLanguageResults.removeAt(0);
    if (next is Future) return next as Future<void>;
    if (next == null) return Future.value();
    return Future.error(next);
  }

  @override
  Future<String> uploadAvatar({
    required String filePath,
    required String fileName,
  }) {
    uploadAvatarCalls.add((filePath: filePath, fileName: fileName));
    final next = uploadAvatarResults.removeAt(0);
    if (next is Future<String>) return next;
    if (next is String) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    changePasswordCalls.add((current: currentPassword, next: newPassword));
    final next = changePasswordResults.removeAt(0);
    if (next is Future) return next as Future<void>;
    if (next == null) return Future.value();
    return Future.error(next);
  }
}

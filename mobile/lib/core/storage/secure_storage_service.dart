import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/storage_keys.dart';

/// Thin wrapper around [FlutterSecureStorage] for persisting auth session data.
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final StreamController<void> _sessionClearedController = StreamController<void>.broadcast();

  Stream<void> get onSessionCleared => _sessionClearedController.stream;

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: StorageKeys.accessToken, value: accessToken);
    await _storage.write(key: StorageKeys.refreshToken, value: refreshToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: StorageKeys.accessToken);

  Future<String?> getRefreshToken() => _storage.read(key: StorageKeys.refreshToken);

  Future<void> saveUserJson(String userJson) =>
      _storage.write(key: StorageKeys.user, value: userJson);

  Future<String?> getUserJson() => _storage.read(key: StorageKeys.user);

  Future<void> saveLanguageCode(String code) =>
      _storage.write(key: StorageKeys.languageCode, value: code);

  Future<String?> getLanguageCode() => _storage.read(key: StorageKeys.languageCode);

  Future<void> saveThemeMode(String mode) =>
      _storage.write(key: StorageKeys.themeMode, value: mode);

  Future<String?> getThemeMode() => _storage.read(key: StorageKeys.themeMode);

  Future<void> clear() async {
    await _storage.delete(key: StorageKeys.accessToken);
    await _storage.delete(key: StorageKeys.refreshToken);
    await _storage.delete(key: StorageKeys.user);
    _sessionClearedController.add(null);
  }
}

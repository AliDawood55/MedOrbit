import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../storage/secure_storage_service.dart';

/// App-wide light/dark/system preference. Client-only — unlike language,
/// the backend has no theme field anywhere (`preferred_language` is the only
/// preference column on `users`), so this never syncs to the server. Mirrors
/// [LocaleController]'s shape: default state first, then an async load of
/// whatever was persisted.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._storage) : super(ThemeMode.system) {
    _loadPersisted();
  }

  final SecureStorageService _storage;

  Future<void> _loadPersisted() async {
    final stored = await _storage.getThemeMode();
    final mode = _fromStorageValue(stored);
    if (mode != null) state = mode;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _storage.saveThemeMode(_toStorageValue(mode));
  }

  static ThemeMode? _fromStorageValue(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null,
    };
  }

  static String _toStorageValue(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }
}

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeMode>(
      (ref) => ThemeController(ref.watch(secureStorageProvider)),
    );

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../storage/secure_storage_service.dart';

/// Mirrors the web frontend's language toggle (`frontend/src/js/i18n.js`):
/// defaults to Arabic, persists the choice, and drives `dir`/text direction.
class LocaleController extends StateNotifier<Locale> {
  LocaleController(this._storage) : super(const Locale('ar')) {
    _loadPersisted();
  }

  final SecureStorageService _storage;

  Future<void> _loadPersisted() async {
    final code = await _storage.getLanguageCode();
    if (code == 'ar' || code == 'en') {
      state = Locale(code!);
    }
  }

  bool get isArabic => state.languageCode == 'ar';

  Future<void> toggle() async {
    final next = isArabic ? const Locale('en') : const Locale('ar');
    state = next;
    await _storage.saveLanguageCode(next.languageCode);
  }

  /// Sets a specific language rather than flipping between the two — used by
  /// the profile screen's explicit Arabic/English selector, where the user
  /// picks a value rather than toggling.
  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode != 'ar' && locale.languageCode != 'en') return;
    if (state.languageCode == locale.languageCode) return;
    state = locale;
    await _storage.saveLanguageCode(locale.languageCode);
  }
}

final localeControllerProvider =
    StateNotifierProvider<LocaleController, Locale>(
      (ref) => LocaleController(ref.watch(secureStorageProvider)),
    );

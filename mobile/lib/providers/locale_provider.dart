import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');

  void toggle() {
    state = state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

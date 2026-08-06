import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/theme_controller.dart';

void main() {
  test('defaults to system when nothing is persisted', () {
    final container = _container(_FakeStorage());
    addTearDown(container.dispose);

    expect(container.read(themeControllerProvider), ThemeMode.system);
  });

  test('loads a persisted mode on startup', () async {
    final container = _container(_FakeStorage(initial: 'dark'));
    addTearDown(container.dispose);

    // Providers are lazy — reading first is what actually constructs the
    // controller and starts its `_loadPersisted()`; awaiting before that
    // first read would just delay against nothing.
    container.read(themeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeControllerProvider), ThemeMode.dark);
  });

  test('ignores a corrupt persisted value and keeps the default', () async {
    final container = _container(_FakeStorage(initial: 'sepia'));
    addTearDown(container.dispose);

    container.read(themeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeControllerProvider), ThemeMode.system);
  });

  test('setThemeMode(light) updates state and persists', () async {
    final storage = _FakeStorage();
    final container = _container(storage);
    addTearDown(container.dispose);
    container.read(themeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(themeControllerProvider.notifier)
        .setThemeMode(ThemeMode.light);

    expect(container.read(themeControllerProvider), ThemeMode.light);
    expect(storage.saved, ['light']);
  });

  test('setThemeMode(dark) updates state and persists', () async {
    final storage = _FakeStorage();
    final container = _container(storage);
    addTearDown(container.dispose);
    container.read(themeControllerProvider);
    await Future<void>.delayed(Duration.zero);

    await container
        .read(themeControllerProvider.notifier)
        .setThemeMode(ThemeMode.dark);

    expect(container.read(themeControllerProvider), ThemeMode.dark);
    expect(storage.saved, ['dark']);
  });

  test(
    'setThemeMode(system) is also persisted explicitly, not just left as the default',
    () async {
      final storage = _FakeStorage(initial: 'dark');
      final container = _container(storage);
      addTearDown(container.dispose);
      // Let the persisted 'dark' value load fully *before* calling
      // setThemeMode — otherwise the still-in-flight load can resolve after
      // the explicit set and clobber it back to 'dark'.
      container.read(themeControllerProvider);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(themeControllerProvider), ThemeMode.dark);

      await container
          .read(themeControllerProvider.notifier)
          .setThemeMode(ThemeMode.system);

      expect(container.read(themeControllerProvider), ThemeMode.system);
      expect(storage.saved, ['system']);
    },
  );

  testWidgets(
    'a MaterialApp watching themeControllerProvider rebuilds its themeMode when the controller changes',
    (tester) async {
      // This is the exact mechanism `main.dart` relies on: `ref.watch(themeControllerProvider)`
      // feeding `MaterialApp.router(themeMode: ...)`. Asserts on the watched
      // value reaching a rebuilding widget directly, rather than on
      // `Theme.of(context).brightness` — resolving brightness routes through
      // `MaterialApp`'s own internal theme-merge machinery, which is Flutter's
      // concern to get right, not this controller's.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [secureStorageProvider.overrideWithValue(_FakeStorage())],
          child: Consumer(
            builder: (context, ref, _) {
              final mode = ref.watch(themeControllerProvider);
              return MaterialApp(
                theme: ThemeData.light(),
                darkTheme: ThemeData.dark(),
                themeMode: mode,
                home: Scaffold(
                  body: Column(
                    children: [
                      Text('mode:$mode'),
                      TextButton(
                        onPressed: () => ref
                            .read(themeControllerProvider.notifier)
                            .setThemeMode(ThemeMode.dark),
                        child: const Text('go dark'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.text('mode:ThemeMode.system'), findsOneWidget);

      await tester.tap(find.text('go dark'));
      await tester.pump();

      expect(find.text('mode:ThemeMode.dark'), findsOneWidget);
    },
  );
}

ProviderContainer _container(SecureStorageService storage) {
  return ProviderContainer(
    overrides: [secureStorageProvider.overrideWithValue(storage)],
  );
}

class _FakeStorage extends SecureStorageService {
  _FakeStorage({this.initial});

  final String? initial;
  final saved = <String>[];

  @override
  Future<String?> getThemeMode() async => initial;

  @override
  Future<void> saveThemeMode(String mode) async {
    saved.add(mode);
  }
}

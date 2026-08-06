import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/dio_client.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/features/auth/screens/login_screen.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('App boots through the splash to the login screen', (WidgetTester tester) async {
    // Startup does real work on the first frame: a host-reachability probe and
    // a secure-storage read for a persisted session. Neither has a backing
    // implementation under `flutter_test` — the probe would outlive the test
    // and trip the pending-timer invariant, and the storage read would raise a
    // MissingPluginException that leaves the splash spinning forever. Both are
    // stubbed so the boot sequence can actually run to completion.
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(
          SecureStorageService(storage: _InMemorySecureStorage()),
        ),
        dioClientProvider.overrideWith(
          (ref) => DioClient(ref.watch(secureStorageProvider))
            ..dio.httpClientAdapter = _OfflineAdapter()
            ..refreshClient.httpClientAdapter = _OfflineAdapter(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MedOrbitApp()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MedOrbitApp), findsOneWidget);
    // No persisted session, so the boot must land on login rather than leaving
    // the patient on an indefinite splash.
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}

/// Answers every request as unreachable, which is what a test host actually is.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({'success': false}),
      503,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Stands in for the platform keystore; starts empty, so there is no session.
class _InMemorySecureStorage implements FlutterSecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

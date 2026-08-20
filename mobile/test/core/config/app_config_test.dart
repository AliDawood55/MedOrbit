import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';

/// `String.fromEnvironment` is resolved at compile time, so a test cannot vary
/// the `--dart-define` values. These cover the pure resolution logic the
/// overrides feed into, plus the compiled-in development defaults.
void main() {
  group('backend base URL', () {
    test('defaults to the LAN host and always carries the /api prefix', () {
      expect(AppConfig.baseUrl, 'http://192.168.0.105:3001/api');
      expect(AppConfig.baseUrl, endsWith('/api'));
      expect(AppConfig.hasApiOverride, isFalse);
    });

    test('normalizeApiBase appends /api exactly once and is idempotent', () {
      const origin = 'https://backend.medorbit.example';
      final once = AppConfig.normalizeApiBase(origin);
      final twice = AppConfig.normalizeApiBase(once);

      expect(once, 'https://backend.medorbit.example/api');
      expect(twice, once);
      expect(twice, isNot(endsWith('/api/api')));
    });

    test('normalizeApiBase tolerates a trailing slash and surrounding space', () {
      expect(AppConfig.normalizeApiBase('https://a.example/'), 'https://a.example/api');
      expect(AppConfig.normalizeApiBase('  https://a.example  '), 'https://a.example/api');
      expect(AppConfig.normalizeApiBase('https://a.example/api/'), 'https://a.example/api');
    });
  });

  group('AI base URL', () {
    test('is derived from the resolved API host on port 8001 without /api', () {
      final aiBase = AppConfig.aiBaseFrom(AppConfig.baseUrl);

      expect(aiBase, 'http://192.168.0.105:8001');
      expect(aiBase, isNot(contains('/api')));
      expect(aiBase, isNot(endsWith('/')));
    });

    test('follows whichever host the API resolver settled on', () {
      expect(AppConfig.aiBaseFrom(AppConfig.emulatorBaseUrl), 'http://10.0.2.2:8001');
      expect(AppConfig.aiBaseFrom(AppConfig.localhostBaseUrl), 'http://localhost:8001');
    });

    test('normalizeAiBase strips any /api prefix and trailing slash', () {
      expect(AppConfig.normalizeAiBase('https://ai.example/api'), 'https://ai.example');
      expect(AppConfig.normalizeAiBase('https://ai.example/api/'), 'https://ai.example');
      expect(AppConfig.normalizeAiBase('https://ai.example/'), 'https://ai.example');
      expect(AppConfig.normalizeAiBase('https://ai.example'), 'https://ai.example');
    });

    test('backend and AI bases stay separate', () {
      expect(AppConfig.baseUrl, contains(':3001'));
      expect(AppConfig.aiBaseFrom(AppConfig.baseUrl), contains(':8001'));
      expect(AppConfig.aiServicePort, 8001);
    });
  });

  group('host candidates', () {
    test('without an override, probes LAN first then emulator and localhost', () {
      final candidates = AppConfig.candidatesFor('');

      expect(candidates, [
        AppConfig.devLanBaseUrl,
        AppConfig.emulatorBaseUrl,
        AppConfig.localhostBaseUrl,
      ]);
      expect(candidates.first, AppConfig.devLanBaseUrl);
      expect(AppConfig.baseUrlCandidates, candidates);
    });

    test('an explicit host is the only candidate, so localhost is never probed', () {
      // Guards the physical-device case: localhost and 10.0.2.2 resolve to the
      // phone itself, so a configured build must not silently fall back to them.
      final candidates = AppConfig.candidatesFor('https://api.medorbit.example');

      expect(candidates, ['https://api.medorbit.example/api']);
      expect(candidates, hasLength(1));
      expect(candidates.any((c) => c.contains('localhost')), isFalse);
      expect(candidates.any((c) => c.contains('10.0.2.2')), isFalse);
    });
  });

  group('timeout budgets', () {
    test('chat receive timeout clears the backend AI budget but stays bounded', () {
      // The backend's own AI client budget is ~60s; below that the app reports
      // a failure while the server is still working. Bounded well under the
      // Virtual Doctor's 120s.
      expect(AppConfig.chatAiReceiveTimeout.inSeconds, greaterThan(60));
      expect(AppConfig.chatAiReceiveTimeout.inSeconds, lessThanOrEqualTo(90));
      expect(AppConfig.chatAiReceiveTimeout, lessThan(AppConfig.aiMessageTimeout));
    });

    test('the global REST timeouts are unchanged', () {
      expect(AppConfig.connectTimeout, const Duration(seconds: 15));
      expect(AppConfig.receiveTimeout, const Duration(seconds: 15));
      expect(AppConfig.sendTimeout, const Duration(seconds: 15));
    });

    test('Virtual Doctor keeps its long per-endpoint budgets', () {
      expect(AppConfig.aiMessageTimeout, const Duration(seconds: 120));
      expect(AppConfig.sttTimeout, const Duration(seconds: 45));
      expect(AppConfig.ttsTimeout, const Duration(seconds: 30));
      expect(AppConfig.reportTimeout, const Duration(seconds: 60));
    });

    test('the AI health probe is short so it cannot stall a consultation', () {
      expect(AppConfig.aiHealthTimeout.inSeconds, inInclusiveRange(5, 10));
      expect(AppConfig.aiHealthTimeout, lessThan(AppConfig.connectTimeout));
    });
  });
}

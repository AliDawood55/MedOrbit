import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/config/app_config.dart';

/// `String.fromEnvironment` is resolved at compile time, so a test cannot vary
/// the `--dart-define` values. These cover the pure resolution logic the
/// overrides feed into. A build without an explicit origin must not silently
/// target a developer machine.
void main() {
  group('backend base URL', () {
    test('has no implicit developer-LAN backend target', () {
      expect(AppConfig.baseUrl, isEmpty);
      expect(AppConfig.hasApiOverride, isFalse);
      expect(AppConfig.baseUrlCandidates, isEmpty);
      expect(AppConfig.missingApiUrlMessage, contains('MEDORBIT_API_URL'));
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

  group('host candidates', () {
    test('without an override, does not probe any fallback machine', () {
      final candidates = AppConfig.candidatesFor('');

      expect(candidates, isEmpty);
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

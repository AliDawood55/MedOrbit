import 'package:flutter/foundation.dart';

/// Centralized environment configuration for the MedOrbit mobile app.
///
/// The backend runs on the developer's LAN, not localhost — a physical
/// test device reaches it over Wi-Fi, so `localhost`/`127.0.0.1` would only
/// resolve to the phone itself.
///
/// ## Environments
///
/// The LAN defaults below are **debug builds only** (`kDebugMode`). A
/// release or profile build without an explicit override throws instead of
/// silently pointing at the developer's LAN IP. A build targets any other
/// environment through `--dart-define`, with no source edit:
///
/// ```
/// flutter build apk \
///   --dart-define=MEDORBIT_API_URL=https://api.medorbit.example \
///   --dart-define=MEDORBIT_AI_URL=https://ai.medorbit.example
/// ```
///
/// TODO(production): production must terminate TLS. Serve both the backend and
/// the AI service over HTTPS behind a reverse proxy and pass those origins via
/// the defines above — the plain-HTTP defaults here will not work once
/// Android's network security config (see
/// `android/app/src/main/res/xml/network_security_config.xml`) stops
/// allowlisting the dev hosts, and iOS ATS blocks cleartext outright.
///
/// TODO(production): the AI service currently has no authentication and
/// wildcard CORS. It must sit behind an authenticated gateway before it is
/// reachable from anything wider than the development LAN.
class AppConfig {
  AppConfig._();

  /// Build-time overrides. Empty unless supplied via `--dart-define`.
  static const String _apiUrlOverride = String.fromEnvironment('MEDORBIT_API_URL');
  static const String _aiUrlOverride = String.fromEnvironment('MEDORBIT_AI_URL');

  /// Development default: the dev laptop's Wi-Fi LAN IP. This is the only
  /// entry that can work from a physical device.
  static const String devLanBaseUrl = 'http://192.168.0.105:3001/api';

  /// Android emulator's alias for the host machine's loopback.
  static const String emulatorBaseUrl = 'http://10.0.2.2:3001/api';

  /// Desktop/web debug builds running on the host machine itself.
  static const String localhostBaseUrl = 'http://localhost:3001/api';

  /// True when this build was given an explicit backend origin.
  static bool get hasApiOverride => _apiUrlOverride.isNotEmpty;

  /// True when this build was given an explicit AI service origin.
  static bool get hasAiOverride => _aiUrlOverride.isNotEmpty;

  /// The configured backend base URL — always ending in exactly one `/api`.
  ///
  /// Outside a debug build, a missing override throws rather than silently
  /// falling back to the developer's LAN IP.
  static String get baseUrl => resolveBaseUrl(debug: kDebugMode, apiUrlOverride: _apiUrlOverride);

  /// Pure resolution logic behind [baseUrl]. Split out because `kDebugMode`
  /// and `String.fromEnvironment` are both compile-time and cannot be varied
  /// from a test otherwise.
  static String resolveBaseUrl({required bool debug, required String apiUrlOverride}) {
    if (apiUrlOverride.isNotEmpty) return normalizeApiBase(apiUrlOverride);
    if (debug) return devLanBaseUrl;
    throw StateError(
      'MEDORBIT_API_URL must be set outside debug builds — pass '
      '--dart-define=MEDORBIT_API_URL=<backend origin>. The developer LAN '
      'default ($devLanBaseUrl) is never used for release/profile builds.',
    );
  }

  /// Probed in order at startup by `ApiHostResolver`; the first host that
  /// answers `GET /health` wins.
  ///
  /// Without an override the emulator/localhost entries only ever succeed on
  /// an emulator or a desktop/web build — from a real phone they resolve to
  /// the phone itself and always fail. They're here so the same build works
  /// across all three targets, not as a recovery path for a device outage.
  ///
  /// With an explicit override they are dropped entirely: a configured host is
  /// the only host that build is allowed to talk to. Outside a debug build,
  /// a missing override throws — see [resolveBaseUrl].
  static List<String> get baseUrlCandidates => candidatesFor(_apiUrlOverride);

  /// Candidate list for a given override value. Split out from
  /// [baseUrlCandidates] because `String.fromEnvironment` is resolved at
  /// compile time and cannot be varied from a test. `debug` defaults to
  /// `kDebugMode` for the same reason; tests pass it explicitly.
  static List<String> candidatesFor(String apiUrlOverride, {bool debug = kDebugMode}) {
    if (apiUrlOverride.isNotEmpty) {
      return <String>[normalizeApiBase(apiUrlOverride)];
    }
    if (!debug) {
      throw StateError(
        'MEDORBIT_API_URL must be set outside debug builds — pass '
        '--dart-define=MEDORBIT_API_URL=<backend origin>. The developer LAN '
        'default ($devLanBaseUrl) is never used for release/profile builds.',
      );
    }
    return const <String>[devLanBaseUrl, emulatorBaseUrl, localhostBaseUrl];
  }

  /// Forces a backend origin to end in exactly one `/api`, matching the web
  /// client's `MEDORBIT_API_URL` handling in `frontend/src/js/api.js`.
  /// Idempotent: normalizing an already-normalized value is a no-op.
  static String normalizeApiBase(String raw) {
    final trimmed = _stripTrailingSlash(raw.trim());
    if (trimmed.isEmpty) return trimmed;
    return trimmed.endsWith('/api') ? trimmed : '$trimmed/api';
  }

  /// Forces an AI origin to carry **no** `/api` prefix and no trailing slash —
  /// the AI service mounts its routes at the root.
  static String normalizeAiBase(String raw) {
    return _stripTrailingSlash(raw.trim().replaceFirst(RegExp(r'/api/?$'), ''));
  }

  static String _stripTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  /// The Python AI service is a **separate** process on its own port with no
  /// `/api` prefix and no JWT — the web app calls it directly the same way
  /// (`AI_BASE` in `frontend/src/js/virtual-doctor-stt.js`).
  static const int aiServicePort = 8001;

  /// Derives the AI service origin from whichever API host resolved, so both
  /// stay on the same machine (LAN / emulator / localhost). An explicit
  /// `MEDORBIT_AI_URL` wins, because in production the two services can live
  /// behind different hostnames rather than two ports on one box.
  static String aiBaseFrom(String apiBaseUrl) {
    if (hasAiOverride) return normalizeAiBase(_aiUrlOverride);
    final uri = Uri.parse(apiBaseUrl);
    return Uri(scheme: uri.scheme, host: uri.host, port: aiServicePort).toString();
  }

  /// Whisper decode + upload.
  ///
  /// The web client uses 20s, which is fine when the service has CUDA
  /// (~0.4-0.6s per utterance). Measured against this machine's Docker
  /// ai-service, which runs WITHOUT the `docker-compose.gpu.yml` overlay and
  /// therefore falls back to CPU: first transcription of a session **35.5s**,
  /// subsequent ones ~3.9-4.2s. A 20s budget aborts turn one every time even
  /// though the server does eventually answer correctly.
  ///
  /// Raised so the app survives CPU mode; the server keeps its own 10s decode
  /// deadline and returns `timed_out` gracefully, so this can't hang forever.
  static const Duration sttTimeout = Duration(seconds: 45);

  /// Piper synthesis is ~0.1 RTF, but a cold voice load costs a couple of
  /// seconds on the first sentence.
  static const Duration ttsTimeout = Duration(seconds: 30);

  /// The final `/message` turn runs the LLM reasoning pass inline, which has
  /// been measured at 23-44s on this hardware. Every earlier turn is ~20ms,
  /// so this budget only ever applies to the last one — but if it's too low
  /// the consultation dies exactly at the moment it produces its result.
  static const Duration aiMessageTimeout = Duration(seconds: 120);

  /// PDF render measured ~0.9s; generous headroom for a cold worker start.
  static const Duration reportTimeout = Duration(seconds: 60);

  static const String apiVersion = 'v1';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const Duration sendTimeout = Duration(seconds: 15);

  /// `POST /chat/message` proxies through to the backend's AI client, whose own
  /// budget is ~60s. The shared 15s REST receive timeout aborts a valid slow
  /// answer long before the server gives up, so the patient is told the message
  /// failed while the backend is still working on it.
  ///
  /// Bounded well above the server ceiling but nowhere near the Virtual
  /// Doctor's 120s — a chat turn that takes longer than this really has failed.
  /// Applied per request in `ChatbotApi.sendMessage` only; every other REST
  /// endpoint keeps the 15s default.
  static const Duration chatAiReceiveTimeout = Duration(seconds: 75);

  /// Upload side of the same request. The body is a short JSON message, so this
  /// only needs to survive a slow uplink, not the AI turn.
  static const Duration chatAiSendTimeout = Duration(seconds: 30);

  /// Preflight reachability check against the AI service's `GET /health`.
  /// Deliberately short: this answers "is the service there at all", and a
  /// patient waiting to start a consultation should not sit through the 120s
  /// AI budget just to learn the host is unreachable.
  static const Duration aiHealthTimeout = Duration(seconds: 8);

  /// How long an AI health result stays usable. Long enough that a double-tap
  /// or an immediate retry doesn't re-probe, short enough that a service coming
  /// back up is noticed on the next real attempt.
  static const Duration aiHealthCacheTtl = Duration(seconds: 30);

  /// Per-candidate budget while probing — short so a wrong host is skipped
  /// quickly instead of blocking the splash screen for the full timeout.
  static const Duration hostProbeTimeout = Duration(milliseconds: 2500);

  /// Origin (no `/api` suffix) — used to resolve relative asset URLs
  /// (e.g. `avatar_url`) returned by the backend, same as the web
  /// frontend's `API.getOrigin()`.
  static String originOf(String url) => url.replaceFirst(RegExp(r'/api/?$'), '');

  /// Origin for the compile-time primary host. Prefer
  /// `activeOriginProvider` at runtime so it tracks a resolved fallback.
  static String get originUrl => originOf(baseUrl);

  /// Same "Web application" OAuth client the backend already verifies
  /// Google ID tokens against (`GOOGLE_CLIENT_ID` in the root `.env`).
  /// Passed as `serverClientId` so the token audience matches what
  /// `auth.service.js#googleLogin` expects — see auth_provider.dart.
  static const String googleServerClientId =
      '414629025958-0h9kemkgt3p6h8fgso66jgr2l0g69hlb.apps.googleusercontent.com';
}

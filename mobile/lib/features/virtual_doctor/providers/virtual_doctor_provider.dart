import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/ai_health_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers/core_providers.dart';
import '../../auth/providers/auth_provider.dart';
import '../../billing/providers/billing_provider.dart';
import '../data/tts_player.dart';
import '../data/virtual_doctor_api.dart';
import '../data/voice_recorder.dart';
import '../models/consultation_models.dart';

/// Where the consultation currently is. Mirrors the web page's state
/// vocabulary, minus the hands-free VAD states — on mobile the patient
/// controls their turn with the mic button (push-to-talk), so `recording`
/// is entered deliberately rather than by voice-activity detection.
enum ConsultState {
  idle,
  connecting,
  listening, // mic armed, waiting for the patient to tap
  recording,
  transcribing,
  thinking,
  speaking,
  complete,
  error,
}

class VirtualDoctorState {
  const VirtualDoctorState({
    this.state = ConsultState.idle,
    this.transcript = const [],
    this.language = 'en',
    this.subtitle,
    this.errorMessage,
    this.micPermanentlyDenied = false,
    this.startedAt,
    this.completedAt,
    this.phase,
    this.chiefComplaint,
    this.profileSnapshot = const {},
    this.confidence,
    this.urgencyLevel,
    this.specialtyEn,
    this.specialtyAr,
    this.reportPath,
    this.isGeneratingReport = false,
    this.reportUnavailable = false,
    this.ttsUnavailable = false,
    this.recommendedSpecialtyId,
    this.differential = const [],
    this.recordingRemainingSeconds,
    this.recoveredSession = false,
    this.entitlementRetryAt,
    this.isEnding = false,
  });

  final ConsultState state;
  final List<TranscriptEntry> transcript;
  final String language;
  final String? subtitle;
  final String? errorMessage;
  final bool micPermanentlyDenied;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? phase;
  final String? chiefComplaint;
  final Map<String, dynamic> profileSnapshot;
  final double? confidence;
  final String? urgencyLevel;
  final String? specialtyEn;
  final String? specialtyAr;
  final String? reportPath;
  final bool isGeneratingReport;
  final bool reportUnavailable;
  final bool ttsUnavailable;
  final String? recommendedSpecialtyId;
  final List<Map<String, dynamic>> differential;
  final int? recordingRemainingSeconds;
  final bool recoveredSession;

  /// When [errorMessage] is `'voice_cooldown'`, the server-supplied timestamp
  /// the free consultation becomes available again — from the backend's
  /// `VOICE_COOLDOWN` `details.next_free_at`. Null whenever the backend did
  /// not supply one; the UI must never invent a time in that case.
  final DateTime? entitlementRetryAt;
  final bool isEnding;

  bool get isActive =>
      state != ConsultState.idle && state != ConsultState.error;
  bool get canRecord =>
      !isEnding &&
      (state == ConsultState.listening || state == ConsultState.recording);
  bool get isEmergency =>
      urgencyLevel == 'emergency' || urgencyLevel == 'urgent';

  VirtualDoctorState copyWith({
    ConsultState? state,
    List<TranscriptEntry>? transcript,
    String? language,
    String? subtitle,
    bool clearSubtitle = false,
    String? errorMessage,
    bool clearError = false,
    bool? micPermanentlyDenied,
    DateTime? startedAt,
    DateTime? completedAt,
    String? phase,
    String? chiefComplaint,
    Map<String, dynamic>? profileSnapshot,
    double? confidence,
    String? urgencyLevel,
    String? specialtyEn,
    String? specialtyAr,
    String? reportPath,
    bool? isGeneratingReport,
    bool? reportUnavailable,
    bool? ttsUnavailable,
    String? recommendedSpecialtyId,
    List<Map<String, dynamic>>? differential,
    int? recordingRemainingSeconds,
    bool clearRecordingRemainingSeconds = false,
    bool? recoveredSession,
    DateTime? entitlementRetryAt,
    bool clearEntitlementRetryAt = false,
    bool? isEnding,
  }) {
    return VirtualDoctorState(
      state: state ?? this.state,
      transcript: transcript ?? this.transcript,
      language: language ?? this.language,
      subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      micPermanentlyDenied: micPermanentlyDenied ?? this.micPermanentlyDenied,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      phase: phase ?? this.phase,
      chiefComplaint: chiefComplaint ?? this.chiefComplaint,
      profileSnapshot: profileSnapshot ?? this.profileSnapshot,
      confidence: confidence ?? this.confidence,
      urgencyLevel: urgencyLevel ?? this.urgencyLevel,
      specialtyEn: specialtyEn ?? this.specialtyEn,
      specialtyAr: specialtyAr ?? this.specialtyAr,
      reportPath: reportPath ?? this.reportPath,
      isGeneratingReport: isGeneratingReport ?? this.isGeneratingReport,
      reportUnavailable: reportUnavailable ?? this.reportUnavailable,
      ttsUnavailable: ttsUnavailable ?? this.ttsUnavailable,
      recommendedSpecialtyId:
          recommendedSpecialtyId ?? this.recommendedSpecialtyId,
      differential: differential ?? this.differential,
      recordingRemainingSeconds: clearRecordingRemainingSeconds
          ? null
          : (recordingRemainingSeconds ?? this.recordingRemainingSeconds),
      recoveredSession: recoveredSession ?? this.recoveredSession,
      entitlementRetryAt: clearEntitlementRetryAt
          ? null
          : (entitlementRetryAt ?? this.entitlementRetryAt),
      isEnding: isEnding ?? this.isEnding,
    );
  }
}

/// Built on the AUTHENTICATED api client, not the AI-service one.
///
/// The Virtual Doctor endpoints now live behind the MedOrbit backend, which
/// authenticates the user, checks entitlement, and only then talks to the AI
/// service over an internal credential. The app has no direct-AI client.
final virtualDoctorApiProvider = Provider<VirtualDoctorApi>(
  (ref) => VirtualDoctorApi(ref.watch(dioProvider)),
);

class VirtualDoctorController extends StateNotifier<VirtualDoctorState> {
  VirtualDoctorController(
    this._api,
    this._recorder,
    this._tts,
    this._health, {
    this._onEntitlementChanged,
  }) : super(const VirtualDoctorState());

  final VirtualDoctorApi _api;
  final VoiceRecorder _recorder;
  final TtsPlayer _tts;
  final AiHealthClient _health;
  final Future<void> Function()? _onEntitlementChanged;

  String? _sessionId;
  Timer? _recordingCapTimer;
  bool _disposed = false;

  /// Start is reachable from both the start card and the fatal-error retry
  /// button, and neither disables itself while the request is in flight. Two
  /// taps used to issue two `/virtual-doctor/start` calls, the second silently
  /// overwriting `_sessionId` and orphaning the first server-side session.
  bool _startInFlight = false;
  bool _endInFlight = false;

  void _set(VirtualDoctorState next) {
    if (_disposed) return;
    state = next;
  }

  void _appendDoctor(String text) {
    _set(
      state.copyWith(
        transcript: [
          ...state.transcript,
          TranscriptEntry(text: text, isDoctor: true),
        ],
      ),
    );
  }

  void _appendPatient(String text) {
    _set(
      state.copyWith(
        transcript: [
          ...state.transcript,
          TranscriptEntry(text: text, isDoctor: false),
        ],
      ),
    );
  }

  /// Begins a consultation: reachability -> permission -> /start -> greeting
  /// spoken aloud.
  Future<void> startConsultation(String language) async {
    if (_startInFlight || state.state == ConsultState.connecting) return;
    _startInFlight = true;
    try {
      await _start(language);
    } finally {
      _startInFlight = false;
    }
  }

  Future<void> _start(String language) async {
    // Reachability first, deliberately ahead of the permission prompt. The
    // backend gateway may be unavailable, and a fast health check avoids a
    // needless microphone prompt before `/virtual-doctor/start` can begin.
    if (await _health.check() != AiHealthStatus.available) {
      _set(
        state.copyWith(
          state: ConsultState.error,
          errorMessage: 'ai_unavailable',
        ),
      );
      return;
    }

    // Guarded: a plugin/platform failure here used to escape as an unhandled
    // async error, leaving the screen stuck on the start card with no message.
    MicPermissionResult permission;
    try {
      permission = await _recorder.ensurePermission();
    } catch (_) {
      // The raw exception is dropped: it reaches the screen as text and can
      // carry plugin internals or a device path.
      _set(
        state.copyWith(
          state: ConsultState.error,
          errorMessage: 'microphone unavailable',
        ),
      );
      return;
    }

    if (permission != MicPermissionResult.granted) {
      _set(
        state.copyWith(
          state: ConsultState.error,
          errorMessage: 'mic_denied',
          micPermanentlyDenied:
              permission == MicPermissionResult.permanentlyDenied,
        ),
      );
      return;
    }

    final startedAt = DateTime.now();
    _set(
      VirtualDoctorState(
        state: ConsultState.connecting,
        language: language,
        startedAt: startedAt,
      ),
    );
    try {
      final result = await _api.start(language: language);
      if (_disposed) return;
      _sessionId = result.sessionId;
      // The service echoes the session language; pin STT to it rather than
      // letting Whisper auto-detect, which is unreliable on short answers.
      _set(
        state.copyWith(
          language: result.language,
          phase: result.phase,
          transcript: result.messages.isEmpty
              ? state.transcript
              : result.messages,
          recoveredSession: result.resumed,
        ),
      );
      unawaited(_onEntitlementChanged?.call());

      // Preload Whisper + Piper behind the greeting so turn one isn't slow.
      unawaited(_api.warmup(result.language));

      if (result.reply.isNotEmpty) {
        final alreadyPresent =
            state.transcript.isNotEmpty &&
            state.transcript.last.isDoctor &&
            state.transcript.last.text == result.reply;
        if (!alreadyPresent) _appendDoctor(result.reply);
        await _speak(result.reply);
      }
      if (_disposed) return;
      _set(
        state.copyWith(
          state: result.phase == 'complete'
              ? ConsultState.complete
              : ConsultState.listening,
          clearSubtitle: true,
        ),
      );
    } catch (e) {
      // Health passed but the call still failed, so the cached pass is stale —
      // drop it so a retry re-probes instead of trusting it.
      _health.invalidate();
      final api = ApiException.from(e);
      if (_isEntitlementFailure(api)) {
        unawaited(_onEntitlementChanged?.call());
      }
      final retryAt = _retryAtFrom(api);
      _set(
        state.copyWith(
          state: ConsultState.error,
          errorMessage: _failureCode(api),
          entitlementRetryAt: retryAt,
          clearEntitlementRetryAt: retryAt == null,
        ),
      );
    }
  }

  /// Maps any AI failure onto a fixed vocabulary `AppStrings.vdError` knows.
  ///
  /// Two things used to reach the screen verbatim: `'start_${api.code}'`
  /// produced unmapped codes like `start_UNKNOWN_ERROR`, and the turn handlers
  /// passed `ApiException.message` straight through, leaving the displayed text
  /// to depend on substring luck against English transport copy.
  ///
  /// Billing/entitlement codes (`backend/src/config/billing.js`'s
  /// `ERROR_CODES`) are checked first and given their own vocabulary entries
  /// rather than collapsing into `'ai_failed'` — a cooldown or an exhausted
  /// quota is not the same failure as the AI service actually breaking, and
  /// telling the patient "something went wrong, try again" for a denial the
  /// backend will repeat on the very next attempt is actively misleading.
  static String _failureCode(ApiException api) {
    if (api.code == ApiException.codeVoiceCooldown) return 'voice_cooldown';
    if (api.code == ApiException.codeVoiceSessionActive) {
      return 'voice_session_active';
    }
    if (api.code == ApiException.codeFreeQuotaExhausted) {
      return 'free_quota_exhausted';
    }
    if (api.code == ApiException.codeSubscriptionRequired) {
      return 'subscription_required';
    }
    if (api.code == ApiException.codeSubscriptionInactive) {
      return 'subscription_inactive';
    }
    if (api.code == ApiException.codeEntitlementUnavailable) {
      return 'entitlement_unavailable';
    }
    if (api.code == ApiException.codeRateLimited) return 'rate_limited';
    if (api.code == ApiException.codeSessionStarting) return 'session_starting';
    if (api.code == ApiException.codeSessionUnavailable) {
      return 'session_unavailable';
    }
    if (api.code == ApiException.codeNotFound) return 'session_expired';
    if (api.isTimeout) return 'ai_timeout';
    if (api.code == ApiException.codeServiceUnavailable) {
      return 'ai_unreachable';
    }
    // The AI service answers 404 once a session has been evicted.
    if (api.statusCode == 404) return 'session_expired';
    return 'ai_failed';
  }

  /// The server-supplied cooldown-end timestamp, if the backend sent one.
  ///
  /// Only ever read for `VOICE_COOLDOWN` — every other denial has no such
  /// timestamp, and this must never be invented client-side.
  static DateTime? _retryAtFrom(ApiException api) {
    if (api.code != ApiException.codeVoiceCooldown) return null;
    final details = api.details;
    if (details is Map) {
      final raw = details['next_free_at'];
      if (raw is String) return DateTime.tryParse(raw);
    }
    return null;
  }

  static bool _isEntitlementFailure(ApiException api) {
    return api.code == ApiException.codeVoiceCooldown ||
        api.code == ApiException.codeVoiceSessionActive ||
        api.code == ApiException.codeSubscriptionRequired ||
        api.code == ApiException.codeSubscriptionInactive ||
        api.code == ApiException.codeEntitlementUnavailable;
  }

  Future<void> startRecording() async {
    if ((!state.canRecord && state.state != ConsultState.speaking) ||
        state.state == ConsultState.recording) {
      return;
    }
    try {
      if (state.state == ConsultState.speaking) await _tts.stop();
      await _recorder.start();
      _set(
        state.copyWith(
          state: ConsultState.recording,
          recordingRemainingSeconds: 30,
          clearError: true,
        ),
      );
      _recordingCapTimer?.cancel();
      _recordingCapTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final remaining = 30 - timer.tick;
        if (_disposed || state.state != ConsultState.recording) {
          timer.cancel();
          return;
        }
        if (remaining <= 0) {
          timer.cancel();
          _set(state.copyWith(recordingRemainingSeconds: 0));
          unawaited(stopRecordingAndSubmit());
          return;
        }
        _set(state.copyWith(recordingRemainingSeconds: remaining));
      });
    } catch (_) {
      _set(
        state.copyWith(
          state: ConsultState.listening,
          errorMessage: 'record_failed',
        ),
      );
    }
  }

  /// Stops capture, transcribes, and feeds the text into the interview engine.
  Future<void> stopRecordingAndSubmit() async {
    if (state.state != ConsultState.recording) return;

    _recordingCapTimer?.cancel();
    _set(
      state.copyWith(
        state: ConsultState.transcribing,
        clearRecordingRemainingSeconds: true,
      ),
    );
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }

    if (path == null) {
      _set(
        state.copyWith(
          state: ConsultState.listening,
          errorMessage: 'no_speech',
        ),
      );
      return;
    }

    try {
      final transcription = await _api.transcribe(
        filePath: path,
        language: state.language,
        sessionId: _sessionId ?? '',
      );
      unawaited(File(path).delete().catchError((_) => File(path!)));

      if (transcription.text.isEmpty) {
        _set(
          state.copyWith(
            state: ConsultState.listening,
            errorMessage: transcription.timedOut ? 'stt_timeout' : 'no_speech',
          ),
        );
        return;
      }

      _appendPatient(transcription.text);
      await _submit(transcription.text);
    } catch (e) {
      unawaited(File(path).delete().catchError((_) => File(path!)));
      final api = ApiException.from(e);
      if (_isEntitlementFailure(api)) {
        unawaited(_onEntitlementChanged?.call());
      }
      final retryAt = _retryAtFrom(api);
      _set(
        state.copyWith(
          state: ConsultState.listening,
          errorMessage: _failureCode(api),
          entitlementRetryAt: retryAt,
          clearEntitlementRetryAt: retryAt == null,
        ),
      );
    }
  }

  Future<void> cancelRecording() async {
    _recordingCapTimer?.cancel();
    await _recorder.cancel();
    if (state.state == ConsultState.recording) {
      _set(
        state.copyWith(
          state: ConsultState.listening,
          clearRecordingRemainingSeconds: true,
        ),
      );
    }
  }

  Future<void> _submit(String text) async {
    final sessionId = _sessionId;
    if (sessionId == null) return;

    _set(state.copyWith(state: ConsultState.thinking, clearError: true));
    try {
      final result = await _api.sendMessage(
        sessionId: sessionId,
        message: text,
      );
      _appendDoctor(result.reply);
      _set(
        state.copyWith(
          phase: result.phase,
          chiefComplaint: result.chiefComplaint,
          profileSnapshot: result.profileSnapshot.isEmpty
              ? state.profileSnapshot
              : result.profileSnapshot,
          confidence: result.confidence,
          urgencyLevel: result.urgencyLevel,
          specialtyEn: result.specialtyEn,
          specialtyAr: result.specialtyAr,
          recommendedSpecialtyId: result.recommendedSpecialtyId,
          differential: result.differential,
        ),
      );

      await _speak(result.reply);
      if (_disposed) return;

      _set(
        state.copyWith(
          state: result.isComplete
              ? ConsultState.complete
              : ConsultState.listening,
          completedAt: result.isComplete ? DateTime.now() : null,
          clearSubtitle: true,
        ),
      );
      if (result.isComplete) unawaited(_onEntitlementChanged?.call());
    } catch (e) {
      final api = ApiException.from(e);
      if (_isEntitlementFailure(api)) {
        unawaited(_onEntitlementChanged?.call());
      }
      final retryAt = _retryAtFrom(api);
      _set(
        state.copyWith(
          state: ConsultState.listening,
          errorMessage: _failureCode(api),
          entitlementRetryAt: retryAt,
          clearEntitlementRetryAt: retryAt == null,
        ),
      );
    }
  }

  Future<void> _speak(String text) async {
    _set(state.copyWith(state: ConsultState.speaking));
    final played = await _tts.speak(
      text,
      language: state.language,
      sessionId: _sessionId ?? '',
      onSentence: (sentence) => _set(state.copyWith(subtitle: sentence)),
    );
    _set(state.copyWith(ttsUnavailable: !played));
  }

  /// Silences the doctor mid-reply so the patient can take their turn.
  Future<void> skipSpeech() async {
    await _tts.stop();
    if (state.state == ConsultState.speaking) {
      _set(state.copyWith(state: ConsultState.listening, clearSubtitle: true));
    }
  }

  Future<void> openMicSettings() => _recorder.openSettings();

  Future<bool> restoreSession(String sessionId) async {
    if (sessionId.trim().isEmpty) return false;
    _set(state.copyWith(state: ConsultState.connecting, clearError: true));
    try {
      final result = await _api.getSession(sessionId);
      if (result.sessionId.isEmpty) {
        throw const ApiException(
          message: 'Session unavailable.',
          code: 'SESSION_UNAVAILABLE',
        );
      }
      _sessionId = result.sessionId;
      _set(
        state.copyWith(
          state: ConsultState.listening,
          language: result.language ?? state.language,
          phase: result.phase,
          chiefComplaint: result.chiefComplaint,
          profileSnapshot: result.profileSnapshot,
          urgencyLevel: result.urgencyLevel,
          recommendedSpecialtyId: result.recommendedSpecialtyId,
          specialtyEn: result.specialtyEn,
          specialtyAr: result.specialtyAr,
          differential: result.differential,
          transcript: result.messages,
          recoveredSession: true,
        ),
      );
      return true;
    } catch (error) {
      _set(
        state.copyWith(
          state: ConsultState.error,
          errorMessage: 'session_unavailable',
        ),
      );
      return false;
    }
  }

  /// Generates the PDF report and saves it to a readable location, returning
  /// the saved path (or null on failure) so the caller can open it without
  /// reaching into controller state.
  ///
  /// A 503 means the renderer is unavailable on the server — a known,
  /// separately-tracked fault — so the on-screen summary still stands.
  Future<String?> generateReport() async {
    final sessionId = _sessionId;
    if (sessionId == null || state.isGeneratingReport) return null;

    // Already fetched once this session — just reopen it.
    final existing = state.reportPath;
    if (existing != null) return existing;

    _set(
      state.copyWith(
        isGeneratingReport: true,
        reportUnavailable: false,
        clearError: true,
      ),
    );
    try {
      final report = await _api.createReport(sessionId);
      final bytes = await _api.downloadReport(report.downloadUrl);

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/medorbit_report_${report.reportId}.pdf');
      await file.writeAsBytes(bytes, flush: true);

      _set(state.copyWith(isGeneratingReport: false, reportPath: file.path));
      unawaited(_onEntitlementChanged?.call());
      return file.path;
    } catch (e) {
      final api = ApiException.from(e);
      final unavailable = api.statusCode == 503;
      _set(
        state.copyWith(
          isGeneratingReport: false,
          reportUnavailable: unavailable,
          errorMessage: unavailable ? null : 'report_failed',
        ),
      );
      return null;
    }
  }

  void clearError() =>
      _set(state.copyWith(clearError: true, clearEntitlementRetryAt: true));

  Future<bool> endConsultation() async {
    if (_endInFlight) return false;
    final sessionId = _sessionId;
    if (sessionId == null) {
      _set(const VirtualDoctorState());
      return true;
    }
    _endInFlight = true;
    _recordingCapTimer?.cancel();
    try {
      await _tts.stop();
      await _recorder.cancel();
      if (state.state != ConsultState.complete) {
        _set(state.copyWith(isEnding: true, clearError: true));
        await _api.endSession(sessionId);
      }
      _sessionId = null;
      _set(const VirtualDoctorState());
      unawaited(_onEntitlementChanged?.call());
      return true;
    } catch (_) {
      _set(state.copyWith(isEnding: false, errorMessage: 'end_failed'));
      return false;
    } finally {
      _endInFlight = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recordingCapTimer?.cancel();
    _tts.dispose();
    _recorder.dispose();
    super.dispose();
  }
}

final virtualDoctorControllerProvider =
    StateNotifierProvider.autoDispose<
      VirtualDoctorController,
      VirtualDoctorState
    >((ref) {
      ref.watch(
        authControllerProvider.select(
          (state) =>
              state.status == AuthStatus.authenticated ? state.user?.id : null,
        ),
      );
      final api = ref.watch(virtualDoctorApiProvider);
      return VirtualDoctorController(
        api,
        VoiceRecorder(),
        TtsPlayer(api),
        ref.watch(aiHealthClientProvider),
        onEntitlementChanged: ref
            .read(billingControllerProvider.notifier)
            .refreshEntitlements,
      );
    });

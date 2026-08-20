import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../models/consultation_models.dart';

/// Client for the MedOrbit backend's `/virtual-doctor/*` gateway.
///
/// These calls used to go straight to the Python AI service on port 8001 with
/// `user_id: null` and no credential of any kind, which meant a consultation
/// belonged to no account and enforced no entitlement. The AI service now
/// requires an internal service credential that a mobile app cannot hold, so
/// every call goes through the authenticated backend instead — the same
/// contract the web app uses.
///
/// This client therefore takes the *authenticated* Dio (the one carrying the
/// auth interceptor and the `/api` base), not the AI-service Dio.
class VirtualDoctorApi {
  VirtualDoctorApi(this._dio);

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  /// Unwrap the backend's `{success, data}` envelope.
  ///
  /// The AI service returned bare payloads; the backend wraps them in the
  /// project-wide response envelope. Unwrapping here keeps every model's
  /// `fromJson` unchanged.
  static Map<String, dynamic> _data(Map<String, dynamic>? body) {
    if (body == null) return const {};
    final data = body['data'];
    if (data is Map<String, dynamic>) return data;
    return body;
  }

  /// Starts a consultation, or rejoins the one already in progress.
  ///
  /// A relaunch, a reconnect or a duplicated tap returns the SAME session
  /// rather than starting a new one, so none of them costs the user their
  /// free consultation. `resumed` on the result says which happened.
  Future<StartResult> start({required String language}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/start',
      // No user_id: identity is taken from the access token server-side. A
      // client-supplied id would be forgeable and the backend does not read one.
      data: {'language': language},
      options: Options(
        extra: {'network.requestName': 'virtual_doctor.start'},
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: AppConfig.aiMessageTimeout,
      ),
    );
    return StartResult.fromJson(_data(response.data));
  }

  Future<MessageResult> sendMessage({required String sessionId, required String message}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/message',
      data: {'session_id': sessionId, 'message': message},
      options: Options(receiveTimeout: AppConfig.aiMessageTimeout),
    );
    return MessageResult.fromJson(_data(response.data));
  }

  Future<RestoredSessionResult> getSession(String sessionId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/virtual-doctor/session/$sessionId',
      options: Options(receiveTimeout: AppConfig.aiMessageTimeout),
    );
    return RestoredSessionResult.fromJson(_data(response.data));
  }

  /// Uploads one recorded utterance. `language` is pinned by the caller
  /// rather than auto-detected — detection is a coin flip on short answers.
  ///
  /// `sessionId` scopes the turn to a consultation the caller owns; without it
  /// the backend refuses, which is what stops transcription being usable as a
  /// free standalone service by anyone holding an account.
  Future<TranscriptionResult> transcribe({
    required String filePath,
    required String language,
    required String sessionId,
  }) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(filePath, filename: 'utterance.wav'),
      'language': language,
      'session_id': sessionId,
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/transcribe',
      data: form,
      options: Options(receiveTimeout: AppConfig.sttTimeout, sendTimeout: AppConfig.sttTimeout),
    );
    return TranscriptionResult.fromJson(_data(response.data));
  }

  /// Returns raw `audio/wav` bytes for one chunk of doctor speech.
  Future<Uint8List> speak({
    required String text,
    required String language,
    required String sessionId,
  }) async {
    final response = await _dio.post<List<int>>(
      '/virtual-doctor/speak',
      data: {'text': text, 'language': language, 'session_id': sessionId},
      options: Options(responseType: ResponseType.bytes, receiveTimeout: AppConfig.ttsTimeout),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<ReportResult> createReport(String sessionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/report/$sessionId',
      options: Options(receiveTimeout: AppConfig.reportTimeout),
    );
    return ReportResult.fromJson(_data(response.data));
  }

  /// Downloads a report PDF.
  ///
  /// The backend verifies the report belongs to the caller before streaming a
  /// byte of it, so a report id from another account resolves to "not found"
  /// rather than to somebody else's medical document.
  ///
  /// Accepts either a bare report id or the `download_url` the backend
  /// returned, since that URL is already `/api`-prefixed and this Dio's base
  /// ends in `/api` — passing it through unchanged would double the prefix.
  Future<Uint8List> downloadReport(String reportIdOrUrl) async {
    final id = reportIdOrUrl.contains('/')
        ? reportIdOrUrl.split('/').where((part) => part.isNotEmpty).toList().reversed.elementAt(1)
        : reportIdOrUrl;
    final response = await _dio.get<List<int>>(
      '/virtual-doctor/report/$id/download',
      options: Options(responseType: ResponseType.bytes, receiveTimeout: AppConfig.reportTimeout),
    );
    return Uint8List.fromList(response.data!);
  }

  /// Explicitly ends a consultation.
  ///
  /// Lets a patient who walks away close the session deliberately instead of
  /// waiting out the idle timeout.
  Future<void> endSession(String sessionId) async {
    await _dio.post<dynamic>('/virtual-doctor/session/$sessionId/end');
  }

  /// Fire-and-forget model preloads. Cold-loading Whisper costs ~9s and would
  /// otherwise land entirely on the patient's first answer; starting both now
  /// hides the load behind the doctor's greeting.
  Future<void> warmup(String language) async {
    await Future.wait([
      _dio
          .post<dynamic>('/virtual-doctor/transcribe/warmup', queryParameters: {'language': language})
          .catchError((_) => Response<dynamic>(requestOptions: RequestOptions())),
      _dio
          .post<dynamic>('/virtual-doctor/speak/warmup')
          .catchError((_) => Response<dynamic>(requestOptions: RequestOptions())),
    ]);
  }
}

import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../models/consultation_models.dart';

/// Client for the AI service's `/virtual-doctor/*` endpoints — the exact same
/// contract the web app uses (`ai-service/virtual_doctor/router.py`).
class VirtualDoctorApi {
  VirtualDoctorApi(this._dio);

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;

  Future<StartResult> start({required String language}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/start',
      data: {'language': language, 'user_id': null},
      options: Options(
        extra: {'network.requestName': 'virtual_doctor.start'},
        connectTimeout: AppConfig.connectTimeout,
        sendTimeout: const Duration(seconds: 30),
        receiveTimeout: AppConfig.aiMessageTimeout,
      ),
    );
    return StartResult.fromJson(response.data!);
  }

  Future<MessageResult> sendMessage({required String sessionId, required String message}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/message',
      data: {'session_id': sessionId, 'message': message},
      options: Options(receiveTimeout: AppConfig.aiMessageTimeout),
    );
    return MessageResult.fromJson(response.data!);
  }

  Future<RestoredSessionResult> getSession(String sessionId) async {
    final response = await _dio.get<Map<String, dynamic>>('/virtual-doctor/session/$sessionId', options: Options(receiveTimeout: AppConfig.aiMessageTimeout));
    return RestoredSessionResult.fromJson(response.data ?? const {});
  }

  /// Uploads one recorded utterance. `language` is pinned by the caller
  /// rather than auto-detected — detection is a coin flip on short answers.
  Future<TranscriptionResult> transcribe({
    required String filePath,
    required String language,
  }) async {
    final form = FormData.fromMap({
      'audio': await MultipartFile.fromFile(filePath, filename: 'utterance.wav'),
      'language': language,
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/transcribe',
      data: form,
      options: Options(receiveTimeout: AppConfig.sttTimeout, sendTimeout: AppConfig.sttTimeout),
    );
    return TranscriptionResult.fromJson(response.data!);
  }

  /// Returns raw `audio/wav` bytes for one chunk of doctor speech.
  Future<Uint8List> speak({required String text, required String language}) async {
    final response = await _dio.post<List<int>>(
      '/virtual-doctor/speak',
      data: {'text': text, 'language': language},
      options: Options(responseType: ResponseType.bytes, receiveTimeout: AppConfig.ttsTimeout),
    );
    return Uint8List.fromList(response.data!);
  }

  Future<ReportResult> createReport(String sessionId) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/virtual-doctor/report/$sessionId',
      options: Options(receiveTimeout: AppConfig.reportTimeout),
    );
    return ReportResult.fromJson(response.data!);
  }

  Future<Uint8List> downloadReport(String downloadUrl) async {
    final response = await _dio.get<List<int>>(
      downloadUrl,
      options: Options(responseType: ResponseType.bytes, receiveTimeout: AppConfig.reportTimeout),
    );
    return Uint8List.fromList(response.data!);
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

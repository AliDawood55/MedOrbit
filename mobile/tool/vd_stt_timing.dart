// Isolates the /transcribe latency question: is the 20s client timeout a real
// defect, or purely a cold-model artifact?
//
// Times a cold transcribe (if the model isn't resident), then warmup, then a
// warm transcribe — the app fires warmup at consultation start, so only the
// warm number reflects normal operation.
//
//   cd mobile && dart run tool/vd_stt_timing.dart

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';

Future<void> main() async {
  final accessToken = Platform.environment['MEDORBIT_ACCESS_TOKEN']?.trim();
  if (accessToken == null || accessToken.isEmpty) {
    stderr.writeln('Set MEDORBIT_ACCESS_TOKEN to a signed-in patient access token.');
    exitCode = 64;
    return;
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.aiMessageTimeout,
      sendTimeout: AppConfig.aiMessageTimeout,
      headers: {'Accept': 'application/json', 'Authorization': 'Bearer $accessToken'},
    ),
  );
  final api = VirtualDoctorApi(dio);
  // This timing tool uses one throwaway authenticated consultation session.
const spoken = 'عندي صداع شديد منذ يومين';
final sessionId = (await api.start(language: 'ar')).sessionId;
stdout.writeln('session: $sessionId');

final wav = await api.speak(
  text: spoken,
  language: 'ar',
  sessionId: sessionId,
);
  final clip = File('${Directory.systemTemp.path}/vd_stt_timing.wav');
  await clip.writeAsBytes(wav, flush: true);
  stdout.writeln('clip: ${wav.length} bytes\n');

  // Generous ceiling so we MEASURE the real duration instead of hitting the
  // app's own 20s budget and learning nothing.
  Future<void> attempt(String label) async {
    final sw = Stopwatch()..start();
    try {
      final res = await dio.post<Map<String, dynamic>>(
        '/virtual-doctor/transcribe',
        data: FormData.fromMap({
          'audio': await MultipartFile.fromFile(clip.path, filename: 'utterance.wav'),
          'language': 'ar',
          'session_id': sessionId,
        }),
        options: Options(receiveTimeout: const Duration(seconds: 180)),
      );
      sw.stop();
      stdout.writeln('$label ${sw.elapsedMilliseconds}ms  text="${res.data!['text']}" '
          'timed_out=${res.data!['timed_out']} proc=${res.data!['processing_seconds']}s');
    } catch (e) {
      sw.stop();
      stdout.writeln('$label ${sw.elapsedMilliseconds}ms  FAILED: $e');
    }
  }

  await attempt('cold transcribe :');
  final sw = Stopwatch()..start();
  await api.warmup('ar');
  sw.stop();
  stdout.writeln('warmup: ${sw.elapsedMilliseconds}ms');

  await attempt('warm transcribe :');
  //await attempt('warm transcribe :');

  await clip.delete();
  stdout.writeln('\nApp client budget (AppConfig.sttTimeout): ${AppConfig.sttTimeout.inSeconds}s');
}

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
  final aiBase = AppConfig.aiBaseFrom(AppConfig.baseUrl);
  final dio = Dio(
    BaseOptions(
      baseUrl: aiBase,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.aiMessageTimeout,
      sendTimeout: AppConfig.aiMessageTimeout,
      headers: {'Accept': 'application/json'},
    ),
  );
  final api = VirtualDoctorApi(dio);

  Future<void> status(String label) async {
    final res = await dio.get<Map<String, dynamic>>('/virtual-doctor/transcribe/status');
    final d = res.data!;
    stdout.writeln('$label loaded=${d['loaded']} models_loaded=${d['models_loaded']} '
        'device=${d['device']} timeout_s=${d['timeout_seconds']}');
  }

  await status('before :');

  // Prepare a real Arabic clip via TTS.
  const spoken = 'عندي صداع شديد منذ يومين';
  final wav = await api.speak(text: spoken, language: 'ar');
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
  await status('after cold :');

  final sw = Stopwatch()..start();
  await api.warmup('ar');
  sw.stop();
  stdout.writeln('warmup: ${sw.elapsedMilliseconds}ms');
  await status('after warmup:');

  await attempt('warm transcribe :');
  await attempt('warm transcribe :');

  await clip.delete();
  stdout.writeln('\nApp client budget (AppConfig.sttTimeout): ${AppConfig.sttTimeout.inSeconds}s');
}

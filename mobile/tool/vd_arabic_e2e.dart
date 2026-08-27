// Pre-flight for the Arabic Virtual Doctor flow, run through the
// authenticated backend gateway using the app's real `VirtualDoctorApi`.
//
// Covers the service-side half of the device checklist so that an on-device
// run only has to prove the device-specific parts (mic capture, audio output,
// PDF viewer):
//
//   1. Whisper transcription  — Arabic TTS clip fed back into /transcribe
//   2. Planner conversation   — full Arabic interview through to `complete`
//   3. PDF generation         — /report + /download, verified as a real PDF
//
//   cd mobile && dart run tool/vd_arabic_e2e.dart

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:mobile/core/config/app_config.dart';
import 'package:mobile/features/virtual_doctor/data/virtual_doctor_api.dart';

/// Plausible Arabic answers covering the usual intake + headache slots. The
/// engine drives the order, so these are consumed in sequence and repeated
/// if it asks more than expected.
const _answers = <String>[
  'علي',
  'خمسة وعشرون سنة',
  'عندي صداع شديد',
  'منذ يومين',
  // Deliberately moderate: "very severe" trips the safety short-circuit and
  // ends the interview before the reasoning pass ever runs.
  'الألم متوسط',
  'في مقدمة رأسي',
  'ألم نابض ومستمر',
  'نعم أشعر بالغثيان',
  'الضوء الساطع يزيد الألم',
  'لا يوجد شيء آخر',
  'لا',
  'نعم',
];

Future<void> main() async {
  final accessToken = Platform.environment['MEDORBIT_ACCESS_TOKEN']?.trim();
  if (accessToken == null || accessToken.isEmpty) {
    stderr.writeln('Set MEDORBIT_ACCESS_TOKEN to a signed-in patient access token.');
    exitCode = 64;
    return;
  }
  stdout.writeln('API base: ${AppConfig.baseUrl}\n');

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
  var failures = 0;
  final sessionId = (await api.start(language: 'ar')).sessionId;
  stdout.writeln('Started authenticated session: $sessionId\n');

  // ---- 1. Whisper transcription, via a TTS -> STT round trip -------------
  // Synthetic speech is easier than a real voice through a phone mic, so this
  // proves the pipeline works, not real-world accuracy.
  stdout.writeln('=== 1. Whisper transcription (Arabic TTS -> STT) ===');
  const spoken = 'عندي صداع شديد منذ يومين';
  try {
    // /speak is scoped to a consultation the caller owns, so this probe needs
    // its own throwaway session — it isn't otherwise used by this check.
    final probeSession = await api.start(language: 'ar');
    final wav = await api.speak(
      text: spoken,
      language: 'ar',
      sessionId: probeSession.sessionId,
    );
    final tmp = File('${Directory.systemTemp.path}/vd_ar_probe.wav');
    await tmp.writeAsBytes(wav, flush: true);
    stdout.writeln('  synthesized ${wav.length} bytes');

    final transcription = await api.transcribe(
      filePath: tmp.path,
      language: 'ar',
      sessionId: probeSession.sessionId,
    );
    stdout.writeln('  spoken     : $spoken');
    stdout.writeln('  transcribed: ${transcription.text}');
    stdout.writeln('  timed_out  : ${transcription.timedOut}');
    await tmp.delete();

    if (transcription.text.isEmpty) {
      failures++;
      stdout.writeln('  FAIL: empty transcript\n');
    } else {
      stdout.writeln('  PASS\n');
    }
  } catch (e, s) {
    failures++;
    stdout.writeln('  FAIL: ${e.runtimeType}: $e\n$s\n');
  }

  // ---- 2. Full Arabic consultation --------------------------------------
  stdout.writeln('=== 2. Arabic consultation (planner) ===');
  var completed = false;
  try {
    final restored = await api.getSession(sessionId);
    stdout.writeln('  session  : ${restored.sessionId}');
    stdout.writeln('  language : ${restored.language}');

    for (var turn = 0; turn < 16 && !completed; turn++) {
      final answer = _answers[turn % _answers.length];
      stdout.writeln('  P: $answer');
      final sw = Stopwatch()..start();
      final result = await api.sendMessage(sessionId: sessionId, message: answer);
      sw.stop();
      stdout.writeln('  D: ${result.reply}   [${result.phase}, ${sw.elapsedMilliseconds}ms]');
      if (result.isComplete) {
        completed = true;
        stdout.writeln('  urgency   : ${result.urgencyLevel}');
        stdout.writeln('  specialty : ${result.specialtyAr} / ${result.specialtyEn}');
        stdout.writeln('  confidence: ${result.confidence}');
      }
    }
    stdout.writeln(completed ? '  PASS: reached "complete"\n' : '  FAIL: never reached "complete"\n');
    if (!completed) failures++;
  } catch (e, s) {
    failures++;
    stdout.writeln('  FAIL: ${e.runtimeType}: $e\n$s\n');
  }

  // ---- 3. PDF report -----------------------------------------------------
  stdout.writeln('=== 3. PDF report ===');
  {
    try {
      final report = await api.createReport(sessionId);
      stdout.writeln('  report_id   : ${report.reportId}');
      stdout.writeln('  download_url: ${report.downloadUrl}');

      final pdf = await api.downloadReport(report.downloadUrl);
      final isPdf = pdf.length > 4 && pdf[0] == 0x25 && pdf[1] == 0x50 && pdf[2] == 0x44 && pdf[3] == 0x46;
      stdout.writeln('  bytes       : ${pdf.length}');
      stdout.writeln('  %PDF header : $isPdf');

      final out = File('${Directory.systemTemp.path}/vd_report_${report.reportId}.pdf');
      await out.writeAsBytes(pdf, flush: true);
      stdout.writeln('  saved       : ${out.path}');
      if (!isPdf) {
        failures++;
        stdout.writeln('  FAIL: not a PDF\n');
      } else {
        stdout.writeln('  PASS\n');
      }
    } on DioException catch (e) {
      failures++;
      stdout.writeln('  FAIL: ${e.type} status=${e.response?.statusCode} body=${e.response?.data}\n');
    } catch (e, s) {
      failures++;
      stdout.writeln('  FAIL: ${e.runtimeType}: $e\n$s\n');
    }
  }

  stdout.writeln(failures == 0 ? 'ALL PRE-FLIGHT CHECKS PASSED' : '$failures CHECK(S) FAILED');
  exit(failures == 0 ? 0 : 1);
}

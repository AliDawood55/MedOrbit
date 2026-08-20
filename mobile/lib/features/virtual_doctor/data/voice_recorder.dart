import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

enum MicPermissionResult { granted, denied, permanentlyDenied }

/// Push-to-talk capture for one patient utterance.
///
/// Records 16 kHz mono WAV: exactly what Whisper consumes, so the server does
/// no resampling, and an uncompressed container removes any codec/container
/// decode risk. On a LAN a 10s clip is ~320 KB, which is not worth compressing.
class VoiceRecorder {
  /// Created on first use. `AudioRecorder()`'s constructor reaches straight for
  /// a platform channel, so building it eagerly would bind the recorder plugin
  /// for every patient who merely has this class constructed — and makes the
  /// class impossible to fake in a unit test.
  AudioRecorder? _recorderInstance;
  AudioRecorder get _recorder => _recorderInstance ??= AudioRecorder();

  String? _currentPath;

  Future<MicPermissionResult> ensurePermission() async {
    final status = await Permission.microphone.request();
    if (status.isGranted || status.isLimited) return MicPermissionResult.granted;
    if (status.isPermanentlyDenied) return MicPermissionResult.permanentlyDenied;
    return MicPermissionResult.denied;
  }

  Future<void> openSettings() => openAppSettings();

  Future<bool> isRecording() => _recorder.isRecording();

  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/vd_utterance_${DateTime.now().millisecondsSinceEpoch}.wav';
    _currentPath = path;

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
        // Same capture constraints the web client asks getUserMedia for.
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
      ),
      path: path,
    );
  }

  /// Returns the recorded file path, or null if nothing usable was captured.
  Future<String?> stop() async {
    final path = await _recorder.stop() ?? _currentPath;
    _currentPath = null;
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;
    // A WAV header alone is 44 bytes; anything near that holds no audio.
    if (await file.length() < 2048) {
      await file.delete().catchError((_) => file);
      return null;
    }
    return path;
  }

  Future<void> cancel() async {
    try {
      await _recorder.stop();
    } catch (_) {
      // Already stopped.
    }
    final path = _currentPath;
    _currentPath = null;
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete().catchError((_) => file);
    }
  }

  /// Nothing to release if recording was never started — don't let disposal be
  /// the thing that first binds the plugin.
  Future<void> dispose() async => _recorderInstance?.dispose();
}

import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import 'virtual_doctor_api.dart';

/// Speaks a doctor reply aloud.
///
/// The reply is split into sentences and played in order, prefetching the next
/// while the current one plays — the same strategy as the web client. That
/// gets first audio out quickly, avoids gaps, and keeps every request under
/// the service's 800-character limit.
///
/// Contract, mirroring the web module: [speak] NEVER throws. A failure just
/// returns false, because a broken voice must not stall a consultation — the
/// text is on screen regardless.
class TtsPlayer {
  TtsPlayer(this._api);

  final VirtualDoctorApi _api;

  /// Created on first use. `AudioPlayer()` resolves `AudioSession.instance`,
  /// which sets a platform-channel handler in its constructor, so building it
  /// eagerly binds the audio session for every patient who merely has this
  /// class constructed — and makes the class impossible to fake in a unit test.
  AudioPlayer? _playerInstance;
  AudioPlayer get _player => _playerInstance ??= AudioPlayer();

  /// Bumped by [stop] and by each new utterance, so an in-flight sequence can
  /// detect it has been superseded and bail out.
  int _generation = 0;
  bool _speaking = false;

  bool get isSpeaking => _speaking;

  /// Split on sentence enders in both scripts, keeping the punctuation.
  /// Arabic uses ؟ and ۔; the full stop is the same glyph as Latin.
  static List<String> splitSentences(String text, {int maxChars = 300}) {
    final raw = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.isEmpty) return const [];

    final matches = RegExp(r'[^.!?؟۔\n]+[.!?؟۔]*\s*').allMatches(raw);
    final pieces = matches.isEmpty ? [raw] : matches.map((m) => m.group(0)!).toList();

    final out = <String>[];
    for (final piece in pieces) {
      var current = piece.trim();
      if (current.isEmpty) continue;

      // Break very long sentences on a comma/space so first audio still
      // arrives quickly and no request exceeds the server limit.
      while (current.length > maxChars) {
        var cut = current.lastIndexOf('،', maxChars);
        if (cut < maxChars * 0.4) cut = current.lastIndexOf(',', maxChars);
        if (cut < maxChars * 0.4) cut = current.lastIndexOf(' ', maxChars);
        if (cut <= 0) cut = maxChars;
        out.add(current.substring(0, cut + 1).trim());
        current = current.substring(cut + 1).trim();
      }
      if (current.isNotEmpty) out.add(current);
    }
    return out;
  }

  /// Plays [text] to completion. Returns false if any part failed to play.
  /// [onSentence] fires as each chunk starts, for subtitle display.
  Future<bool> speak(
    String text, {
    required String language,
    void Function(String sentence)? onSentence,
  }) async {
    await stop();
    final myGeneration = ++_generation;

    final sentences = splitSentences(text);
    if (sentences.isEmpty) return true;

    _speaking = true;
    try {
      Future<File?>? pending = _fetchClip(sentences.first, language);

      for (var i = 0; i < sentences.length; i++) {
        final file = await pending;
        if (myGeneration != _generation) return true; // superseded

        // Prefetch the next chunk while this one plays.
        pending = (i + 1 < sentences.length) ? _fetchClip(sentences[i + 1], language) : null;

        if (file == null) return false;

        onSentence?.call(sentences[i]);
        final played = await _playFile(file, myGeneration);
        if (!played) return myGeneration != _generation;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      if (myGeneration == _generation) _speaking = false;
    }
  }

  Future<File?> _fetchClip(String sentence, String language) async {
    try {
      final bytes = await _api.speak(text: sentence, language: language);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/vd_tts_${DateTime.now().microsecondsSinceEpoch}.wav');
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      // 503 = voice unavailable on the server; carry on with text only.
      return null;
    }
  }

  Future<bool> _playFile(File file, int myGeneration) async {
    try {
      await _player.setFilePath(file.path);
      if (myGeneration != _generation) return false;
      // play() completes when playback ends, or when stop() cancels it.
      await _player.play();
      // `playing` stays true after completion, and a subsequent play() would
      // then return immediately instead of awaiting the next clip — so reset.
      await _player.stop();
      return myGeneration == _generation;
    } catch (_) {
      return false;
    } finally {
      unawaited(file.delete().catchError((_) => file));
    }
  }

  /// Cuts speech off immediately. Safe to call at any time.
  Future<void> stop() async {
    _generation++;
    _speaking = false;
    try {
      // Nothing has ever played if the player was never built.
      await _playerInstance?.stop();
    } catch (_) {
      // Not playing.
    }
  }

  Future<void> dispose() async {
    _generation++;
    await _playerInstance?.dispose();
  }
}

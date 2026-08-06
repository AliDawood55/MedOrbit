import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A file selected via [ReportFilePicker.pickReportFile]. [path] is a real
/// local filesystem path (never a `content://` URI) — the native side
/// already copies the picked document into the app's cache directory before
/// returning, so [path] is always safe to hand straight to
/// `MultipartFile.fromFile`.
class PickedReportFile {
  const PickedReportFile({required this.path, required this.name, required this.sizeBytes});

  final String path;
  final String name;
  final int sizeBytes;
}

/// Platform file picker for Report Summarizer's PDF/image upload, backed by
/// a small native `MethodChannel` rather than a plugin package.
///
/// `file_picker` was removed: its bundled Android `build.gradle` called the
/// long-retired `jcenter()` repository and could not be made to build
/// against this project's Gradle/AGP setup without downgrading tooling
/// (explicitly out of scope). This channel is intentionally narrow — one
/// method, one purpose — matching the native implementation in
/// `android/app/src/main/kotlin/.../MainActivity.kt`.
class ReportFilePicker {
  ReportFilePicker._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('medorbit/report_file_picker');

  /// Launches the native document picker (PDF/PNG/JPG/JPEG only). Returns
  /// null if the user cancelled. Throws [PlatformException] (including
  /// [MissingPluginException] if no platform implementation is registered,
  /// e.g. iOS today or a test harness) on a genuine failure — callers are
  /// expected to catch it and show a safe, localized error rather than the
  /// raw exception text.
  static Future<PickedReportFile?> pickReportFile() async {
    final result = await channel.invokeMapMethod<String, dynamic>('pickReportFile');
    if (result == null) return null;
    final path = result['path'] as String?;
    final name = result['name'] as String?;
    final sizeBytes = result['sizeBytes'] as int?;
    if (path == null || name == null || sizeBytes == null) return null;
    return PickedReportFile(path: path, name: name, sizeBytes: sizeBytes);
  }
}

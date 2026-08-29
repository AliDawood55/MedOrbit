import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'prescriptions_api.dart';

/// The PDF downloaded successfully but couldn't be saved or opened on this
/// device (no compatible app, or the platform reported an error). Kept
/// distinct from [PrescriptionsApi.downloadPdf]'s `ApiException` so callers
/// can tell "we couldn't get the PDF" from "we have it, but can't show it".
class PrescriptionPdfOpenException implements Exception {
  const PrescriptionPdfOpenException();
}

/// Downloads one prescription's PDF into the app's temporary/cache
/// directory and hands it to the device's PDF-capable app.
///
/// Deliberately not persisted anywhere durable: this is a "view it now"
/// action, not a document-management feature, so app-private temp storage
/// (no storage permission needed) is enough.
class PrescriptionPdfService {
  /// [tempDirectory] and [openFile] are positional (not named) so the
  /// initializing-formal shorthand below can bind them straight to the
  /// private fields callers inject: a named parameter can't share a
  /// leading-underscore identifier with the field it fills, since that name
  /// would then be unusable as an argument label from outside this library.
  PrescriptionPdfService(
    this._api, [
    this._tempDirectory = getTemporaryDirectory,
    this._openFile = OpenFilex.open,
  ]);

  final PrescriptionsApi _api;
  final Future<Directory> Function() _tempDirectory;
  final Future<OpenResult> Function(String path) _openFile;

  /// A [PrescriptionsApi] failure (network, auth, invalid response)
  /// propagates as-is as an `ApiException` so callers can branch on it; a
  /// save/open failure throws [PrescriptionPdfOpenException] instead.
  Future<void> downloadAndOpen({
    required String prescriptionId,
    String? prescriptionNumber,
  }) async {
    final bytes = await _api.downloadPdf(prescriptionId);

    final File file;
    try {
      final dir = await _tempDirectory();
      file = File('${dir.path}/${_safeFilename(prescriptionNumber, prescriptionId)}');
      await file.writeAsBytes(bytes, flush: true);
    } catch (_) {
      throw const PrescriptionPdfOpenException();
    }

    final OpenResult result;
    try {
      result = await _openFile(file.path);
    } catch (_) {
      throw const PrescriptionPdfOpenException();
    }
    if (result.type != ResultType.done) {
      throw const PrescriptionPdfOpenException();
    }
  }

  /// Builds `MedOrbit_<safe>.pdf` from the prescription number (falling back
  /// to the id), keeping only `[A-Za-z0-9_-]` so no path separator, `..`, or
  /// control character from server/user text can ever reach the filesystem
  /// path.
  static String _safeFilename(String? prescriptionNumber, String id) {
    final fromNumber = _sanitizeComponent(prescriptionNumber);
    final base = fromNumber.isNotEmpty ? fromNumber : _sanitizeComponent(id);
    return 'MedOrbit_${base.isNotEmpty ? base : 'prescription'}.pdf';
  }

  static String _sanitizeComponent(String? input) {
    if (input == null) return '';
    return input.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  }
}

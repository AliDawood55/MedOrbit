import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/prescription_model.dart';

const _invalidResponse = ApiException(
  message: 'Unexpected response from server. Please try again.',
  code: 'INVALID_RESPONSE',
);

/// First 5 bytes of every valid PDF.
const _pdfSignature = '%PDF-';

class PrescriptionsApi {
  PrescriptionsApi(this._dio);

  final Dio _dio;

  /// A malformed entry fails the whole fetch rather than being silently
  /// dropped: a prescription quietly missing from the list would read to
  /// the patient as "you have no such prescription", which is worse than an
  /// error state they can retry.
  Future<List<PrescriptionModel>> list() async {
    final response = await _dio.get('/patients/me/prescriptions');
    final data = response.data is Map<String, dynamic> ? response.data['data'] : null;
    if (data is! List) throw _invalidResponse;
    return data.map((e) {
      if (e is! Map<String, dynamic>) throw _invalidResponse;
      return PrescriptionModel.fromJson(e);
    }).toList();
  }

  /// `GET /prescriptions/:id/pdf` — the server-generated PDF for one
  /// prescription. Ownership is enforced server-side (`requirePrescriptionRead`);
  /// the id alone is enough here, same as [PrescriptionsApi.list] never needs
  /// a patient id.
  ///
  /// The response is validated before it's handed back rather than trusted on
  /// a bare 200: an empty body, a non-PDF content type, or a body that isn't
  /// actually PDF-shaped all fail as an `INVALID_RESPONSE` [ApiException] so a
  /// caller never writes a JSON/HTML error page to disk with a `.pdf` name.
  Future<Uint8List> downloadPdf(String id) async {
    final response = await _dio.get<List<int>>(
      '/prescriptions/$id/pdf',
      options: Options(responseType: ResponseType.bytes),
    );

    final data = response.data;
    if (data == null || data.isEmpty) throw _invalidResponse;

    final contentType = response.headers.value('content-type');
    if (contentType != null && !contentType.toLowerCase().contains('application/pdf')) {
      throw _invalidResponse;
    }

    final bytes = Uint8List.fromList(data);
    if (bytes.length < _pdfSignature.length ||
        String.fromCharCodes(bytes.take(_pdfSignature.length)) != _pdfSignature) {
      throw _invalidResponse;
    }

    return bytes;
  }
}

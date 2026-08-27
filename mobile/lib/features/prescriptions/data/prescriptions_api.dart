import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/prescription_model.dart';

class PrescriptionsApi {
  PrescriptionsApi(this._dio);

  final Dio _dio;

  Future<List<PrescriptionModel>> list() async {
    final response = await _dio.get('/patients/me/prescriptions');
    final data = response.data['data'] as List;
    return data
        .map((e) => PrescriptionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Uint8List> downloadPdf(String prescriptionId) async {
    final response = await _dio.get<List<int>>(
      '/prescriptions/$prescriptionId/pdf',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Prescription PDF was empty.');
    }
    return Uint8List.fromList(bytes);
  }
}

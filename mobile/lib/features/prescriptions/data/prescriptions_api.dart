import 'package:dio/dio.dart';

import '../models/prescription_model.dart';

class PrescriptionsApi {
  PrescriptionsApi(this._dio);

  final Dio _dio;

  Future<List<PrescriptionModel>> list() async {
    final response = await _dio.get('/patients/me/prescriptions');
    final data = response.data['data'] as List;
    return data.map((e) => PrescriptionModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}

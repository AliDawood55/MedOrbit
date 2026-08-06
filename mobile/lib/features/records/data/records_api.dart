import 'package:dio/dio.dart';

import '../models/record_entry_model.dart';

class RecordsApi {
  RecordsApi(this._dio);

  final Dio _dio;

  Future<List<RecordEntryModel>> getTimeline() async {
    final response = await _dio.get('/patients/me/records');
    final data = response.data['data'] as Map<String, dynamic>;
    final timeline = data['timeline'] as List;
    return timeline.map((e) => RecordEntryModel.fromJson(e as Map<String, dynamic>)).toList();
  }
}

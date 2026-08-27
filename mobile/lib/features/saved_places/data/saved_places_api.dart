import 'package:dio/dio.dart';

import '../../../core/network/api_exception.dart';
import '../models/saved_place.dart';

class SavedPlacesApi {
  SavedPlacesApi(this._dio);
  final Dio _dio;

  Future<List<SavedPlace>> list() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/users/me/saved-places',
    );
    final envelope = response.data;
    if (envelope == null) {
      throw const ApiException(
        message: 'Empty response from server.',
        code: 'EMPTY_RESPONSE',
      );
    }
    if (envelope['success'] == false) {
      throw const ApiException(
        message: 'Request failed.',
        code: 'BACKEND_FAILURE',
      );
    }
    final data = envelope['data'];
    if (data is! Map || data['places'] is! List) {
      throw const ApiException(
        message: 'Unexpected response from server.',
        code: 'INVALID_RESPONSE',
      );
    }
    return (data['places'] as List)
        .map(
          (item) => SavedPlace.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList();
  }
}

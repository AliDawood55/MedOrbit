import 'package:dio/dio.dart';

import '../models/user_profile_model.dart';

class UserApi {
  UserApi(this._dio);

  final Dio _dio;

  Future<UserProfileModel> getMe() async {
    final response = await _dio.get('/users/me');
    return UserProfileModel.fromJson(response.data['data'] as Map<String, dynamic>);
  }
}

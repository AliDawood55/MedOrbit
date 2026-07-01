import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();

// Android emulator maps host loopback to 10.0.2.2
const apiBaseUrl = String.fromEnvironment(
  'MEDORBIT_API_BASE',
  defaultValue: 'http://10.0.2.2:8080',
);

Dio createDio() {
  final dio = Dio(BaseOptions(baseUrl: apiBaseUrl));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: 'accessToken');
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  return dio;
}

final dioProvider = Provider<Dio>((ref) => createDio());

class AuthApi {
  AuthApi(this._dio);
  final Dio _dio;

  Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    final res = await _dio.post<Map<String, dynamic>>('/api/v1/auth/register', data: data);
    return res.data ?? {};
  }

  Future<void> login(String email, String password) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    final body = res.data ?? {};
    await _storage.write(key: 'accessToken', value: body['accessToken'] as String?);
    await _storage.write(key: 'refreshToken', value: body['refreshToken'] as String?);
  }
}

class DoctorApi {
  DoctorApi(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> listDoctors() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/doctors');
    final doctors = res.data?['doctors'] as List<dynamic>? ?? [];
    return doctors.cast<Map<String, dynamic>>();
  }
}

final authApiProvider = Provider<AuthApi>((ref) => AuthApi(ref.watch(dioProvider)));
final doctorApiProvider = Provider<DoctorApi>((ref) => DoctorApi(ref.watch(dioProvider)));

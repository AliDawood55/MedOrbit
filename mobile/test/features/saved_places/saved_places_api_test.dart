import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/saved_places/data/saved_places_api.dart';

void main() {
  test('loads saved places from the authenticated user endpoint', () async {
    final fake = _FakeDio({
      'success': true,
      'data': {
        'places': [
          {
            'id': 'place-1',
            'place_name': 'Nablus Clinic',
            'place_type': 'clinic',
            'address': 'Rafidia',
            'distance_km': 1.2,
          },
        ],
      },
    });
    final places = await SavedPlacesApi(fake.dio).list();
    expect(fake.path, '/users/me/saved-places');
    expect(places.single.placeName, 'Nablus Clinic');
    expect(places.single.distanceKm, 1.2);
  });
}

class _FakeDio {
  _FakeDio(this.body) : dio = Dio() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          path = options.path;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: body,
            ),
          );
        },
      ),
    );
  }
  final Map<String, dynamic> body;
  final Dio dio;
  String? path;
}

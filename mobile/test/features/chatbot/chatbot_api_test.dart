import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/chatbot/data/chatbot_api.dart';
import 'package:mobile/features/chatbot/models/chatbot_models.dart';

void main() {
  test('sendMessage builds POST body and parses places doctors suggestions metadata', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'conversationId': 'conversation-1',
          'reply': 'Visit a nearby clinic.',
          'intent': 'find_clinic',
          'confidence': '0.94',
          'places': [
            {
              'id': 'place-1',
              'name_en': 'Nablus Clinic',
              'latitude': '32.2211',
              'longitude': '35.2544',
              'metadata': {'latitude': '32.2211', 'longitude': '35.2544'},
            },
          ],
          'doctors': [
            {'id': 'doctor-1', 'first_name_en': 'Mariam', 'average_rating': '4.8'},
          ],
          'suggestions': [
            {'text': 'Show clinic details', 'metadata': {'source': 'triage'}},
          ],
        },
      },
    ]);
    final api = ChatbotApi(fake.dio);

    final response = await api.sendMessage(
      const ChatMessageRequest(
        message: 'I need a clinic',
        conversationId: 'conversation-1',
        latitude: 32.2211,
        longitude: 35.2544,
      ),
    );

    expect(fake.requests.single.method, 'POST');
    expect(fake.requests.single.path, '/chat/message');
    expect(fake.requests.single.data, {
      'message': 'I need a clinic',
      'conversationId': 'conversation-1',
      'latitude': 32.2211,
      'longitude': 35.2544,
    });
    expect(response.places.single.metadata.latitude, 32.2211);
    expect(response.doctors.single.averageRating, 4.8);
    expect(response.suggestions.single.metadata.values['source'], 'triage');
  });

  test('conversation list search and detail parse correctly', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'conversations': [
            {'id': 'conversation-1', 'title': 'Headache', 'message_count': '2'},
          ],
          'pagination': {'page': '1', 'limit': '50', 'total': '1'},
        },
      },
      {
        'success': true,
        'data': {
          'conversations': [
            {'id': 'conversation-2', 'title': 'Clinic search'},
          ],
        },
      },
      {
        'success': true,
        'data': {
          'conversation': {'id': 'conversation-1', 'title': 'Headache'},
          'messages': [
            {
              'id': 'message-1',
              'message_text': 'I have a headache',
              'message_type': 'user',
              'metadata': {'severity': 'mild'},
            },
          ],
          'places': [
            {'id': 'place-1', 'name_en': 'Saved Clinic'},
          ],
          'messageCount': '1',
        },
      },
    ]);
    final api = ChatbotApi(fake.dio);

    final list = await api.listConversations(search: 'headache');
    final search = await api.searchConversations('clinic');
    final detail = await api.getConversation('conversation-1', limit: 25, offset: 5);

    expect(fake.requests[0].path, '/conversations');
    expect(fake.requests[0].queryParameters, {'page': 1, 'limit': 50, 'search': 'headache'});
    expect(list.conversations.single.messageCount, 2);
    expect(list.pagination?.total, 1);
    expect(fake.requests[1].path, '/conversations/search');
    expect(fake.requests[1].queryParameters, {'q': 'clinic'});
    expect(search.single.id, 'conversation-2');
    expect(fake.requests[2].path, '/conversations/conversation-1');
    expect(fake.requests[2].queryParameters, {'limit': 25, 'offset': 5});
    expect(detail.messages.single.metadata.values['severity'], 'mild');
    expect(detail.places.single.nameEn, 'Saved Clinic');
  });

  test('rename delete and generated title endpoints use correct method path and body', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {'id': 'conversation-1', 'title': 'Updated title'},
      },
      {'success': true, 'data': null},
      {
        'success': true,
        'data': {'id': 'conversation-1', 'title': 'Auto title'},
      },
    ]);
    final api = ChatbotApi(fake.dio);

    final renamed = await api.renameConversation('conversation-1', title: 'Updated title');
    await api.deleteConversation('conversation-1');
    final generated = await api.generateConversationTitle('conversation-1');

    expect(renamed.title, 'Updated title');
    expect(fake.requests[0].method, 'PUT');
    expect(fake.requests[0].path, '/conversations/conversation-1');
    expect(fake.requests[0].data, {'title': 'Updated title'});
    expect(fake.requests[1].method, 'DELETE');
    expect(fake.requests[1].path, '/conversations/conversation-1');
    expect(fake.requests[2].method, 'POST');
    expect(fake.requests[2].path, '/conversations/conversation-1/title');
    expect(generated.title, 'Auto title');
  });

  test('saved places endpoints parse and preserve optional fields', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {
          'places': [
            {'id': 'place-1', 'name_en': 'Saved Clinic', 'distance_km': '1.2'},
          ],
        },
      },
      {
        'success': true,
        'data': {
          'id': 'place-2',
          'name_en': 'Pharmacy',
          'latitude': '32.2',
          'longitude': '35.2',
          'rating': '4.5',
        },
      },
    ]);
    final api = ChatbotApi(fake.dio);

    final places = await api.listConversationPlaces('conversation-1');
    final saved = await api.saveConversationPlace(
      'conversation-1',
      placeName: 'Pharmacy',
      placeType: 'pharmacy',
      latitude: 32.2,
      longitude: 35.2,
      rating: 4.5,
    );

    expect(fake.requests[0].method, 'GET');
    expect(fake.requests[0].path, '/conversations/conversation-1/places');
    expect(places.single.distanceKm, 1.2);
    expect(fake.requests[1].method, 'POST');
    expect(fake.requests[1].path, '/conversations/conversation-1/places');
    expect(fake.requests[1].data, {
      'placeName': 'Pharmacy',
      'placeType': 'pharmacy',
      'latitude': 32.2,
      'longitude': 35.2,
      'rating': 4.5,
    });
    expect(saved.extra['rating'], '4.5');
  });

  test('createConversation omits null language and success false throws ApiException', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {'id': 'conversation-1', 'title': null},
      },
      {'success': false, 'message': 'Cannot create conversation', 'data': {'raw': 'not exposed'}},
    ]);
    final api = ChatbotApi(fake.dio);

    final conversation = await api.createConversation();

    expect(conversation.id, 'conversation-1');
    expect(fake.requests.first.data, isEmpty);
    await expectLater(
      api.createConversation(language: 'en'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'BACKEND_FAILURE')
            .having((error) => error.message, 'message', 'Cannot create conversation')
            .having((error) => error.details, 'details', isNull),
      ),
    );
  });

  test('client does not print or manually log request or response bodies', () async {
    final fake = _FakeDio([
      {
        'success': true,
        'data': {'conversationId': 'conversation-1', 'reply': 'Private medical reply'},
      },
    ]);
    final api = ChatbotApi(fake.dio);
    final printed = <String>[];

    await runZoned(
      () => api.sendMessage(const ChatMessageRequest(message: 'Private medical message')),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(printed, isEmpty);
  });
}

class _FakeDio {
  _FakeDio(List<Map<String, dynamic>> responses)
    : dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(
            _RecordedRequest(
              method: options.method,
              path: options.path,
              data: options.data,
              queryParameters: Map<String, dynamic>.from(options.queryParameters),
            ),
          );
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: responses.removeAt(0),
            ),
          );
        },
      ),
    );
  }

  final Dio dio;
  final requests = <_RecordedRequest>[];
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.data,
    required this.queryParameters,
  });

  final String method;
  final String path;
  final dynamic data;
  final Map<String, dynamic> queryParameters;
}

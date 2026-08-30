import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/features/messaging/data/messaging_api.dart';

void main() {
  group('MessagingApi', () {
    test(
      'lists conversations with the exact path and server pagination query',
      () async {
        final fake = _FakeDio([
          _envelope({
            'items': [_conversation()],
            'limit': 25,
            'offset': 5,
          }),
        ]);
        final page = await MessagingApi(
          fake.dio,
        ).listConversations(limit: 25, offset: 5);

        expect(page.items.single.id, _conversationId);
        expect(fake.requests.single.method, 'GET');
        expect(fake.requests.single.path, '/messages/conversations');
        expect(fake.requests.single.queryParameters, {
          'limit': 25,
          'offset': 5,
        });
      },
    );

    test(
      'creates a conversation with counterpartId and no ownership authority',
      () async {
        final fake = _FakeDio([_envelope(_conversation())]);
        await MessagingApi(fake.dio).createConversation(_counterpartId);

        final body = Map<String, dynamic>.from(
          fake.requests.single.data as Map,
        );
        expect(body, {'counterpartId': _counterpartId});
        expect(
          body.keys,
          isNot(containsAll(['role', 'relationship_id', 'user_id'])),
        );
      },
    );

    test('history sends opaque older and after cursors unchanged', () async {
      final fake = _FakeDio([
        _envelope({
          'items': [_message()],
          'next_cursor': 'older',
          'latest_cursor': 'latest',
        }),
        _envelope({
          'items': <dynamic>[],
          'next_cursor': null,
          'latest_cursor': null,
        }),
      ]);
      final api = MessagingApi(fake.dio);
      final page = await api.listMessages(
        _conversationId,
        cursor: 'opaque-old',
        limit: 40,
      );
      await api.listMessages(_conversationId, after: 'opaque-new', limit: 50);

      expect(page.items.single.body, 'Hello');
      expect(
        fake.requests[0].path,
        '/messages/conversations/$_conversationId/messages',
      );
      expect(fake.requests[0].queryParameters, {
        'limit': 40,
        'cursor': 'opaque-old',
      });
      expect(fake.requests[1].queryParameters, {
        'limit': 50,
        'after': 'opaque-new',
      });
    });

    test('send body contains only text and stable client_message_id', () async {
      final fake = _FakeDio([
        _envelope({..._message(), 'idempotent': false}),
      ]);
      await MessagingApi(fake.dio).sendMessage(
        conversationId: _conversationId,
        body: 'Hello',
        clientMessageId: _clientMessageId,
      );

      expect(fake.requests.single.data, {
        'body': 'Hello',
        'client_message_id': _clientMessageId,
      });
      expect(
        (fake.requests.single.data as Map).keys,
        isNot(contains('sender_user_id')),
      );
    });

    test(
      'mark-read supports exact message body and empty latest body',
      () async {
        final read = {
          'conversation_id': _conversationId,
          'last_read_message_id': _messageId,
          'last_read_at': _now,
        };
        final fake = _FakeDio([_envelope(read), _envelope(read)]);
        final api = MessagingApi(fake.dio);
        await api.markRead(_conversationId, messageId: _messageId);
        await api.markRead(_conversationId);

        expect(fake.requests[0].data, {'message_id': _messageId});
        expect(fake.requests[1].data, <String, dynamic>{});
      },
    );

    test('accept and decline use exact empty POST endpoints', () async {
      final fake = _FakeDio([
        _envelope({
          ..._conversation(),
          'request_status': 'accepted',
          'can_respond_to_request': false,
        }),
        _envelope({
          'id': _conversationId,
          'status': 'closed',
          'request_status': 'declined',
        }),
      ]);
      final api = MessagingApi(fake.dio);
      await api.acceptRequest(_conversationId);
      final declined = await api.declineRequest(_conversationId);

      expect(
        fake.requests[0].path,
        '/messages/conversations/$_conversationId/accept',
      );
      expect(
        fake.requests[1].path,
        '/messages/conversations/$_conversationId/decline',
      );
      expect(
        fake.requests.map((request) => request.data),
        everyElement(<String, dynamic>{}),
      );
      expect(declined.requestStatus, 'declined');
    });

    test(
      'doctor discovery sends supported search, page, and limit only',
      () async {
        final fake = _FakeDio([
          _envelope({
            'doctors': [_doctor()],
            'pagination': {},
          }),
        ]);
        final result = await MessagingApi(
          fake.dio,
        ).searchDoctors('family', limit: 20);

        expect(result.single.id, _counterpartId);
        expect(fake.requests.single.path, '/doctors');
        expect(fake.requests.single.queryParameters, {
          'search': 'family',
          'page': 1,
          'limit': 20,
        });
      },
    );

    test(
      'patient discovery and own doctor profile use verified backend paths',
      () async {
        final fake = _FakeDio([
          _envelope({
            'items': [_patient()],
            'limit': 20,
          }),
          _envelope({'id': _counterpartId}),
        ]);
        final api = MessagingApi(fake.dio);
        final patients = await api.searchPatients('Nablus');
        final ownId = await api.getOwnDoctorId();

        expect(patients.single.city, 'Nablus');
        expect(ownId, _counterpartId);
        expect(fake.requests[0].path, '/patients/discover');
        expect(fake.requests[1].path, '/doctors/me/profile');
      },
    );

    test(
      'patient request preference uses exact profile paths and boolean authority only',
      () async {
        final fake = _FakeDio([
          _envelope({'allow_doctor_messages': false}),
          _envelope({'allow_doctor_messages': true}),
        ]);
        final api = MessagingApi(fake.dio);

        final current = await api.getPatientMessagingPreference();
        final updated = await api.updatePatientMessagingPreference(true);

        expect(current.allowDoctorMessages, isFalse);
        expect(updated.allowDoctorMessages, isTrue);
        expect(fake.requests[0].method, 'GET');
        expect(fake.requests[0].path, '/patients/me/profile');
        expect(fake.requests[1].method, 'PUT');
        expect(fake.requests[1].path, '/patients/me/profile');
        expect(fake.requests[1].data, {'allowDoctorMessages': true});
        expect(
          (fake.requests[1].data as Map).keys,
          isNot(containsAll(['user_id', 'role', 'bio', 'city'])),
        );
      },
    );

    test(
      'patient request preference rejects a malformed server boolean',
      () async {
        final fake = _FakeDio([
          _envelope({'allow_doctor_messages': 'yes'}),
        ]);

        await expectLater(
          MessagingApi(fake.dio).getPatientMessagingPreference(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'INVALID_RESPONSE',
            ),
          ),
        );
      },
    );

    test(
      'preserves structured backend error code and details from a false envelope',
      () async {
        final fake = _FakeDio([
          {
            'success': false,
            'error': {
              'code': 'MESSAGE_REQUEST_COOLDOWN',
              'message': 'raw server text',
              'details': {'private': true},
            },
          },
        ]);

        await expectLater(
          MessagingApi(fake.dio).createConversation(_counterpartId),
          throwsA(
            isA<ApiException>()
                .having(
                  (error) => error.code,
                  'code',
                  'MESSAGE_REQUEST_COOLDOWN',
                )
                .having((error) => error.details, 'details', {'private': true}),
          ),
        );
      },
    );

    test(
      'rejects null, non-map, and malformed typed data as INVALID_RESPONSE',
      () async {
        final fake = _FakeDio([
          {'success': true, 'data': null},
          _envelope({
            'items': [
              {'id': 7},
            ],
            'limit': 1,
            'offset': 0,
          }),
        ]);
        final api = MessagingApi(fake.dio);

        for (var i = 0; i < 2; i++) {
          await expectLater(
            i == 0
                ? api.createConversation(_counterpartId)
                : api.listConversations(),
            throwsA(
              isA<ApiException>().having(
                (error) => error.code,
                'code',
                'INVALID_RESPONSE',
              ),
            ),
          );
        }
      },
    );
  });
}

const _conversationId = '123e4567-e89b-42d3-a456-426614174000';
const _counterpartId = '223e4567-e89b-42d3-a456-426614174001';
const _userId = '323e4567-e89b-42d3-a456-426614174002';
const _messageId = '423e4567-e89b-42d3-a456-426614174003';
const _clientMessageId = '523e4567-e89b-42d3-a456-426614174004';
const _now = '2026-08-29T12:00:00.000Z';

Map<String, dynamic> _envelope(Object? data) => {'success': true, 'data': data};
Map<String, dynamic> _conversation() => {
  'id': _conversationId,
  'status': 'active',
  'conversation_type': 'patient_doctor',
  'request_status': 'pending',
  'initiated_by_user_id': _userId,
  'request_updated_at': _now,
  'created_at': _now,
  'last_message_at': null,
  'other_role': 'doctor',
  'other_avatar_url': null,
  'other_display_name': 'Dr Lina',
  'last_message_id': null,
  'last_message_preview': null,
  'last_sender_user_id': null,
  'last_message_created_at': null,
  'can_respond_to_request': true,
  'unread_count': 2,
};
Map<String, dynamic> _message() => {
  'id': _messageId,
  'conversation_id': _conversationId,
  'sender_user_id': _userId,
  'client_message_id': _clientMessageId,
  'body': 'Hello',
  'message_type': 'text',
  'created_at': _now,
};
Map<String, dynamic> _doctor() => {
  'id': _counterpartId,
  'first_name_en': 'Lina',
  'last_name_en': 'Saleh',
  'specialty_en': 'Family medicine',
};
Map<String, dynamic> _patient() => {
  'id': _counterpartId,
  'first_name_en': 'Omar',
  'last_name_en': 'Haddad',
  'city': 'Nablus',
};

class _FakeDio {
  _FakeDio(List<Map<String, dynamic>> responses)
    : _responses = [...responses],
      dio = Dio(BaseOptions(baseUrl: 'https://example.test/api')) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: _responses.removeAt(0),
            ),
          );
        },
      ),
    );
  }

  final Dio dio;
  final List<Map<String, dynamic>> _responses;
  final List<RequestOptions> requests = [];
}

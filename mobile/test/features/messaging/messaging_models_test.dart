import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/messaging/models/messaging_models.dart';

void main() {
  test(
    'conversation parses request, unread, role, preview, and server dates',
    () {
      final conversation = CareConversation.fromJson(_conversation());

      expect(conversation.id, _conversationId);
      expect(conversation.isPending, isTrue);
      expect(conversation.canRespondToRequest, isTrue);
      expect(conversation.unreadCount, 3);
      expect(conversation.otherRole, 'doctor');
      expect(conversation.lastMessagePreview, 'مرحبا Hello');
      expect(conversation.createdAt.isUtc, isTrue);
    },
  );

  test('accepted conversation state is derived only from backend fields', () {
    final accepted = CareConversation.fromJson({
      ..._conversation(),
      'request_status': 'accepted',
      'status': 'active',
    });
    final closed = CareConversation.fromJson({
      ..._conversation(),
      'request_status': 'accepted',
      'status': 'closed',
    });

    expect(accepted.isAccepted, isTrue);
    expect(closed.isAccepted, isFalse);
  });

  test('message page preserves chronological messages and opaque cursors', () {
    final page = MessagePage.fromJson({
      'items': [
        _message('1', '2026-08-29T10:00:00Z'),
        _message('2', '2026-08-29T10:01:00Z'),
      ],
      'next_cursor': 'opaque-older',
      'latest_cursor': 'opaque-latest',
    });

    expect(page.items.map((message) => message.body), ['body-1', 'body-2']);
    expect(page.nextCursor, 'opaque-older');
    expect(page.latestCursor, 'opaque-latest');
  });

  test(
    'optimistic message keeps client identity across failed retry state',
    () {
      final optimistic = CareMessage.optimistic(
        conversationId: _conversationId,
        senderUserId: _userId,
        clientMessageId: _clientId,
        body: 'One logical send',
        createdAt: DateTime.utc(2026, 8, 29),
      );
      final failed = optimistic.copyWith(
        deliveryState: MessageDeliveryState.failed,
        errorCode: 'SERVICE_UNAVAILABLE',
      );

      expect(failed.clientMessageId, _clientId);
      expect(failed.stableKey, _clientId);
      expect(failed.errorCode, 'SERVICE_UNAVAILABLE');
    },
  );

  test('doctor and patient recipients use localized fallback names safely', () {
    final doctor = MessagingRecipient.doctor({
      'id': _userId,
      'first_name_ar': 'ليلى',
      'last_name_ar': 'حسن',
      'first_name_en': 'Layla',
      'last_name_en': 'Hasan',
      'specialty_ar': 'طب الأسرة',
    });
    final patient = MessagingRecipient.patient({
      'id': _clientId,
      'first_name_en': 'Sami',
      'city': 'Ramallah',
    });

    expect(doctor.displayName(true), 'ليلى حسن');
    expect(doctor.displayName(false), 'Layla Hasan');
    expect(doctor.specialty(false), 'طب الأسرة');
    expect(patient.kind, RecipientKind.patient);
    expect(patient.displayName(false), 'Sami');
  });

  test(
    'patient messaging preference preserves the backend boolean exactly',
    () {
      expect(
        PatientMessagingPreference.fromJson({
          'allow_doctor_messages': true,
        }).allowDoctorMessages,
        isTrue,
      );
      expect(
        PatientMessagingPreference.fromJson({
          'allow_doctor_messages': false,
        }).allowDoctorMessages,
        isFalse,
      );
    },
  );

  test('patient messaging preference rejects missing or coerced values', () {
    expect(
      () => PatientMessagingPreference.fromJson(const {}),
      throwsFormatException,
    );
    expect(
      () => PatientMessagingPreference.fromJson({'allow_doctor_messages': 1}),
      throwsFormatException,
    );
  });

  test(
    'malformed required ids, dates, counts, and message bodies fail closed',
    () {
      final malformed = <Map<String, dynamic>>[
        {..._conversation(), 'id': 7},
        {..._conversation(), 'created_at': 'not-a-date'},
        {..._conversation(), 'unread_count': -1},
      ];
      for (final json in malformed) {
        expect(() => CareConversation.fromJson(json), throwsFormatException);
      }
      expect(
        () => CareMessage.fromJson({..._message('1', _now), 'body': ''}),
        throwsFormatException,
      );
    },
  );
}

const _conversationId = '123e4567-e89b-42d3-a456-426614174000';
const _userId = '223e4567-e89b-42d3-a456-426614174001';
const _clientId = '323e4567-e89b-42d3-a456-426614174002';
const _now = '2026-08-29T12:00:00Z';

Map<String, dynamic> _conversation() => {
  'id': _conversationId,
  'status': 'active',
  'conversation_type': 'patient_doctor',
  'request_status': 'pending',
  'initiated_by_user_id': _userId,
  'request_updated_at': _now,
  'created_at': _now,
  'last_message_at': _now,
  'other_role': 'doctor',
  'other_avatar_url': null,
  'other_display_name': 'Dr Layla',
  'last_message_id': _clientId,
  'last_message_preview': 'مرحبا Hello',
  'last_sender_user_id': _userId,
  'last_message_created_at': _now,
  'can_respond_to_request': true,
  'unread_count': 3,
};

Map<String, dynamic> _message(String suffix, String createdAt) => {
  'id': '423e4567-e89b-42d3-a456-42661417400$suffix',
  'conversation_id': _conversationId,
  'sender_user_id': _userId,
  'client_message_id': '523e4567-e89b-42d3-a456-42661417400$suffix',
  'body': 'body-$suffix',
  'message_type': 'text',
  'created_at': createdAt,
};

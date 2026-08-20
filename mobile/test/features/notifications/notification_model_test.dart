import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/notifications/models/notification_model.dart';

void main() {
  group('NotificationModel.fromJson', () {
    test('parses Arabic and English title/message fields', () {
      final model = NotificationModel.fromJson({
        'id': 'notif-1',
        'notification_type': 'appointment',
        'title_ar': 'موعد جديد',
        'title_en': 'New appointment',
        'message_ar': 'تم تأكيد موعدك',
        'message_en': 'Your appointment is confirmed',
        'is_read': false,
        'created_at': '2026-08-05T10:00:00.000Z',
        'read_at': null,
      });

      expect(model.id, 'notif-1');
      expect(model.notificationType, 'appointment');
      expect(model.titleAr, 'موعد جديد');
      expect(model.titleEn, 'New appointment');
      expect(model.messageAr, 'تم تأكيد موعدك');
      expect(model.messageEn, 'Your appointment is confirmed');
    });

    test('parses read state — is_read true with a read_at timestamp', () {
      final model = NotificationModel.fromJson({
        'id': 'notif-2',
        'notification_type': 'reminder',
        'title_ar': 'ت',
        'title_en': 'T',
        'message_ar': 'م',
        'message_en': 'M',
        'is_read': true,
        'created_at': '2026-08-05T09:00:00.000Z',
        'read_at': '2026-08-05T09:30:00.000Z',
      });

      expect(model.isRead, isTrue);
      expect(model.readAt, DateTime.parse('2026-08-05T09:30:00.000Z'));
    });

    test('parses unread state — is_read false with a null read_at', () {
      final model = NotificationModel.fromJson({
        'id': 'notif-3',
        'notification_type': 'system',
        'title_ar': 'ت',
        'title_en': 'T',
        'message_ar': 'م',
        'message_en': 'M',
        'is_read': false,
        'created_at': '2026-08-05T09:00:00.000Z',
        'read_at': null,
      });

      expect(model.isRead, isFalse);
      expect(model.readAt, isNull);
    });

    test('parses createdAt from an ISO timestamp string', () {
      final model = NotificationModel.fromJson({
        'id': 'notif-4',
        'notification_type': 'system',
        'title_ar': 'ت',
        'title_en': 'T',
        'message_ar': 'م',
        'message_en': 'M',
        'is_read': false,
        'created_at': '2026-08-05T12:34:56.000Z',
      });

      expect(model.createdAt, DateTime.parse('2026-08-05T12:34:56.000Z'));
    });

    test('ignores extra fields only present on the mutation-endpoint response shape', () {
      // PUT /notifications/:id/read echoes back extra columns the GET list
      // never includes (user_id, reference_id, reference_type, channel,
      // email_sent_at) — none of them should surface anywhere on the model.
      final model = NotificationModel.fromJson({
        'id': 'notif-5',
        'user_id': 'user-1',
        'notification_type': 'appointment',
        'title_ar': 'ت',
        'title_en': 'T',
        'message_ar': 'م',
        'message_en': 'M',
        'reference_id': 'appt-1',
        'reference_type': 'appointment',
        'channel': 'in_app',
        'is_read': true,
        'read_at': '2026-08-05T09:30:00.000Z',
        'email_sent_at': null,
        'created_at': '2026-08-05T09:00:00.000Z',
      });

      expect(model.id, 'notif-5');
      expect(model.isRead, isTrue);
    });

    test('missing optional fields (read_at) are handled safely', () {
      final model = NotificationModel.fromJson({
        'id': 'notif-6',
        'notification_type': 'system',
        'title_ar': 'ت',
        'title_en': 'T',
        'message_ar': 'م',
        'message_en': 'M',
        'is_read': false,
        'created_at': '2026-08-05T09:00:00.000Z',
        // read_at omitted entirely, not just null.
      });

      expect(model.readAt, isNull);
    });

    test('missing/malformed required-looking fields never throw — safe fallbacks instead', () {
      expect(() => NotificationModel.fromJson(const {}), returnsNormally);

      final model = NotificationModel.fromJson(const {});
      expect(model.id, isEmpty);
      expect(model.notificationType, isEmpty);
      expect(model.titleAr, isEmpty);
      expect(model.titleEn, isEmpty);
      expect(model.messageAr, isEmpty);
      expect(model.messageEn, isEmpty);
      expect(model.isRead, isFalse);
      expect(model.readAt, isNull);
    });

    test('a numeric id is coerced to a string', () {
      final model = NotificationModel.fromJson({'id': 12345});
      expect(model.id, '12345');
    });
  });

  group('NotificationModel.copyWith', () {
    test('copyWith isRead=true sets readAt when provided', () {
      final createdAt = DateTime.parse('2026-08-05T09:00:00.000Z');
      final original = NotificationModel(
        id: 'notif-1',
        notificationType: 'appointment',
        titleAr: 'ع',
        titleEn: 'T',
        messageAr: 'م',
        messageEn: 'M',
        isRead: false,
        createdAt: createdAt,
      );
      final readAt = DateTime.parse('2026-08-05T10:00:00.000Z');

      final updated = original.copyWith(isRead: true, readAt: readAt);

      expect(updated.isRead, isTrue);
      expect(updated.readAt, readAt);
      expect(updated.id, original.id);
      expect(updated.titleEn, original.titleEn);
      expect(updated.createdAt, createdAt);
    });
  });
}

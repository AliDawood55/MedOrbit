import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/virtual_doctor/models/consultation_models.dart';

void main() {
  test('message and recovered-session models preserve supported optional fields', () {
    final message = MessageResult.fromJson({'session_id': 's', 'reply': 'reply', 'phase': 'assessment', 'recommended_specialty_id': 'cardiology', 'recommended_specialty_name_en': 'Cardiology', 'recommended_specialty_name_ar': 'قلب', 'differential': [{'name': 'x'}], 'profile_snapshot': {'age': 30}, 'urgency_level': 'urgent', 'confidence': 0.8});
    expect(message.recommendedSpecialtyId, 'cardiology'); expect(message.differential, hasLength(1)); expect(message.profileSnapshot['age'], 30);
    final restored = RestoredSessionResult.fromJson({'session_id': 's', 'language': 'en', 'messages': [{'role': 'assistant', 'text': '101'}], 'unknown': true});
    expect(restored.messages.single.isDoctor, isTrue); expect(restored.extra['unknown'], isTrue);
  });
}

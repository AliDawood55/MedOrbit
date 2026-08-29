import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/care/models/my_doctor_model.dart';

Map<String, dynamic> _fullDoctor() => {
      'id': 'doctor-1',
      'email': 'doc@example.com',
      'first_name_ar': 'أحمد',
      'last_name_ar': 'محمود',
      'first_name_en': 'Ahmad',
      'last_name_en': 'Mahmoud',
      'phone': '0599000000',
      'profile_image_url': '/uploads/avatars/1.jpg',
      'specialty_ar': 'قلب',
      'specialty_en': 'Cardiology',
      'consultation_fee': 120,
      'average_rating': 4.6,
      'relationship_started_at': '2026-01-05',
      'relationship_source': 'appointment',
      'next_appointment_date': '2026-09-01',
      'last_appointment_date': '2026-07-01',
      'has_upcoming': true,
    };

void main() {
  group('MyDoctorModel.fromJson', () {
    test('parses a fully populated row', () {
      final doctor = MyDoctorModel.fromJson(_fullDoctor());

      expect(doctor.id, 'doctor-1');
      expect(doctor.displayName(false), 'Ahmad Mahmoud');
      expect(doctor.displayName(true), 'أحمد محمود');
      expect(doctor.displaySpecialty(false), 'Cardiology');
      expect(doctor.consultationFee, 120);
      expect(doctor.averageRating, 4.6);
      expect(doctor.hasUpcoming, isTrue);
    });

    test('missing required UUID throws FormatException', () {
      final json = _fullDoctor()..remove('id');
      expect(() => MyDoctorModel.fromJson(json), throwsFormatException);
    });

    test('blank id throws FormatException', () {
      final json = _fullDoctor()..['id'] = '';
      expect(() => MyDoctorModel.fromJson(json), throwsFormatException);
    });

    test('optional bilingual fields null falls back to email', () {
      final doctor = MyDoctorModel.fromJson({'id': 'doctor-2', 'email': 'doc2@example.com'});

      expect(doctor.displayName(false), 'doc2@example.com');
      expect(doctor.displaySpecialty(false), isNull);
      expect(doctor.averageRating, isNull);
    });

    test('avatar null renders as null, never a broken placeholder value', () {
      final doctor = MyDoctorModel.fromJson({'id': 'doctor-3'});
      expect(doctor.profileImageUrl, isNull);
    });

    test('dates null are treated as absent, not fabricated', () {
      final doctor = MyDoctorModel.fromJson({'id': 'doctor-4'});
      expect(doctor.relationshipStartedAt, isNull);
      expect(doctor.nextAppointmentDate, isNull);
      expect(doctor.lastAppointmentDate, isNull);
      expect(doctor.hasUpcoming, isFalse);
    });

    test('a structured id value still fails loudly rather than stringifying', () {
      expect(
        () => MyDoctorModel.fromJson({'id': <String, dynamic>{}}),
        throwsFormatException,
      );
    });
  });
}

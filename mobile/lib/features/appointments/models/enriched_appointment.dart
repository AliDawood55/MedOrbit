import '../../../shared/utils/localized_field.dart';
import 'appointment_model.dart';

/// `GET /appointments` rows have no joined doctor/clinic name (unlike the
/// records timeline endpoint) — the web app enriches each row with one
/// `GET /doctors/:id` / `GET /clinics/:id` call per unique id
/// (`my-appointments.js:105-129`). This wraps that enrichment result.
class EnrichedAppointment {
  const EnrichedAppointment({
    required this.appointment,
    this.doctorNameAr,
    this.doctorNameEn,
    this.clinicNameAr,
    this.clinicNameEn,
  });

  final AppointmentModel appointment;
  final String? doctorNameAr;
  final String? doctorNameEn;
  final String? clinicNameAr;
  final String? clinicNameEn;

  String? doctorName(bool isArabic) {
    final value = localizedField(isArabic: isArabic, ar: doctorNameAr, en: doctorNameEn);
    return value.isEmpty ? null : value;
  }

  String? clinicName(bool isArabic) {
    final value = localizedField(isArabic: isArabic, ar: clinicNameAr, en: clinicNameEn);
    return value.isEmpty ? null : value;
  }

  EnrichedAppointment copyWith({AppointmentModel? appointment}) {
    return EnrichedAppointment(
      appointment: appointment ?? this.appointment,
      doctorNameAr: doctorNameAr,
      doctorNameEn: doctorNameEn,
      clinicNameAr: clinicNameAr,
      clinicNameEn: clinicNameEn,
    );
  }
}

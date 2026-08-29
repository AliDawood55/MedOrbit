import '../../../shared/utils/json_parsing.dart';

/// One row of `GET /appointments` — `SELECT *` on `medorbit.appointments`.
/// Only the columns the UI needs.
class AppointmentModel {
  const AppointmentModel({
    required this.id,
    required this.appointmentNumber,
    required this.doctorId,
    this.clinicId,
    required this.scheduledDate,
    required this.startTime,
    required this.endTime,
    required this.appointmentType,
    required this.status,
    this.reasonForVisit,
  });

  final String id;
  final String appointmentNumber;
  final String doctorId;
  final String? clinicId;
  final String scheduledDate; // DATE, "YYYY-MM-DD"-ish — see parseDateOnly
  final String startTime; // TIME, "HH:mm:ss"
  final String endTime;
  final String appointmentType; // 'in_person' | 'telemedicine'
  final String status; // scheduled|confirmed|in_progress|completed|cancelled|no_show
  final String? reasonForVisit;

  /// Throws a [FormatException] naming the missing/malformed field if a
  /// required identity/schedule/status field is absent or not a usable
  /// string — booking data must fail loudly rather than show a fabricated
  /// id, date, or status. Every required field here is a `UUID`/`VARCHAR`/
  /// `DATE`/`TIME NOT NULL` column (`db/02_dependent_tables.sql`'s
  /// `appointments` table), never numeric or boolean in a well-formed
  /// response, so no scalar coercion is applied.
  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: requireExactString(json, 'id'),
      appointmentNumber: requireExactString(json, 'appointment_number'),
      doctorId: requireExactString(json, 'doctor_id'),
      clinicId: optionalExactString(json, 'clinic_id'),
      scheduledDate: requireExactString(json, 'scheduled_date'),
      startTime: requireExactString(json, 'start_time'),
      endTime: requireExactString(json, 'end_time'),
      appointmentType: optionalExactString(json, 'appointment_type') ?? 'in_person',
      status: requireExactString(json, 'status'),
      reasonForVisit: optionalExactString(json, 'reason_for_visit'),
    );
  }

  AppointmentModel copyWith({String? status}) {
    return AppointmentModel(
      id: id,
      appointmentNumber: appointmentNumber,
      doctorId: doctorId,
      clinicId: clinicId,
      scheduledDate: scheduledDate,
      startTime: startTime,
      endTime: endTime,
      appointmentType: appointmentType,
      status: status ?? this.status,
      reasonForVisit: reasonForVisit,
    );
  }
}

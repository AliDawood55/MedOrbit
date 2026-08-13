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

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['id'].toString(),
      appointmentNumber: json['appointment_number'] as String,
      doctorId: json['doctor_id'].toString(),
      clinicId: json['clinic_id']?.toString(),
      scheduledDate: json['scheduled_date'] as String,
      startTime: json['start_time'] as String,
      endTime: json['end_time'] as String,
      appointmentType: json['appointment_type'] as String? ?? 'in_person',
      status: json['status'] as String,
      reasonForVisit: json['reason_for_visit'] as String?,
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

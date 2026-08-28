class DoctorSchedule {
  const DoctorSchedule({
    required this.isAcceptingPatients,
    required this.appointments,
    required this.weeklyAvailability,
    required this.overrides,
  });

  final bool isAcceptingPatients;
  final List<DoctorScheduleAppointment> appointments;
  final List<DoctorAvailability> weeklyAvailability;
  final List<DoctorAvailability> overrides;

  factory DoctorSchedule.fromJson(Map<String, dynamic> json) => DoctorSchedule(
        isAcceptingPatients: json['doctor'] is Map
            ? (json['doctor'] as Map)['is_accepting_patients'] == true
            : false,
        appointments: _mapList(json['appointments'], DoctorScheduleAppointment.fromJson),
        weeklyAvailability: _mapList(json['weekly'], DoctorAvailability.fromJson),
        overrides: _mapList(json['overrides'], DoctorAvailability.fromJson),
      );
}

class DoctorScheduleAppointment {
  const DoctorScheduleAppointment({
    required this.id,
    required this.number,
    required this.scheduledDate,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.status,
    this.patientNameAr,
    this.patientNameEn,
  });

  final String id;
  final String number;
  final String scheduledDate;
  final String startTime;
  final String endTime;
  final String type;
  final String status;
  final String? patientNameAr;
  final String? patientNameEn;

  String patientName(bool ar) {
    final preferred = ar ? patientNameAr : patientNameEn;
    final fallback = ar ? patientNameEn : patientNameAr;
    return (preferred?.trim().isNotEmpty == true ? preferred : fallback)?.trim() ?? '';
  }

  DoctorScheduleAppointment copyWith({String? status}) => DoctorScheduleAppointment(
        id: id,
        number: number,
        scheduledDate: scheduledDate,
        startTime: startTime,
        endTime: endTime,
        type: type,
        status: status ?? this.status,
        patientNameAr: patientNameAr,
        patientNameEn: patientNameEn,
      );

  factory DoctorScheduleAppointment.fromJson(Map<String, dynamic> json) {
    String name(String first, String last) => [json[first], json[last]]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' ');
    return DoctorScheduleAppointment(
      id: '${json['id'] ?? ''}',
      number: '${json['appointment_number'] ?? ''}',
      scheduledDate: '${json['scheduled_date'] ?? ''}',
      startTime: '${json['start_time'] ?? ''}',
      endTime: '${json['end_time'] ?? ''}',
      type: '${json['appointment_type'] ?? 'in_person'}',
      status: '${json['status'] ?? 'scheduled'}',
      patientNameAr: name('first_name_ar', 'last_name_ar'),
      patientNameEn: name('first_name_en', 'last_name_en'),
    );
  }
}

class DoctorAvailability {
  const DoctorAvailability({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.dayOfWeek,
    this.specificDate,
    this.type = 'available',
    this.isActive = true,
  });

  final String id;
  final String startTime;
  final String endTime;
  final int? dayOfWeek;
  final String? specificDate;
  final String type;
  final bool isActive;

  factory DoctorAvailability.fromJson(Map<String, dynamic> json) => DoctorAvailability(
        id: '${json['id'] ?? ''}',
        startTime: '${json['start_time'] ?? ''}',
        endTime: '${json['end_time'] ?? ''}',
        dayOfWeek: json['day_of_week'] is num ? (json['day_of_week'] as num).toInt() : null,
        specificDate: json['specific_date']?.toString(),
        type: '${json['availability_type'] ?? 'available'}',
        isActive: json['is_active'] != false,
      );
}

List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) fromJson) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => fromJson(Map<String, dynamic>.from(item))).toList();
}

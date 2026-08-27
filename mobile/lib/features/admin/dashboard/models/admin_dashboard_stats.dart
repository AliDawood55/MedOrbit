/// Aggregate, non-clinical platform counts returned to an authorized
/// administrator by `GET /dashboard/stats`.
class AdminDashboardStats {
  const AdminDashboardStats({
    required this.usersTotal,
    required this.patients,
    required this.doctors,
    required this.appointmentsTotal,
    required this.recordsTotal,
    required this.prescriptionsTotal,
    this.averageRating,
  });

  final int usersTotal;
  final int patients;
  final int doctors;
  final int appointmentsTotal;
  final int recordsTotal;
  final int prescriptionsTotal;
  final double? averageRating;

  factory AdminDashboardStats.fromJson(Map<String, dynamic> json) {
    final users = _map(json['users']);
    final appointments = _map(json['appointments']);
    final records = _map(json['medical_records']);
    final prescriptions = _map(json['prescriptions']);
    final ratings = _map(json['ratings']);

    return AdminDashboardStats(
      usersTotal: _integer(users['total']),
      patients: _integer(users['patients']),
      doctors: _integer(users['doctors']),
      appointmentsTotal: _integer(appointments['total']),
      recordsTotal: _integer(records['total']),
      prescriptionsTotal: _integer(prescriptions['total']),
      averageRating: _decimalOrNull(ratings['average']),
    );
  }
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? Map<String, dynamic>.from(value)
    : const <String, dynamic>{};

int _integer(Object? value) => value is num
    ? value.toInt()
    : int.tryParse(value?.toString() ?? '') ?? 0;

double? _decimalOrNull(Object? value) {
  if (value == null) return null;
  return value is num ? value.toDouble() : double.tryParse(value.toString());
}

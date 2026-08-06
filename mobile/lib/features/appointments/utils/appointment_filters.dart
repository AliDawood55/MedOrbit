import '../../../core/utils/date_formatting.dart';
import '../models/enriched_appointment.dart';

bool isPastAppointment(EnrichedAppointment entry) {
  final status = entry.appointment.status;
  if (status == 'completed' || status == 'no_show') return true;

  final date = parseDateOnly(entry.appointment.scheduledDate);
  final today = DateTime.now();
  final todayDateOnly = DateTime(today.year, today.month, today.day);
  return DateTime(date.year, date.month, date.day).isBefore(todayDateOnly);
}

bool isUpcomingAppointment(EnrichedAppointment entry) {
  return entry.appointment.status != 'cancelled' && !isPastAppointment(entry);
}

// Mirrors `ai-service/virtual_doctor/schemas.py`. Field names are the
// service's snake_case wire format, unchanged.

class StartResult {
  const StartResult({required this.sessionId, required this.reply, required this.phase, required this.language});

  final String sessionId;
  final String reply;
  final String phase;

  /// Echoed back by the service so the client can pin STT to this language
  /// for every turn — Whisper's auto-detect is unreliable on short answers.
  final String language;

  factory StartResult.fromJson(Map<String, dynamic> json) => StartResult(
    sessionId: json['session_id'] as String,
    reply: json['reply'] as String? ?? '',
    phase: json['phase'] as String? ?? 'intake',
    language: json['language'] as String? ?? 'en',
  );
}

class RestoredSessionResult {
  const RestoredSessionResult({required this.sessionId, this.language, this.phase, this.chiefComplaint, this.profileSnapshot = const {}, this.urgencyLevel, this.recommendedSpecialtyId, this.specialtyEn, this.specialtyAr, this.differential = const [], this.messages = const [], this.extra = const {}});
  final String sessionId; final String? language; final String? phase; final String? chiefComplaint; final Map<String, dynamic> profileSnapshot; final String? urgencyLevel; final String? recommendedSpecialtyId; final String? specialtyEn; final String? specialtyAr; final List<Map<String, dynamic>> differential; final List<TranscriptEntry> messages; final Map<String, dynamic> extra;
  factory RestoredSessionResult.fromJson(Map<String, dynamic> json) { final profile = json['profile_snapshot']; final rawMessages = json['messages']; return RestoredSessionResult(sessionId: json['session_id']?.toString() ?? '', language: json['language'] as String?, phase: json['phase'] as String?, chiefComplaint: json['chief_complaint'] as String?, profileSnapshot: profile is Map ? Map<String, dynamic>.from(profile) : const {}, urgencyLevel: json['urgency_level'] as String?, recommendedSpecialtyId: json['recommended_specialty_id']?.toString(), specialtyEn: json['recommended_specialty_name_en'] as String?, specialtyAr: json['recommended_specialty_name_ar'] as String?, differential: _listMap(json['differential']), messages: rawMessages is List ? rawMessages.whereType<Map>().map((item) { final map = Map<String, dynamic>.from(item); return TranscriptEntry(text: map['text']?.toString() ?? map['message']?.toString() ?? '', isDoctor: map['is_doctor'] == true || map['role'] == 'assistant'); }).where((item) => item.text.isNotEmpty).toList() : const [], extra: Map<String, dynamic>.fromEntries(json.entries.where((entry) => !const {'session_id','language','phase','chief_complaint','profile_snapshot','urgency_level','recommended_specialty_id','recommended_specialty_name_en','recommended_specialty_name_ar','differential','messages'}.contains(entry.key)))); }
}

class MessageResult {
  const MessageResult({
    required this.sessionId,
    required this.reply,
    required this.phase,
    this.chiefComplaint,
    this.urgencyLevel,
    this.recommendedSpecialtyId,
    this.specialtyEn,
    this.specialtyAr,
    this.confidence,
    this.differential = const [],
    this.profileSnapshot = const {},
  });

  final String sessionId;
  final String reply;
  final String phase;
  final String? chiefComplaint;
  final String? urgencyLevel;
  final String? recommendedSpecialtyId;
  final String? specialtyEn;
  final String? specialtyAr;
  final double? confidence;
  final List<Map<String, dynamic>> differential;
  final Map<String, dynamic> profileSnapshot;

  bool get isComplete => phase == 'complete';
  bool get isEmergency => urgencyLevel == 'emergency' || urgencyLevel == 'urgent';

  factory MessageResult.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['profile_snapshot'];
    return MessageResult(
      sessionId: json['session_id'] as String,
      reply: json['reply'] as String? ?? '',
      phase: json['phase'] as String? ?? '',
      chiefComplaint: json['chief_complaint'] as String?,
      urgencyLevel: json['urgency_level'] as String?,
      recommendedSpecialtyId: json['recommended_specialty_id']?.toString(),
      specialtyEn: json['recommended_specialty_name_en'] as String?,
      specialtyAr: json['recommended_specialty_name_ar'] as String?,
      confidence: _asDouble(json['confidence']),
      differential: _listMap(json['differential']),
      profileSnapshot: rawProfile is Map
          ? Map<String, dynamic>.from(rawProfile)
          : const {},
    );
  }
}

class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.timedOut,
    this.detectedLanguage,
    this.metadata = const {},
  });

  final String text;

  /// The service returns 200 with empty text + this flag when decoding hit
  /// its deadline, so the client asks the patient to repeat rather than
  /// showing a failure.
  final bool timedOut;
  final String? detectedLanguage;
  final Map<String, dynamic> metadata;

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) => TranscriptionResult(
    text: (json['text'] as String? ?? '').trim(),
    timedOut: json['timed_out'] as bool? ?? false,
    detectedLanguage: json['detected_language'] as String?,
    metadata: json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : const {},
  );
}

class ReportResult {
  const ReportResult({
    required this.reportId,
    required this.downloadUrl,
    this.sessionId,
    this.urgencyLevel,
    this.recommendedSpecialtyNameEn,
    this.recommendedSpecialtyNameAr,
  });

  final String reportId;
  final String? sessionId;

  /// Service-relative, e.g. `/virtual-doctor/report/<id>/download`.
  final String downloadUrl;
  final String? urgencyLevel;
  final String? recommendedSpecialtyNameEn;
  final String? recommendedSpecialtyNameAr;

  factory ReportResult.fromJson(Map<String, dynamic> json) => ReportResult(
    reportId: json['report_id']?.toString() ?? '',
    sessionId: json['session_id']?.toString(),
    downloadUrl: json['download_url'] as String? ?? '',
    urgencyLevel: json['urgency_level'] as String?,
    recommendedSpecialtyNameEn: json['recommended_specialty_name_en'] as String?,
    recommendedSpecialtyNameAr: json['recommended_specialty_name_ar'] as String?,
  );
}

/// One line in the on-screen conversation.
class TranscriptEntry {
  const TranscriptEntry({required this.text, required this.isDoctor});

  final String text;
  final bool isDoctor;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

List<Map<String, dynamic>> _listMap(Object? value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
}

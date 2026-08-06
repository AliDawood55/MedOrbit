/// Mirrors `TriageResponse.triage_level` in `ai-service/chatbot/main.py`.
/// Any value the client doesn't recognize is treated as [routine] — this is
/// the least urgent framing, so an unexpected string never causes an
/// under-reaction to be skipped in favor of an over-reaction, and it never
/// crashes the UI.
enum TriageLevel {
  emergency,
  urgent,
  routine;

  static TriageLevel fromWire(String? value) => switch (value) {
    'emergency' => TriageLevel.emergency,
    'urgent' => TriageLevel.urgent,
    _ => TriageLevel.routine,
  };
}

/// Parses the AI service's flat `TriageResponse` body directly — `/triage`
/// has no `{success, data}` envelope, unlike every backend-proxied endpoint
/// elsewhere in the app. Only the fields the result card actually renders are
/// modeled; `specialty_scores` and `matched_keywords` are internal ranking
/// detail the web UI doesn't surface either.
class SymptomCheckResult {
  const SymptomCheckResult({
    required this.id,
    required this.symptoms,
    required this.triageLevel,
    required this.confidenceScore,
    required this.recommendations,
    required this.followUpAction,
    this.recommendedSpecialtyId,
    this.recommendedSpecialtyNameEn,
    this.recommendedSpecialtyNameAr,
  });

  final String id;
  final List<String> symptoms;
  final TriageLevel triageLevel;

  /// 0.0-1.0, straight from the server. Never adjusted or rounded here — the
  /// UI decides display formatting, this model keeps the raw value.
  final double confidenceScore;

  /// Server-generated, English-only. There is no Arabic variant on the
  /// backend, so this is shown as-is regardless of app locale.
  final String recommendations;

  final String followUpAction;
  final String? recommendedSpecialtyId;
  final String? recommendedSpecialtyNameEn;
  final String? recommendedSpecialtyNameAr;

  factory SymptomCheckResult.fromJson(Map<String, dynamic> json) {
    return SymptomCheckResult(
      id: json['id'] as String? ?? '',
      symptoms: (json['symptoms'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      triageLevel: TriageLevel.fromWire(json['triage_level'] as String?),
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      recommendations: json['recommendations'] as String? ?? '',
      followUpAction: json['follow_up_action'] as String? ?? '',
      recommendedSpecialtyId: json['recommended_specialty_id'] as String?,
      recommendedSpecialtyNameEn:
          json['recommended_specialty_name_en'] as String?,
      recommendedSpecialtyNameAr:
          json['recommended_specialty_name_ar'] as String?,
    );
  }
}

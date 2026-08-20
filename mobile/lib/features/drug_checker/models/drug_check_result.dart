/// Mirrors `DrugInteractionMatcher._classify_severity()` in
/// `ai-service/chatbot/medical/drug_interaction_matcher.py`. Any wire value
/// the client doesn't recognize is treated as [unknown] — the same bucket the
/// server itself falls back to when it can't classify a description, so this
/// never crashes the UI and never invents a severity the server didn't say.
enum DrugSeverity {
  severe,
  moderate,
  mild,
  unknown;

  static DrugSeverity fromWire(String? value) => switch (value) {
    'severe' => DrugSeverity.severe,
    'moderate' => DrugSeverity.moderate,
    'mild' => DrugSeverity.mild,
    _ => DrugSeverity.unknown,
  };
}

/// One interacting pair from `DrugCheckResponse.interactions`. `description`
/// is server-generated, English-only free text (drawn from a database
/// column) — there is no Arabic variant on the backend, so it is shown as-is
/// regardless of app locale, the same known limitation as Symptom Checker's
/// `recommendations` field.
class DrugInteraction {
  const DrugInteraction({
    required this.drug1NameEn,
    required this.drug1NameAr,
    required this.drug2NameEn,
    required this.drug2NameAr,
    required this.severity,
    required this.description,
  });

  final String? drug1NameEn;
  final String? drug1NameAr;
  final String? drug2NameEn;
  final String? drug2NameAr;
  final DrugSeverity severity;
  final String description;

  factory DrugInteraction.fromJson(Map<String, dynamic> json) {
    final drug1 = json['drug_1'] as Map<String, dynamic>? ?? const {};
    final drug2 = json['drug_2'] as Map<String, dynamic>? ?? const {};
    return DrugInteraction(
      drug1NameEn: drug1['name_en'] as String?,
      drug1NameAr: drug1['name_ar'] as String?,
      drug2NameEn: drug2['name_en'] as String?,
      drug2NameAr: drug2['name_ar'] as String?,
      severity: DrugSeverity.fromWire(json['severity'] as String?),
      description: json['description'] as String? ?? '',
    );
  }
}

/// Parses the AI service's flat `DrugCheckResponse` body directly —
/// `/drug-interactions` has no `{success, data}` envelope, same as
/// `/triage`. There is no dosage field anywhere in this contract.
class DrugCheckResult {
  const DrugCheckResult({
    required this.hasInteractions,
    required this.interactionCount,
    required this.interactions,
    required this.severitySummary,
  });

  final bool hasInteractions;
  final int interactionCount;
  final List<DrugInteraction> interactions;

  /// `{severity: count}`, e.g. `{'severe': 1, 'moderate': 2}`.
  final Map<String, int> severitySummary;

  factory DrugCheckResult.fromJson(Map<String, dynamic> json) {
    final rawSummary = json['severity_summary'] as Map<String, dynamic>? ?? const {};
    return DrugCheckResult(
      hasInteractions: json['has_interactions'] as bool? ?? false,
      interactionCount: json['interaction_count'] as int? ?? 0,
      interactions: (json['interactions'] as List<dynamic>? ?? const [])
          .map((e) => DrugInteraction.fromJson(e as Map<String, dynamic>))
          .toList(),
      severitySummary: rawSummary.map(
        (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
      ),
    );
  }
}

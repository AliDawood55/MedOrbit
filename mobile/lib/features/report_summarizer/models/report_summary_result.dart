/// Parses the AI service's flat `POST /summarize` response body directly —
/// no `{success, data}` envelope, same as Symptom Checker's `/triage` and
/// Drug Checker's `/drug-interactions`.
class ReportSummaryResult {
  const ReportSummaryResult({
    required this.id,
    required this.summaryAr,
    required this.summaryEn,
    required this.extractedText,
    required this.processingTimeMs,
    required this.modelUsed,
    required this.sourceFileType,
  });

  final String id;
  final String summaryAr;
  final String summaryEn;
  final String extractedText;
  final int processingTimeMs;
  final String modelUsed;
  final String sourceFileType;

  factory ReportSummaryResult.fromJson(Map<String, dynamic> json) {
    return ReportSummaryResult(
      id: json['id'] as String? ?? '',
      summaryAr: json['summary_ar'] as String? ?? '',
      summaryEn: json['summary_en'] as String? ?? '',
      extractedText: json['extracted_text'] as String? ?? '',
      processingTimeMs: (json['processing_time_ms'] as num?)?.toInt() ?? 0,
      modelUsed: json['model_used'] as String? ?? '',
      sourceFileType: json['source_file_type'] as String? ?? '',
    );
  }
}

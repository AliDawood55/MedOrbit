/// Which backend source a [MyReportItem] came from. Only [reportSummary] is
/// populated as of this iteration — `report_summarizations` is the only
/// table with both a `user_id` column and a listing endpoint
/// (`GET /api/reports/summaries`). [generatedReport] and [virtualDoctor] are
/// modeled now so the UI and unified list don't need to change shape later:
///
/// - `generated_reports` was inspected and deliberately excluded: it has no
///   `user_id` (only `generated_by`), its only existing route
///   (`GET /api/reports`) is admin-only with zero ownership filtering, and
///   its content is admin-wide analytics exports (all appointments, all
///   prescriptions, …), not a patient's own reports — a patient would never
///   have rows there since only admins can trigger generation.
/// - `virtual_doctor_reports` has a `session_id` → `virtual_doctor_sessions.user_id`
///   join path but no listing endpoint exists yet on the backend. Adding one
///   was out of scope for this iteration to keep the change focused; the
///   mobile app already has full create/download support for a single
///   session's report (`VirtualDoctorApi.createReport`/`downloadReport`).
enum MyReportType { reportSummary, generatedReport, virtualDoctor }

/// A unified, read-only view of one report the patient can see in My
/// Reports. `extractedTextPreview` is always server-truncated — the full
/// extracted text is never requested or received by mobile.
class MyReportItem {
  const MyReportItem({
    required this.id,
    required this.type,
    required this.createdAt,
    this.title,
    this.summaryAr,
    this.summaryEn,
    this.extractedTextPreview,
    this.modelUsed,
    this.sourceFileType,
    this.downloadUrl,
    this.status,
  });

  final String id;
  final MyReportType type;
  final DateTime createdAt;

  /// Raw title if the backend ever supplies one. Null for
  /// `report_summarizations` today — the screen derives a localized display
  /// title from [type] instead of hardcoding English text here.
  final String? title;

  final String? summaryAr;
  final String? summaryEn;
  final String? extractedTextPreview;
  final String? modelUsed;
  final String? sourceFileType;

  /// Present only for source types that have a downloadable artifact
  /// (a future `generatedReport`/`virtualDoctor` item). Always null for
  /// `reportSummary` — a summary has no separate file, just stored text.
  final String? downloadUrl;

  final String? status;

  /// Parses one row from `GET /api/reports/summaries`
  /// (`backend/src/routes/report.routes.js`): `id, summary_ar, summary_en,
  /// extracted_text_preview, model_used, source_file_type, created_at`.
  factory MyReportItem.fromReportSummaryJson(Map<String, dynamic> json) {
    return MyReportItem(
      id: json['id'] as String? ?? '',
      type: MyReportType.reportSummary,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      summaryAr: json['summary_ar'] as String?,
      summaryEn: json['summary_en'] as String?,
      extractedTextPreview: json['extracted_text_preview'] as String?,
      modelUsed: json['model_used'] as String?,
      sourceFileType: json['source_file_type'] as String?,
    );
  }
}

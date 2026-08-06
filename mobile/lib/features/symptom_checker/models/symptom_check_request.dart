/// Request body for the AI service's `POST /triage` — exactly the shape the
/// web client sends (`frontend/src/js/symptom-checker.js`): a plain list of
/// symptom strings, no `user_id`/`session_id` even for a signed-in patient.
class SymptomCheckRequest {
  const SymptomCheckRequest({required this.symptoms});

  final List<String> symptoms;

  Map<String, dynamic> toJson() => {'symptoms': symptoms};
}

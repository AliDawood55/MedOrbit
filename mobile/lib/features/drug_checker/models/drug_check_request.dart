/// Request body for the AI service's `POST /drug-interactions` — exactly the
/// shape the web client sends (`frontend/src/js/drug-checker.js`): a plain
/// list of medication name strings. The AI service also accepts
/// `medication_ids`, but the web client never sends it, so neither does this.
class DrugCheckRequest {
  const DrugCheckRequest({required this.medicationNames});

  final List<String> medicationNames;

  Map<String, dynamic> toJson() => {'medication_names': medicationNames};
}

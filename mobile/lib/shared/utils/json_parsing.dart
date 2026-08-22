/// Throws a [FormatException] naming [field] unless `json[field]` is
/// already a non-empty [String]. Never coerces a number, boolean, or
/// structured value into text — reserved for contract fields the backend
/// schema defines as a plain string (UUID/VARCHAR/DATE/TIME columns, auth
/// tokens) where inventing or guessing a value would be worse than failing
/// loudly.
String requireExactString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing or invalid required field "$field"');
}

/// Returns `json[field]` as a trimmed, non-empty [String], or `null` if
/// it's absent, `null`, or any non-string scalar (`num`/`bool` are never
/// stringified into what would read as real text) — the normal shape of an
/// optional presentation field. A structured value (`Map`/`List`) is also
/// treated as absent: for these general-purpose fields, silently omitting
/// a stray object is preferable to failing an entire record over cosmetic
/// detail.
String? optionalExactString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

/// Same as [optionalExactString] for `null`/missing/`num`/`bool`, but
/// throws a [FormatException] naming [field] when the value is a `Map` or
/// `List`. Reserved for fields where a malformed structured value must
/// never be silently dropped — e.g. a prescription medication's name or
/// dosage, where hiding the field would render an incomplete-looking
/// medication line instead of failing loudly.
String? optionalStringOrFail(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is Map || value is List) {
    throw FormatException('Malformed structured value for field "$field"');
  }
  return optionalExactString(json, field);
}

/// Same as [optionalStringOrFail], but also accepts a [num] and stringifies
/// it. Reserved for the one field with an actual product reason to render
/// a number as text — medication quantity, an `INTEGER NOT NULL` column in
/// the backend schema. Never stringifies a [bool].
String? optionalScalarStringOrFail(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is num) return value.toString();
  return optionalStringOrFail(json, field);
}

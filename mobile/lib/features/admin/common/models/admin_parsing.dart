/// Shared, deliberately strict scalar parsing for administration payloads.
///
/// Postgres returns `COUNT(*)`/`bigint` and `NUMERIC` columns as **strings**
/// through `node-postgres` unless the query casts them (`::int`). The admin
/// endpoints do both — `report.service.js` casts the analytics sections but
/// not the headline totals — so every numeric field here accepts either form.
library;

/// A required object field. Throws when the value is not a map.
Map<String, dynamic> adminRequireMap(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('Missing or invalid object field "$field"');
  }
  return Map<String, dynamic>.from(value);
}

/// An optional object field: absent, `null`, or a non-map reads as empty.
Map<String, dynamic> adminOptionalMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};

/// A `UUID`/`VARCHAR NOT NULL` contract field. Never coerces a number or a
/// boolean: inventing an identifier for a malformed row would let the UI act
/// on the wrong record.
String adminRequireString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Missing or invalid required field "$field"');
}

/// An optional presentation string. Blank, missing, numeric, boolean and
/// structured values all read as absent.
String? adminOptionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// A count. Accepts `int`, a whole `num`, and the string form Postgres sends
/// for uncast `COUNT(*)`. Returns `null` rather than guessing on anything else.
int? adminOptionalInt(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// A count that must render as a number. Falls back to `0` — a stat tile
/// showing `0` is honest for an absent aggregate, and is what the web
/// dashboard's `toNumber()` does with the same payload.
int adminInt(Object? value) => adminOptionalInt(value) ?? 0;

/// A decimal such as `ROUND(AVG(...), 2)`, which arrives as a string.
double? adminOptionalDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

/// A boolean column. Postgres booleans arrive as real booleans through the
/// driver; the string forms are accepted defensively but nothing else is
/// coerced, so a missing flag never reads as `true`.
bool adminBool(Object? value, {bool orElse = false}) {
  if (value is bool) return value;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == 't') return true;
    if (normalized == 'false' || normalized == 'f') return false;
  }
  return orElse;
}

/// A required timestamp column.
DateTime adminRequireDate(Map<String, dynamic> json, String field) {
  final parsed = adminOptionalDate(json[field]);
  if (parsed == null) {
    throw FormatException('Missing or invalid required field "$field"');
  }
  return parsed;
}

/// An optional timestamp column.
DateTime? adminOptionalDate(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Joins an Arabic or English `first_name`/`last_name` pair into one display
/// name, matching the web admin pages' `displayName()` helpers.
String adminJoinName(String? first, String? last) =>
    [first?.trim(), last?.trim()]
        .where((part) => part != null && part.isNotEmpty)
        .join(' ')
        .trim();

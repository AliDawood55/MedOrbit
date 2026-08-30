import '../../../../core/network/api_exception.dart';

/// The single failure used whenever an administration endpoint answers with a
/// shape the client cannot trust. Deliberately carries no backend text: admin
/// responses can quote account emails, invitation state, and moderation
/// content, none of which belongs in a rendered error.
const ApiException adminInvalidResponse = ApiException(
  message: 'Unexpected response from the server.',
  code: 'INVALID_RESPONSE',
);

/// Unwraps the backend's `{ success, data }` envelope.
///
/// A `success: false` body (which the backend only produces on a non-2xx
/// status, but which a proxy or a future change could produce on a 200) is
/// converted into an [ApiException] carrying the server's **code** and a
/// generic message. Screens branch on `code` and render their own localized
/// copy, so the backend's English sentence is never shown to a user.
Object? adminEnvelopeData(Object? body) {
  if (body is! Map) throw adminInvalidResponse;
  final envelope = Map<String, dynamic>.from(body);

  if (envelope['success'] == false) {
    final error = envelope['error'];
    final code = error is Map ? error['code'] : null;
    throw ApiException(
      message: 'The request could not be completed.',
      code: code is String && code.isNotEmpty ? code : 'BACKEND_FAILURE',
    );
  }
  if (envelope['success'] != true) throw adminInvalidResponse;

  return envelope['data'];
}

/// `data` as an object, or [adminInvalidResponse].
Map<String, dynamic> adminEnvelopeObject(Object? body) {
  final data = adminEnvelopeData(body);
  if (data is! Map) throw adminInvalidResponse;
  return Map<String, dynamic>.from(data);
}

/// `data` as a list of objects, or [adminInvalidResponse]. A single malformed
/// entry fails the whole read rather than silently shortening an operational
/// list — an admin acting on "everything pending" must not be shown a
/// quietly-truncated queue.
List<Map<String, dynamic>> adminEnvelopeList(Object? body) {
  final data = adminEnvelopeData(body);
  return adminObjectList(data);
}

/// Same contract as [adminEnvelopeList] for a nested array (e.g. the `items`
/// array inside a paginated payload).
List<Map<String, dynamic>> adminObjectList(Object? value) {
  if (value is! List) throw adminInvalidResponse;
  return value.map((item) {
    if (item is! Map) throw adminInvalidResponse;
    return Map<String, dynamic>.from(item);
  }).toList(growable: false);
}

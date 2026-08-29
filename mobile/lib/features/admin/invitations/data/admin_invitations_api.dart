import 'package:dio/dio.dart';

import '../../common/data/admin_response.dart';
import '../models/admin_invitation.dart';

/// Client for `/api/admin/invitations`.
///
/// Role split matters here and is enforced server-side:
///  * list / create / revoke → `authorizeSuperAdmin`
///  * `POST /accept` → `authenticate` only, because the account accepting the
///    invitation is still a patient or doctor at that moment.
///
/// There is no resend endpoint. The web page does not offer one either: a new
/// invitation for the same email is refused with `INVITATION_EXISTS` while one
/// is pending, so "resend" means revoke and create again.
class AdminInvitationsApi {
  AdminInvitationsApi(this._dio);

  final Dio _dio;

  Future<List<AdminInvitation>> list() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/admin/invitations',
    );
    return adminEnvelopeList(
      response.data,
    ).map(AdminInvitation.fromJson).toList(growable: false);
  }

  Future<AdminInvitationCreation> create(String email) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/admin/invitations',
      data: {'email': email.trim().toLowerCase()},
    );
    return AdminInvitationCreation.fromJson(
      adminEnvelopeObject(response.data),
    );
  }

  Future<AdminInvitation> revoke(String invitationId) async {
    final response = await _dio.delete<Map<String, dynamic>>(
      '/admin/invitations/${Uri.encodeComponent(invitationId)}',
    );
    return AdminInvitation.fromJson(adminEnvelopeObject(response.data));
  }

  /// Accepts an invitation for the **currently signed-in** account. The
  /// backend matches the invitation's email against that account and answers
  /// `INVITATION_ACCOUNT_MISMATCH` when they differ.
  Future<void> accept(String token) async {
    await _dio.post<Map<String, dynamic>>(
      '/admin/invitations/accept',
      data: {'token': token},
    );
  }
}

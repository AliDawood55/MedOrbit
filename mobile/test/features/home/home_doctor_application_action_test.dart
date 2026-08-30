import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/home/screens/home_screen.dart';

/// The patient Home shows the Doctor Application quick action for patients
/// only. A full HomeScreen widget test would need a large multi-provider
/// harness that does not exist in this codebase, so — consistent with
/// `test/routes/router_auth_session_test.dart` testing `sessionRedirect` in
/// isolation — the role gate is verified directly here.
void main() {
  test('patient accounts see the Doctor Application quick action', () {
    expect(homeShowsDoctorApplicationAction('patient'), isTrue);
    expect(homeShowsDoctorApplicationAction('Patient'), isTrue);
    expect(homeShowsDoctorApplicationAction(' patient '), isTrue);
  });

  test('doctor, admin, super_admin and unknown roles never see it', () {
    for (final role in const ['doctor', 'admin', 'super_admin', 'reviewer', '']) {
      expect(homeShowsDoctorApplicationAction(role), isFalse, reason: role);
    }
    expect(homeShowsDoctorApplicationAction(null), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/auth/providers/app_role_capabilities_provider.dart';
import 'package:mobile/features/home/screens/home_screen.dart';

void main() {
  test(
    'Home presents one shared Feed capability to every authenticated role',
    () {
      for (final role in ['patient', 'doctor', 'admin', 'super_admin']) {
        final capabilities = AppRoleCapabilities.fromRole(role);
        expect(homeShowsSocialFeedAction(capabilities), isTrue, reason: role);
      }
    },
  );

  test('Home does not present Feed without an authenticated session', () {
    final capabilities = AppRoleCapabilities.fromRole(
      'patient',
      isAuthenticated: false,
    );
    expect(homeShowsSocialFeedAction(capabilities), isFalse);
  });
}

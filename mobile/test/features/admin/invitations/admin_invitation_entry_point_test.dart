import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/features/home/models/user_profile_model.dart';
import 'package:mobile/features/profile/data/profile_api.dart';
import 'package:mobile/features/profile/providers/profile_provider.dart';
import 'package:mobile/features/profile/screens/profile_screen.dart';
import 'package:mobile/routes/route_paths.dart';

import '../admin_test_support.dart';

/// The invitation acceptance screen has no emailed-link entry on mobile (the
/// backend mails a link to the *web* page, and this app claims no app-link
/// domain), so Profile carries the only in-app way in. These cover that it is
/// offered to exactly the accounts that could use it.
UserProfileModel _profile(String role) => UserProfileModel(
  id: adminActorId,
  email: 'operator@medorbit.test',
  role: role,
  firstNameEn: 'Sara',
  lastNameEn: 'Nasser',
);

Future<void> _pump(WidgetTester tester, {required String role}) =>
    pumpAdminScreen(
      tester,
      screen: const ProfileScreen(),
      role: role,
      surfaceSize: const Size(800, 3200),
      overrides: [profileApiProvider.overrideWithValue(_FakeProfileApi(role))],
      extraRoutes: [
        GoRoute(
          path: RoutePaths.adminInvitationAccept,
          builder: (_, _) => const Scaffold(
            body: Text('accept', key: ValueKey('accept-screen')),
          ),
        ),
      ],
    );

void main() {
  testWidgets('a patient is offered the acceptance entry point', (
    tester,
  ) async {
    await _pump(tester, role: 'patient');

    expect(
      find.byKey(const ValueKey('profile-admin-invitation-accept')),
      findsOneWidget,
    );
    expect(find.text(en.adminInvitationAcceptEntryHint), findsOneWidget);
  });

  testWidgets('a doctor is offered it too', (tester) async {
    await _pump(tester, role: 'doctor');

    expect(
      find.byKey(const ValueKey('profile-admin-invitation-accept')),
      findsOneWidget,
    );
  });

  testWidgets('an administrator is not — there is nothing to accept', (
    tester,
  ) async {
    await _pump(tester, role: 'admin');

    expect(
      find.byKey(const ValueKey('profile-admin-invitation-accept')),
      findsNothing,
    );
  });

  testWidgets('a super admin is not offered it either', (tester) async {
    await _pump(tester, role: 'super_admin');

    expect(
      find.byKey(const ValueKey('profile-admin-invitation-accept')),
      findsNothing,
    );
  });

  testWidgets('tapping it opens the acceptance route', (tester) async {
    await _pump(tester, role: 'patient');

    await tapByKey(
      tester,
      const ValueKey('profile-admin-invitation-accept'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('accept-screen')), findsOneWidget);
  });
}

class _FakeProfileApi extends ProfileApi {
  _FakeProfileApi(this._role) : super(Dio());

  final String _role;

  @override
  Future<UserProfileModel> getMe() async => _profile(_role);
}

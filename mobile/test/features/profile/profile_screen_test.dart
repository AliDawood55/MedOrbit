import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/localization/app_strings.dart';
import 'package:mobile/core/network/api_exception.dart';
import 'package:mobile/core/providers/core_providers.dart';
import 'package:mobile/core/storage/secure_storage_service.dart';
import 'package:mobile/core/theme/app_theme.dart';
import 'package:mobile/features/home/models/user_profile_model.dart';
import 'package:mobile/features/profile/data/profile_api.dart';
import 'package:mobile/features/profile/models/profile_edit_model.dart';
import 'package:mobile/features/profile/providers/profile_provider.dart';
import 'package:mobile/features/profile/screens/profile_screen.dart';
import 'package:mobile/features/profile/widgets/change_password_sheet.dart';

const _strings = AppStrings(
  false,
); // English, matching the default direction used below

UserProfileModel _profile({String? avatarUrl}) {
  return UserProfileModel(
    id: 'user-1',
    email: 'sara@example.com',
    role: 'patient',
    firstNameAr: 'سارة',
    lastNameAr: 'أحمد',
    firstNameEn: 'Sara',
    lastNameEn: 'Ahmad',
    avatarUrl: avatarUrl,
    createdAt: DateTime.parse('2026-01-01T00:00:00.000Z'),
  );
}

/// The profile page is long — every section (avatar, form, preferences,
/// password) laid out end-to-end exceeds the default 800x600 test surface,
/// which makes `tester.tap()` fail to hit-test anything below the fold even
/// after `ensureVisible` scrolls it there (the scroll itself works; the
/// surface is just too short for some later assertions in the same test).
/// Growing the surface once up front is simpler and more robust than
/// scrolling per element.
Future<void> _useTallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  testWidgets('shows a loading state while the initial profile is in flight', (
    tester,
  ) async {
    final completer = Completer<UserProfileModel>();
    final api = _FakeProfileApi()..getMeResults.add(completer.future);
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(_profile());
  });

  testWidgets('loads and renders the profile form', (tester) async {
    await _useTallSurface(tester);
    final api = _FakeProfileApi()..getMeResults.add(_profile());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text('Sara Ahmad'), findsOneWidget);
    expect(find.text('sara@example.com'), findsOneWidget);
    expect(find.text(_strings.profileSectionInfo), findsOneWidget);
    expect(find.text(_strings.billingTitle), findsOneWidget);
    expect(find.text(_strings.billingProfileDescription), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(7));
  });

  testWidgets('shows a safe error with retry, and retry reloads the profile', (
    tester,
  ) async {
    final api = _FakeProfileApi()
      ..getMeResults.add(
        const ApiException(
          message: 'Network down',
          code: ApiException.codeServiceUnavailable,
        ),
      )
      ..getMeResults.add(_profile());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    expect(find.text(_strings.profileLoadError), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, _strings.retry));
    await tester.pump();

    expect(find.text('Sara Ahmad'), findsOneWidget);
  });

  testWidgets(
    'editing the English first name and saving sends the updated draft',
    (tester) async {
      await _useTallSurface(tester);
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..updateMeResults.add(null)
        ..getMeResults.add(_profile());
      await tester.pumpWidget(_app(api: api));
      await tester.pump();

      // Field order inside ProfileFormSection: firstNameAr, lastNameAr, firstNameEn, lastNameEn, phone, address, city.
      await tester.enterText(find.byType(TextFormField).at(2), 'Sarah');
      await tester.tap(
        find.widgetWithText(ElevatedButton, _strings.saveChangesAction),
      );
      await tester.pump();
      await tester.pump();

      expect(api.updateMeCalls.single.firstNameEn, 'Sarah');
    },
  );

  testWidgets('cancel reverts an in-progress edit without saving', (
    tester,
  ) async {
    await _useTallSurface(tester);
    final api = _FakeProfileApi()..getMeResults.add(_profile());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(2), 'Something else');
    await tester.tap(
      find.widgetWithText(OutlinedButton, _strings.cancelChangesAction),
    );
    await tester.pump();

    expect(find.text('Something else'), findsNothing);
    expect(find.text('Sara'), findsOneWidget);
    expect(api.updateMeCalls, isEmpty);
  });

  testWidgets(
    'clearing a required name field blocks save with a validation message',
    (tester) async {
      await _useTallSurface(tester);
      final api = _FakeProfileApi()..getMeResults.add(_profile());
      await tester.pumpWidget(_app(api: api));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField).at(2), '');
      await tester.tap(
        find.widgetWithText(ElevatedButton, _strings.saveChangesAction),
      );
      await tester.pump();

      // `ProfileFormSection` calls `Validators.required` directly (not
      // `strings.requiredField`, which has a different, punctuated format).
      expect(
        find.text('${_strings.firstNameEnLabel} is required'),
        findsOneWidget,
      );
      expect(api.updateMeCalls, isEmpty);
    },
  );

  testWidgets(
    'the language selector switches language and syncs to the server',
    (tester) async {
      await _useTallSurface(tester);
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..updateLanguageResults.add(null);
      // `LocaleController` itself defaults to Arabic and only becomes English
      // once its async persisted-load resolves (the fake storage here returns
      // 'en'); an extra pump lets that settle before tapping, so the tap below
      // is a genuine ar<-en selection change rather than a same-value no-op.
      await tester.pumpWidget(_app(api: api));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text(_strings.profileLanguageArOption));
      await tester.pump();
      await tester.pump();

      expect(api.updateLanguageCalls, ['ar']);
    },
  );

  testWidgets('the theme selector updates the selected segment', (
    tester,
  ) async {
    await _useTallSurface(tester);
    final api = _FakeProfileApi()..getMeResults.add(_profile());
    await tester.pumpWidget(_app(api: api));
    await tester.pump();

    await tester.tap(find.text(_strings.themeDarkOption));
    await tester.pump();

    final segmentedButton = tester.widget<SegmentedButton<ThemeMode>>(
      find.byKey(const ValueKey('profile-theme-selector')),
    );
    expect(segmentedButton.selected, {ThemeMode.dark});
  });

  testWidgets(
    'opens the change-password sheet and validates the confirm field',
    (tester) async {
      await _useTallSurface(tester);
      final api = _FakeProfileApi()..getMeResults.add(_profile());
      await tester.pumpWidget(_app(api: api));
      await tester.pump();

      await tester.tap(find.text(_strings.changePasswordAction));
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordSheet), findsOneWidget);

      final sheetFields = find.descendant(
        of: find.byType(ChangePasswordSheet),
        matching: find.byType(TextFormField),
      );
      expect(sheetFields, findsNWidgets(3));

      await tester.enterText(sheetFields.at(0), 'CurrentPass1!');
      await tester.enterText(sheetFields.at(1), 'NewPass1!aaaa');
      await tester.enterText(sheetFields.at(2), 'Mismatch1!aaaa');
      await tester.tap(
        find.descendant(
          of: find.byType(ChangePasswordSheet),
          matching: find.widgetWithText(
            ElevatedButton,
            _strings.changePasswordAction,
          ),
        ),
      );
      await tester.pump();

      expect(find.text(_strings.passwordMismatch), findsOneWidget);
      expect(api.changePasswordCalls, isEmpty);
    },
  );

  testWidgets(
    'a wrong current password shows a safe inline error in the sheet',
    (tester) async {
      await _useTallSurface(tester);
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile())
        ..changePasswordResults.add(
          const ApiException(
            message: 'Current password is incorrect',
            code: 'INVALID_CREDENTIALS',
          ),
        );
      await tester.pumpWidget(_app(api: api));
      await tester.pump();

      await tester.tap(find.text(_strings.changePasswordAction));
      await tester.pumpAndSettle();

      final sheetFields = find.descendant(
        of: find.byType(ChangePasswordSheet),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(sheetFields.at(0), 'WrongCurrent1!');
      await tester.enterText(sheetFields.at(1), 'NewPass1!aaaa');
      await tester.enterText(sheetFields.at(2), 'NewPass1!aaaa');
      await tester.tap(
        find.descendant(
          of: find.byType(ChangePasswordSheet),
          matching: find.widgetWithText(
            ElevatedButton,
            _strings.changePasswordAction,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text(_strings.wrongCurrentPasswordError), findsOneWidget);
    },
  );

  testWidgets(
    'shows the initial-letter avatar fallback when there is no avatar_url',
    (tester) async {
      final api = _FakeProfileApi()
        ..getMeResults.add(_profile(avatarUrl: null));
      await tester.pumpWidget(_app(api: api));
      await tester.pump();

      expect(find.text('S'), findsWidgets);
    },
  );

  testWidgets(
    'tapping change-photo does not crash when the platform picker is unavailable',
    (tester) async {
      final api = _FakeProfileApi()..getMeResults.add(_profile());
      await tester.pumpWidget(_app(api: api));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('profile-change-photo')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(api.uploadAvatarCalls, isEmpty);
    },
  );

  testWidgets('renders in Arabic RTL and at 2x text scale without throwing', (
    tester,
  ) async {
    await _useTallSurface(tester);
    final api = _FakeProfileApi()..getMeResults.add(_profile());
    await tester.pumpWidget(
      _app(
        api: api,
        isArabic: true,
        direction: TextDirection.rtl,
        textScale: 2,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'focusing a field does not throw or leave the save button unreachable',
    (tester) async {
      await _useTallSurface(tester);
      final api = _FakeProfileApi()..getMeResults.add(_profile());
      await tester.pumpWidget(_app(api: api));
      await tester.pump();

      await tester.tap(find.byType(TextFormField).at(2));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(ElevatedButton, _strings.saveChangesAction),
        findsOneWidget,
      );
    },
  );
}

Widget _app({
  required ProfileApi api,
  bool isArabic = false,
  TextDirection direction = TextDirection.ltr,
  double textScale = 1,
}) {
  return ProviderScope(
    overrides: [
      profileApiProvider.overrideWithValue(api),
      // The real secure storage plugin has no backing implementation under
      // `flutter_test` — covers locale, theme, and the change-password
      // success path's forced logout, all of which read/write it.
      secureStorageProvider.overrideWithValue(
        _FakeSecureStorage(isArabic ? 'ar' : 'en'),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(isArabic: isArabic),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: direction,
          child: const ProfileScreen(),
        ),
      ),
    ),
  );
}

class _FakeSecureStorage extends SecureStorageService {
  _FakeSecureStorage(this._languageCode);
  final String _languageCode;

  @override
  Future<String?> getLanguageCode() async => _languageCode;

  @override
  Future<void> saveLanguageCode(String code) async {}

  @override
  Future<String?> getThemeMode() async => null;

  @override
  Future<void> saveThemeMode(String mode) async {}

  @override
  Future<String?> getRefreshToken() async => null;

  @override
  Future<void> clear() async {}
}

class _FakeProfileApi extends ProfileApi {
  _FakeProfileApi() : super(Dio());

  final getMeResults = <Object>[];
  final updateMeResults = <Object?>[];
  final updateLanguageResults = <Object?>[];
  final uploadAvatarResults = <Object>[];
  final changePasswordResults = <Object?>[];

  final updateMeCalls = <ProfileEditModel>[];
  final updateLanguageCalls = <String>[];
  final uploadAvatarCalls = <({String filePath, String fileName})>[];
  final changePasswordCalls = <({String current, String next})>[];

  @override
  Future<UserProfileModel> getMe() {
    final next = getMeResults.removeAt(0);
    if (next is Future<UserProfileModel>) return next;
    if (next is UserProfileModel) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<void> updateMe(ProfileEditModel draft) {
    updateMeCalls.add(draft);
    final next = updateMeResults.removeAt(0);
    if (next is Future) return next as Future<void>;
    if (next == null) return Future.value();
    return Future.error(next);
  }

  @override
  Future<void> updateLanguagePreference(String language) {
    updateLanguageCalls.add(language);
    final next = updateLanguageResults.removeAt(0);
    if (next is Future) return next as Future<void>;
    if (next == null) return Future.value();
    return Future.error(next);
  }

  @override
  Future<String> uploadAvatar({
    required String filePath,
    required String fileName,
  }) {
    uploadAvatarCalls.add((filePath: filePath, fileName: fileName));
    final next = uploadAvatarResults.removeAt(0);
    if (next is Future<String>) return next;
    if (next is String) return Future.value(next);
    return Future.error(next);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) {
    changePasswordCalls.add((current: currentPassword, next: newPassword));
    final next = changePasswordResults.removeAt(0);
    if (next is Future) return next as Future<void>;
    if (next == null) return Future.value();
    return Future.error(next);
  }
}

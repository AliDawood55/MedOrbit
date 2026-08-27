import 'dart:async';

import 'package:dio/dio.dart'; import 'package:flutter/material.dart'; import 'package:flutter_riverpod/flutter_riverpod.dart'; import 'package:flutter_test/flutter_test.dart'; import 'package:mobile/core/localization/app_strings.dart'; import 'package:mobile/core/network/api_exception.dart'; import 'package:mobile/core/providers/core_providers.dart'; import 'package:mobile/core/storage/secure_storage_service.dart'; import 'package:mobile/core/theme/app_theme.dart'; import 'package:mobile/features/chatbot/data/chatbot_api.dart'; import 'package:mobile/features/chatbot/models/chatbot_models.dart'; import 'package:mobile/features/chatbot/providers/chatbot_provider.dart'; import 'package:mobile/features/chatbot/screens/chatbot_screen.dart'; import 'package:mobile/features/chatbot/widgets/chat_route_card.dart';
const _strings = AppStrings(false); // English, matching secureStorageProvider's override below
void main() { testWidgets('empty state, send, result sections, suggestions, and emergency response render', (tester) async { final api = _Api()..responses.add(Future.value(const ChatMessageResponse(conversationId: 'c1', reply: 'For emergencies call 101.', intent: 'emergency', places: [ChatPlaceResult(id: '', nameEn: 'Nablus Hospital')], doctors: [ChatDoctorResult(id: '', firstNameEn: 'Mariam')], route: ChatRouteResult(distanceKm: 2, durationMinutes: 5), suggestions: [ChatSuggestion(text: 'Find a clinic')]))); await tester.pumpWidget(_app(api)); expect(find.text('Start a conversation'), findsOneWidget); await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Help'); await tester.tap(find.byKey(const ValueKey('chat-send'))); await tester.pumpAndSettle(); expect(find.text('Help'), findsOneWidget); expect(find.text('For emergencies call 101.'), findsOneWidget); expect(find.text('Nablus Hospital'), findsOneWidget); final container = ProviderScope.containerOf(tester.element(find.byType(ChatbotScreen))); expect(container.read(chatbotControllerProvider).route, isNotNull); for (var i = 0; i < 4 && find.byType(ChatRouteCard).evaluate().isEmpty; i++) { await tester.drag(find.byType(ListView).first, const Offset(0, -300)); await tester.pump(); } expect(find.byType(ChatRouteCard), findsOneWidget); await tester.tap(find.text('Find a clinic')); expect(find.text('Find a clinic'), findsNWidgets(2)); });

  testWidgets('a free-quota-exhausted send shows a quiet warning notice with no Retry action', (tester) async {
    final completer = Completer<ChatMessageResponse>();
    final api = _Api()..responses.add(completer.future);
    await tester.pumpWidget(_app(api));
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Help');
    // Tapping starts the send, which suspends on `await _api.sendMessage(...)`
    // — completing the error only now (not when the future was created above)
    // keeps a listener attached before completion, matching the pattern
    // `chatbot_provider_test.dart` uses for the same reason.
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    completer.completeError(
      const ApiException(
        message: 'Your free messages are used for this period.',
        code: ApiException.codeFreeQuotaExhausted,
        statusCode: 429,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(_strings.chatErrQuotaTitle), findsOneWidget);
    expect(find.textContaining(_strings.chatErrQuotaMessage), findsOneWidget);
    // A quota denial is not retryable immediately, so no Retry action — and
    // the warning icon (not the error icon) marks it as a product rule, not
    // a broken request.
    expect(find.text(_strings.retry), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('a duplicate-in-flight send still offers Retry', (tester) async {
    final completer = Completer<ChatMessageResponse>();
    final api = _Api()..responses.add(completer.future);
    await tester.pumpWidget(_app(api));
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Help');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    completer.completeError(
      const ApiException(
        message: 'This message is already being processed.',
        code: ApiException.codeDuplicateInFlight,
        statusCode: 409,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(_strings.chatErrDuplicateTitle), findsOneWidget);
    expect(find.text(_strings.retry), findsOneWidget);
  });
}
Widget _app(_Api api) => ProviderScope(overrides: [chatbotApiProvider.overrideWithValue(api), secureStorageProvider.overrideWithValue(_FakeSecureStorage('en'))], child: MaterialApp(theme: AppTheme.light(), home: const ChatbotScreen()));
class _Api extends ChatbotApi { _Api() : super(Dio()); final responses = <Future<ChatMessageResponse>>[]; @override Future<ChatMessageResponse> sendMessage(ChatMessageRequest request) => responses.removeAt(0); }
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
}

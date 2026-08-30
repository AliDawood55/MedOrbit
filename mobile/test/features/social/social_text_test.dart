import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/social/widgets/social_text.dart';

void main() {
  group('autoTextDirection', () {
    test('an Arabic body resolves RTL', () {
      expect(autoTextDirection('اشرب الماء بانتظام'), TextDirection.rtl);
    });

    test('an English body resolves LTR', () {
      expect(autoTextDirection('Drink water regularly'), TextDirection.ltr);
    });

    test('a mixed body follows its first strong character', () {
      expect(
        autoTextDirection('نصيحة: Drink 2L daily'),
        TextDirection.rtl,
        reason: 'the Arabic opener decides, as dir="auto" would',
      );
      expect(autoTextDirection('Tip: اشرب الماء'), TextDirection.ltr);
    });

    test('leading punctuation and digits do not decide direction', () {
      expect(autoTextDirection('"2026 — اشرب الماء'), TextDirection.rtl);
      expect(autoTextDirection('  ... Drink water'), TextDirection.ltr);
    });

    test('text with no strong character inherits from context', () {
      expect(autoTextDirection('2026 — 12:30'), isNull);
      expect(autoTextDirection(''), isNull);
    });
  });

  group('AutoDirectionText', () {
    testWidgets('renders Arabic RTL inside an LTR app', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.ltr,
            child: Scaffold(body: AutoDirectionText('اشرب الماء')),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textDirection, TextDirection.rtl);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders English LTR inside an RTL app', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: AutoDirectionText('Drink water')),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textDirection, TextDirection.ltr);
    });

    testWidgets('direction-neutral text inherits the ambient direction', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: AutoDirectionText('2026')),
          ),
        ),
      );

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.textDirection, isNull);
    });
  });
}

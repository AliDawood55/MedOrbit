import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/social/data/social_api.dart';
import 'package:mobile/features/social/localization/social_strings.dart';
import 'package:mobile/features/social/models/social_models.dart';
import 'package:mobile/features/social/providers/social_providers.dart';
import 'package:mobile/features/social/widgets/post_comments_sheet.dart';
import 'package:mobile/core/providers/core_providers.dart';

/// Reproduces (and, after the fix, disproves) the RenderFlex "BOTTOM
/// OVERFLOWED BY N PIXELS" error: the sheet's SizedBox was a fixed 75% of
/// the *full* screen height, so once the keyboard's viewInsets pushed the
/// sheet's own bottom Padding up, the combined space demanded exceeded what
/// was actually available under the keyboard.
void main() {
  testWidgets(
    'the comments sheet does not overflow when the keyboard opens',
    (tester) async {
      // A typical phone-sized surface with the keyboard already accounted
      // for in viewInsets, the same way the real IME reports it via
      // MediaQuery once it's shown.
      const screenSize = Size(390, 800);
      const keyboardInset = 300.0;

      final container = ProviderContainer(
        overrides: [
          socialApiProvider.overrideWithValue(_FakeSocialApi()),
          socialStringsProvider.overrideWithValue(SocialStrings(false)),
          activeOriginProvider.overrideWithValue('https://example.test'),
        ],
      );
      addTearDown(container.dispose);

      await tester.binding.setSurfaceSize(screenSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: screenSize,
                  viewInsets: EdgeInsets.only(bottom: keyboardInset),
                ),
                // A Column bounded to the viewport height, not a Scaffold —
                // this is what actually turns "requests more height than is
                // available" into the specific "RenderFlex overflowed"
                // assertion: a Column asks its non-flexible child for its
                // natural size with the main axis unbounded, then compares
                // that against its own (here: bounded) height. A Scaffold
                // would instead auto-resize for the keyboard
                // (resizeToAvoidBottomInset) and zero the inset before the
                // widget under test ever saw it, hiding the bug this test
                // exists to catch — the real ModalBottomSheetRoute does no
                // such thing, which is exactly why the widget does its own
                // `Padding(bottom: viewInsets.bottom)`.
                child: SizedBox(
                  height: screenSize.height,
                  child: Material(
                    child: Column(
                      children: [PostCommentsSheet(postId: 'post-1')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Focusing the comment field is the real-world trigger, but the sheet
      // only reacts to MediaQuery's viewInsets (already simulated above) —
      // asserting no overflow after that pump is the direct reproduction.
      await tester.tap(find.byKey(const Key('socialCommentInput')));
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}

class _FakeSocialApi extends SocialApi {
  _FakeSocialApi() : super(Dio());

  @override
  Future<List<PostComment>> getComments(String postId) async => const [];
}

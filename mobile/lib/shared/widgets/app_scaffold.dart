import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Reusable scaffold with opt-in safe-area, responsive padding, content
/// constraints, and keyboard-aware behavior.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.endDrawer,
    this.backgroundColor,
    this.extendBody = false,
    this.resizeToAvoidBottomInset,
    this.padding,
    this.useSafeArea = false,
    this.safeAreaTop = true,
    this.safeAreaBottom = true,
    this.constrainBody = false,
    this.maxContentWidth = AppTheme.maxPhoneContentWidth,
    this.keyboardAware = false,
    this.contentAlignment = AlignmentDirectional.topCenter,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? drawer;
  final Widget? endDrawer;
  final Color? backgroundColor;
  final bool extendBody;
  final bool? resizeToAvoidBottomInset;
  final EdgeInsetsGeometry? padding;
  final bool useSafeArea;
  final bool safeAreaTop;
  final bool safeAreaBottom;
  final bool constrainBody;
  final double maxContentWidth;
  final bool keyboardAware;
  final AlignmentGeometry contentAlignment;

  @override
  Widget build(BuildContext context) {
    Widget buildContent(BuildContext context) {
      Widget content = body;

      if (constrainBody || padding != null) {
        content = LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final resolvedPadding = padding ?? EdgeInsetsDirectional.symmetric(
              horizontal: AppTheme.pageHorizontalPadding(width),
            );

            return Align(
              alignment: contentAlignment,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constrainBody ? maxContentWidth : double.infinity,
                ),
                child: Padding(padding: resolvedPadding, child: content),
              ),
            );
          },
        );
      }

      if (keyboardAware) {
        final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
        content = AnimatedPadding(
          duration: AppTheme.motionDuration(context, AppTheme.motionFast),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: content,
        );
      }

      if (useSafeArea) {
        content = SafeArea(
          top: safeAreaTop,
          bottom: safeAreaBottom,
          child: content,
        );
      }

      return content;
    }

    return Scaffold(
      appBar: appBar,
      body: Builder(builder: buildContent),
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      drawer: drawer,
      endDrawer: endDrawer,
      backgroundColor: backgroundColor,
      extendBody: extendBody,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
    );
  }
}

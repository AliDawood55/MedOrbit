import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/page_sections.dart';

class AuthPageFrame extends StatelessWidget {
  const AuthPageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    this.leading,
    this.actions,
    this.maxWidth = AppTheme.maxAuthContentWidth,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget body;
  final Widget? leading;
  final List<Widget>? actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      resizeToAvoidBottomInset: true,
      useSafeArea: true,
      safeAreaTop: false,
      appBar: AppBar(
        automaticallyImplyLeading: leading != null,
        leading: leading,
        title: const Text('MedOrbit'),
        actions: actions,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AuthBackdrop()),
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontal = AppTheme.pageHorizontalPadding(constraints.maxWidth);
              final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
              const verticalPadding = AppTheme.spaceXl * 2;
              final minHeight = (constraints.maxHeight - verticalPadding).clamp(0.0, double.infinity).toDouble();

              return SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsetsDirectional.fromSTEB(
                  horizontal,
                  AppTheme.spaceXl,
                  horizontal,
                  AppTheme.spaceXl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth, minHeight: minHeight),
                    child: Column(
                      mainAxisAlignment: keyboardOpen ? MainAxisAlignment.start : MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PageIntro(title: title, subtitle: subtitle, icon: icon),
                        const SizedBox(height: AppTheme.spaceLg),
                        body,
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: ClipRect(
        child: Stack(
          children: [
            PositionedDirectional(
              top: -170,
              end: -150,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: dark ? 0.14 : 0.09),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: -190,
              start: -150,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppTheme.secondary.withValues(alpha: dark ? 0.11 : 0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

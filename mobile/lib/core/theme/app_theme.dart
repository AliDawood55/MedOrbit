import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared MedOrbit visual tokens, aligned with `frontend/src/css/main.css`.
class AppTheme {
  AppTheme._();

  // Responsive breakpoints.
  static const double compactBreakpoint = 360;
  static const double wideBreakpoint = 600;
  static const double maxPhoneContentWidth = 720;
  static const double maxAuthContentWidth = 560;

  // Brand.
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryTint = Color(0xFFEFF6FF);
  static const Color primaryTintStrong = Color(0xFFDBEAFE);
  static const Color secondary = Color(0xFF10B981);
  static const Color accent = Color(0xFFF59E0B);
  static const Color violet = Color(0xFF7C3AED);

  // Semantic.
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  static const Color info = Color(0xFF06B6D4);

  // Light surfaces and content.
  static const Color backgroundLight = Color(0xFFF9FAFB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceElevatedLight = Color(0xFFFFFFFF);
  static const Color surfaceMutedLight = Color(0xFFF3F4F6);
  static const Color textLight = Color(0xFF111827);
  static const Color textMutedLight = Color(0xFF4B5563);
  static const Color textFaintLight = Color(0xFF6B7280);
  static const Color borderSubtleLight = Color(0xFFE5E7EB);
  static const Color borderStrongLight = Color(0xFFD1D5DB);

  // Dark surfaces and content.
  static const Color backgroundDark = Color(0xFF0B1220);
  static const Color surfaceMutedDark = Color(0xFF111827);
  static const Color surfaceDark = Color(0xFF1F2937);
  static const Color surfaceElevatedDark = Color(0xFF1F2937);
  static const Color textDark = Color(0xFFF9FAFB);
  static const Color textMutedDark = Color(0xFFE5E7EB);
  static const Color textFaintDark = Color(0xFF9CA3AF);
  static const Color borderSubtleDark = Color(0xFF374151);
  static const Color borderStrongDark = Color(0xFF4B5563);

  // Gradients.
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, violet],
  );
  static const LinearGradient secondaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [secondary, info],
  );
  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, danger],
  );

  // Radius scale.
  static const double radiusXs = 4;
  static const double radiusSm = 6;
  static const double radiusMd = 10;
  static const double radiusLg = 14;
  static const double radiusXl = 18;
  static const double radius2xl = 24;
  static const double radiusPill = 999;

  // Spacing scale.
  static const double space2xs = 2;
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceLg = 16;
  static const double spaceXl = 24;
  static const double space2xl = 32;
  static const double space3xl = 40;
  static const double space4xl = 48;

  // Typography scale.
  static const double fontXs = 11;
  static const double fontSm = 12;
  static const double fontMd = 14;
  static const double fontLg = 16;
  static const double fontXl = 20;
  static const double font2xl = 24;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightSemibold = FontWeight.w600;
  static const FontWeight weightBold = FontWeight.w700;
  static const FontWeight weightExtraBold = FontWeight.w800;

  // Elevation and shadows.
  static const double elevation0 = 0;
  static const double elevation1 = 1;
  static const double elevation2 = 2;
  static const double elevation3 = 4;

  static const List<BoxShadow> shadowXsLight = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowSmLight = [
    BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> shadowMdLight = [
    BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> shadowXsDark = [
    BoxShadow(color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowSmDark = [
    BoxShadow(color: Color(0x4D000000), blurRadius: 5, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> shadowMdDark = [
    BoxShadow(color: Color(0x52000000), blurRadius: 12, offset: Offset(0, 5)),
  ];

  // Icon and touch-target sizes.
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 24;
  static const double iconXl = 32;
  static const double icon2xl = 48;
  static const double minTouchTarget = 48;

  // Motion tokens. Widgets should pass these through [motionDuration].
  static const Duration motionFast = Duration(milliseconds: 150);
  static const Duration motionBase = Duration(milliseconds: 250);
  static const Duration motionSlow = Duration(milliseconds: 400);

  static bool isCompactWidth(double width) => width < compactBreakpoint;

  static bool isWideWidth(double width) => width >= wideBreakpoint;

  static bool usesLargeText(
    BuildContext context, {
    double threshold = 1.3,
  }) =>
      MediaQuery.textScalerOf(context).scale(1) > threshold;

  static bool prefersReducedMotion(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    return media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
  }

  static IconData directionalForwardIconOf(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl
          ? Icons.arrow_back_rounded
          : Icons.arrow_forward_rounded;

  static double pageHorizontalPadding(double width) {
    if (width < compactBreakpoint) return spaceMd;
    if (width < wideBreakpoint) return spaceLg;
    return spaceXl;
  }

  static Color mutedSurfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? surfaceMutedDark : surfaceMutedLight;

  static Color faintTextOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? textFaintDark : textFaintLight;

  static Color strongBorderOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? borderStrongDark : borderStrongLight;

  static List<BoxShadow> shadowSmOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? shadowSmDark : shadowSmLight;

  static Duration motionDuration(BuildContext context, Duration duration) {
    return prefersReducedMotion(context) ? Duration.zero : duration;
  }

  static TextTheme _textTheme(bool isArabic, Color textColor, Color mutedText) {
    final base = isArabic ? GoogleFonts.cairoTextTheme() : GoogleFonts.interTextTheme();
    return base
        .copyWith(
          headlineSmall: base.headlineSmall?.copyWith(
            fontSize: font2xl,
            height: 1.3,
            fontWeight: weightExtraBold,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: fontXl,
            height: 1.35,
            fontWeight: weightBold,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: fontLg,
            height: 1.4,
            fontWeight: weightBold,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: fontMd,
            height: 1.4,
            fontWeight: weightSemibold,
          ),
          bodyLarge: base.bodyLarge?.copyWith(fontSize: fontLg, height: 1.55),
          bodyMedium: base.bodyMedium?.copyWith(fontSize: fontMd, height: 1.55),
          bodySmall: base.bodySmall?.copyWith(fontSize: fontSm, height: 1.5, color: mutedText),
          labelLarge: base.labelLarge?.copyWith(fontSize: fontMd, fontWeight: weightBold),
          labelMedium: base.labelMedium?.copyWith(fontSize: fontSm, fontWeight: weightSemibold),
          labelSmall: base.labelSmall?.copyWith(fontSize: fontXs, fontWeight: weightSemibold),
        )
        .apply(bodyColor: textColor, displayColor: textColor);
  }

  static ThemeData light({bool isArabic = true}) {
    const colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      tertiary: accent,
      onTertiary: Colors.white,
      error: danger,
      onError: Colors.white,
      surface: surfaceLight,
      onSurface: textLight,
      onSurfaceVariant: textMutedLight,
      outline: borderSubtleLight,
      outlineVariant: borderStrongLight,
    );
    return _build(
      colorScheme: colorScheme,
      isArabic: isArabic,
      background: backgroundLight,
      surface: surfaceLight,
      mutedSurface: surfaceMutedLight,
      text: textLight,
      mutedText: textMutedLight,
      border: borderSubtleLight,
    );
  }

  static ThemeData dark({bool isArabic = true}) {
    const colorScheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      tertiary: accent,
      onTertiary: Colors.white,
      error: danger,
      onError: Colors.white,
      surface: surfaceDark,
      onSurface: textDark,
      onSurfaceVariant: textMutedDark,
      outline: borderSubtleDark,
      outlineVariant: borderStrongDark,
    );
    return _build(
      colorScheme: colorScheme,
      isArabic: isArabic,
      background: backgroundDark,
      surface: surfaceDark,
      mutedSurface: surfaceMutedDark,
      text: textDark,
      mutedText: textMutedDark,
      border: borderSubtleDark,
    );
  }

  static ThemeData _build({
    required ColorScheme colorScheme,
    required bool isArabic,
    required Color background,
    required Color surface,
    required Color mutedSurface,
    required Color text,
    required Color mutedText,
    required Color border,
  }) {
    final textTheme = _textTheme(isArabic, text, mutedText);
    final roundedMedium = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd));

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      textTheme: textTheme,
      dividerColor: border,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: elevation0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: const IconThemeData(size: iconLg),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: elevation0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceMd),
        hintStyle: textTheme.bodyMedium?.copyWith(color: mutedText),
        helperStyle: textTheme.bodySmall,
        errorMaxLines: 3,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusMd)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceMd),
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primary.withValues(alpha: 0.45),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.9),
          elevation: elevation1,
          shape: roundedMedium,
          textStyle: textTheme.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceMd),
          shape: roundedMedium,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: spaceLg, vertical: spaceMd),
          side: BorderSide(color: border),
          shape: roundedMedium,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          padding: const EdgeInsets.symmetric(horizontal: spaceMd, vertical: spaceSm),
          shape: roundedMedium,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(minTouchTarget, minTouchTarget)),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primary.withValues(alpha: 0.12),
        elevation: elevation2,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : mutedText,
            size: iconLg,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: mutedText,
        indicatorColor: primary,
        dividerColor: border,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
        showDragHandle: true,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: text,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: background),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMd)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: mutedSurface,
        selectedColor: primary.withValues(alpha: 0.12),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusPill)),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: spaceSm, vertical: spaceXs),
      ),
    );
  }
}

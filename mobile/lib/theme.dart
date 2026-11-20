import 'package:flutter/material.dart';

/// Font families: Space Grotesk for headings, Inter for everything else.
class AppFonts {
  static const body = 'Inter';
  static const display = 'SpaceGrotesk';
}

/// Design system: deep black, cinematic, one orange accent, amber for premium.
class AppColors {
  // Accent
  static const primary = Color(0xFFFF7A1A);
  static const primaryDark = Color(0xFFE25A00);
  static const accent = Color(0xFFFFB347);
  static const gold = Color(0xFFFFC24D);

  // Surfaces (darkest → lightest)
  static const background = Color(0xFF0A0A0C);
  static const surface = Color(0xFF141418);
  static const surfaceHigh = Color(0xFF1F1F25);
  static const chip = Color(0xFF17171C);
  static const bubble = Color(0xFF1F1F25); // raised cards / chips
  static const border = Color(0xFF26262E);
  static const borderSoft = Color(0xFF1F1F25);

  // Text
  static const text = Color(0xFFF5F5F7);
  static const muted = Color(0xFFA1A1AA);
  static const subtle = Color(0xFF8A8A94);
  static const link = Color(0xFFFF9A4D);
  static const ink = Color(0xFF1A1005); // text on gold/orange

  // Status
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFFB347);
  static const danger = Color(0xFFFF5A5F);
  static const successBg = Color(0xFF10261D);
  static const warningBg = Color(0xFF2A1F10);
  static const dangerBg = Color(0xFF2B1414);

  /// Hero areas (premium card, splash, avatars, CTAs).
  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF5F1F), Color(0xFFFF8A00), Color(0xFFFFB347)],
  );

  /// Top bars: near-black with a faint warm glow in the corner.
  static const Gradient barGradient = RadialGradient(
    center: Alignment(1.1, -2.2),
    radius: 2.4,
    colors: [Color(0xFF2A1406), Color(0xFF0A0A0C)],
    stops: [0, 0.75],
  );

  /// Subtle warm-dark fill for placeholders and soft cards.
  static const softGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E1B22), Color(0xFF141418)],
  );

  /// Warm glow behind headers (top-right orange haze).
  static const glow = RadialGradient(
    center: Alignment(0.9, -1.2),
    radius: 1.3,
    colors: [Color(0x55FF6A00), Color(0x00FF6A00)],
  );

  /// Bottom fade over thumbnails so overlay text stays readable.
  static const scrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00000000), Color(0xB3000000)],
  );
}

/// Spacing and radius scale used across screens.
class Gap {
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
}

class Radii {
  static const card = 18.0;
  static const button = 14.0;
  static const chip = 999.0;
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primary,
        onPrimary: AppColors.ink,
        secondary: AppColors.accent,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.danger,
      ).copyWith(
        surfaceContainerLowest: AppColors.background,
        surfaceContainerLow: AppColors.surface,
        surfaceContainer: AppColors.surface,
        surfaceContainerHigh: AppColors.surfaceHigh,
        surfaceContainerHighest: AppColors.surfaceHigh,
        outline: AppColors.border,
        outlineVariant: AppColors.border,
        onSurfaceVariant: AppColors.muted,
      );

  final base = ThemeData(
    colorScheme: scheme,
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: AppFonts.body,
  );
  final text = base.textTheme
      .merge(
        const TextTheme(
          headlineSmall: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
          titleLarge: TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 15, height: 1.45),
          bodyMedium: TextStyle(fontSize: 14, height: 1.45),
          bodySmall: TextStyle(fontSize: 12),
          labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      )
      .apply(
        fontFamily: AppFonts.body,
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Radii.button),
  );
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.button),
    borderSide: BorderSide(color: c, width: w),
  );

  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    visualDensity: VisualDensity.compact,
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 60,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.text,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.text,
      unselectedLabelColor: AppColors.muted,
      indicatorColor: AppColors.primary,
      dividerColor: Colors.transparent,
      labelStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.muted,
      textColor: AppColors.text,
      minVerticalPadding: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    iconTheme: const IconThemeData(color: AppColors.text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.surfaceHigh,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(0, 50),
        elevation: 0,
        shape: rounded,
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.surfaceHigh,
        foregroundColor: AppColors.text,
        shape: rounded,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: Color(0xFF3A3A44), width: 1.2),
        shape: rounded,
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.link,
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.muted,
        selectedBackgroundColor: AppColors.text,
        selectedForegroundColor: AppColors.background,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.ink,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.subtle),
      labelStyle: const TextStyle(color: AppColors.muted),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
      border: field(AppColors.border),
      enabledBorder: field(AppColors.border),
      focusedBorder: field(AppColors.primary, 1.6),
      errorBorder: field(AppColors.danger),
      focusedErrorBorder: field(AppColors.danger, 1.6),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.chip,
      selectedColor: AppColors.primary,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.text,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      checkmarkColor: AppColors.ink,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        fontFamily: AppFonts.display,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: AppFonts.body,
        fontSize: 14,
        height: 1.45,
        color: AppColors.muted,
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.text,
      ),
      actionTextColor: AppColors.primary,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.surfaceHigh,
      circularTrackColor: Colors.transparent,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: Color(0x40FFFFFF),
      thumbColor: Colors.white,
      trackHeight: 3,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Colors.white : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.surfaceHigh,
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.muted,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : Colors.transparent,
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF111114),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: const Color(0x26FF7A1A),
      indicatorShape: const StadiumBorder(),
      overlayColor: const WidgetStatePropertyAll(Color(0x14FF7A1A)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: AppFonts.body,
          fontSize: 11,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 24,
          color: s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.muted,
        ),
      ),
    ),
  );
}

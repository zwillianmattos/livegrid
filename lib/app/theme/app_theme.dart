import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const background = Color(0xFF0A0A0A);
  static const surface = Color(0xFF141414);
  static const surfaceHigh = Color(0xFF1E1E1E);
  static const hairline = Color(0x1AFFFFFF);
  static const hairlineStrong = Color(0x33FFFFFF);

  static const text = Color(0xFFFFFFFF);
  static const textMuted = Color(0xB3FFFFFF);
  static const textSubtle = Color(0x80FFFFFF);
  static const textFaint = Color(0x4DFFFFFF);

  static const live = Color(0xFFEF4444);
  static const safe = Color(0xFF10B981);
  static const warn = Color(0xFFF59E0B);
  static const edit = Color(0xFFF59E0B);
  static const info = Color(0xFF60A5FA);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    const accent = AppColors.live;
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: Colors.white,
        secondary: AppColors.edit,
        onSecondary: Colors.black,
        surface: AppColors.background,
        onSurface: AppColors.text,
        surfaceContainerHighest: AppColors.surface,
        outline: AppColors.hairline,
        outlineVariant: AppColors.hairlineStrong,
      ),
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.textMuted, size: 20),
      textTheme: const TextTheme(
        displayLarge: TextStyle(color: AppColors.text),
        displayMedium: TextStyle(color: AppColors.text),
        headlineMedium: TextStyle(
          color: AppColors.text,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: TextStyle(color: AppColors.textMuted, fontSize: 13),
        bodySmall: TextStyle(color: AppColors.textSubtle, fontSize: 12),
        labelSmall: TextStyle(
          color: AppColors.textSubtle,
          fontSize: 10,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.textMuted, width: 1.2),
        ),
        labelStyle: const TextStyle(color: AppColors.textSubtle, fontSize: 12),
        hintStyle: const TextStyle(color: AppColors.textFaint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 2,
        activeTrackColor: AppColors.text,
        inactiveTrackColor: AppColors.hairlineStrong,
        thumbColor: AppColors.text,
        overlayColor: AppColors.text.withValues(alpha: 0.08),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        valueIndicatorColor: AppColors.surface,
        valueIndicatorTextStyle: const TextStyle(
          color: AppColors.text,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.text,
          foregroundColor: Colors.black,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.text,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.text
              : AppColors.textFaint,
        ),
      ),
    );
    return base;
  }

  static TextStyle numeric({
    double size = 12,
    Color color = AppColors.text,
    FontWeight weight = FontWeight.w600,
  }) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: 0.2,
      );

  static TextStyle label({
    double size = 10,
    Color color = AppColors.textSubtle,
  }) =>
      TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
      );
}

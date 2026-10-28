import 'package:flutter/material.dart';

/// Colors shared by the theme and a few custom widgets.
abstract final class AppColors {
  static const ink = Color(0xFF142421);
  static const teal = Color(0xFF0F4C4A);
  static const tealSoft = Color(0xFFE5F2F0);
  static const copper = Color(0xFFB8612E);
  static const copperSoft = Color(0xFFF8EBE3);
  static const copperInk = Color(0xFF6A3A1C);
  static const cream = Color(0xFFF3F0EA);
  static const line = Color(0xFFE3DDD3);
  static const muted = Color(0xFF3E514C);
}

ThemeData buildAppTheme() {
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.teal,
        brightness: Brightness.light,
      ).copyWith(
        primary: AppColors.teal,
        onPrimary: Colors.white,
        primaryContainer: AppColors.tealSoft,
        onPrimaryContainer: AppColors.teal,
        secondary: AppColors.copper,
        onSecondary: Colors.white,
        secondaryContainer: AppColors.copperSoft,
        onSecondaryContainer: AppColors.copperInk,
        surface: Colors.white,
        onSurface: AppColors.ink,
        onSurfaceVariant: AppColors.muted,
        outline: AppColors.line,
        outlineVariant: AppColors.line,
        error: const Color(0xFF9B2C2C),
        onError: Colors.white,
      );

  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.cream,
    dividerColor: AppColors.line,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        fontFamily: 'Roboto',
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: rounded,
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Roboto',
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: AppColors.tealSoft,
      checkmarkColor: AppColors.teal,
      labelStyle: const TextStyle(
        color: AppColors.ink,
        fontWeight: FontWeight.w600,
        fontFamily: 'Roboto',
      ),
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.teal,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.tealSoft,
      height: 68,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          fontFamily: 'Roboto',
          color: selected ? AppColors.teal : AppColors.muted,
        );
      }),
    ),
  );
}

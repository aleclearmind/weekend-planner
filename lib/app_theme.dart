import 'package:flutter/material.dart';

abstract final class AppColors {
  static const ink = Color(0xFF171D19);
  static const muted = Color(0xFF3F4943);
  static const faint = Color(0xFF6F7A72);
  static const canvas = Color(0xFFF6FBF6);
  static const outer = Color(0xFFDCE3DC);
  static const surface = Color(0xFFF1F6F1);
  static const surfaceStrong = Color(0xFFEDF3ED);
  static const nav = Color(0xFFEAF1EA);
  static const primary = Color(0xFF1F6B54);
  static const primaryDark = Color(0xFF0B2E22);
  static const primaryContainer = Color(0xFFD3E8DC);
  static const accent = Color(0xFFA6F2D8);
  static const warning = Color(0xFF7A4A00);
  static const warningContainer = Color(0xFFFFE0B2);
  static const border = Color(0xFFC3CDC5);
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
        surface: AppColors.canvas,
      ).copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.primaryDark,
        surface: AppColors.canvas,
        onSurface: AppColors.ink,
        outline: AppColors.faint,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 23,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35, color: AppColors.ink),
      bodySmall: TextStyle(
        fontSize: 12.5,
        height: 1.35,
        color: AppColors.muted,
      ),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 20,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surfaceStrong,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: false,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(13)),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.faint),
        borderRadius: BorderRadius.all(Radius.circular(13)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(13)),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    ),
    chipTheme: const ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
      ),
      side: BorderSide(color: AppColors.border),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primaryDark,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 76,
      backgroundColor: AppColors.nav,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: Color(0xFF002015),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(17)),
      ),
    ),
  );
}
